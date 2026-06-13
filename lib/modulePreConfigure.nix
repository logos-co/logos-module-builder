# Shell snippets prepended to mkLogosModule / mkLogosModuleTests preConfigure.
{ lib }:

let
  # accounts_module -> AccountsModuleImpl
  defaultImplClassFromName = moduleName:
    let
      parts = lib.filter (s: s != "") (lib.splitString "_" moduleName);
      cap = s:
        if s == "" then ""
        else lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (builtins.stringLength s - 1) s;
    in
      lib.concatStrings (map cap parts) + "Impl";

  # Copy resolved external library outputs into ./lib for CMake EXTERNAL_LIBS / includes
  copyExternalLibsToLib = externalLibs:
    let
      names = builtins.attrNames externalLibs;
      one = name:
        let
          v = externalLibs.${name};
        in
          if v == null then ""
          else ''
            if [ -d "${v}/lib" ]; then
              cp -f "${v}"/lib/* lib/ 2>/dev/null || true
            fi
            if [ -d "${v}/include" ]; then
              cp -f "${v}"/include/*.h lib/ 2>/dev/null || true
            fi
          '';
    in
      if names == [] then ""
      else ''
        mkdir -p lib
        ${lib.concatMapStringsSep "\n" one names}
      '';

  # macOS: fix install_name on copied dylibs so tests/runtime resolve via RPATH
  fixupDarwinDylibs = ''
    if [ "$(uname -s)" = Darwin ]; then
      for f in lib/*.dylib; do
        [ -f "$f" ] || continue
        bn=$(basename "$f")
        install_name_tool -id "@rpath/$bn" "$f" 2>/dev/null || true
      done
    fi
  '';

  universalCodegen = config:
    let
      cg = config.codegen or {};
      implClass = cg.impl_class or (defaultImplClassFromName config.name);
      ihRaw = cg.impl_header or "${config.name}_impl.h";
      fromPath =
        if lib.hasInfix "/" ihRaw then ihRaw else "src/${ihRaw}";
      # Include string embedded in generated glue (basename when path is qualified)
      implHeaderInclude =
        if lib.hasInfix "/" ihRaw then builtins.baseNameOf ihRaw else ihRaw;
    in
      ''
        echo "logos-module-builder: generating universal module glue (${config.name})..."
        # Qt glue from the Qt layer's generator; the .lidl sidecar (consumed
        # by dependents' typed-event codegen) from the Qt-free generator.
        logos-qt-generator --from-header "${fromPath}" \
          --backend qt \
          --impl-class ${implClass} \
          --impl-header ${implHeaderInclude} \
          --metadata metadata.json \
          --output-dir ./generated_code
        logos-cpp-generator --header-to-lidl "${fromPath}" \
          --impl-class ${implClass} \
          --metadata metadata.json \
          -o ./generated_code/${config.name}.lidl
      '';

  providerCodegen = config:
    let
      cg = config.codegen or {};
      headerPath =
        if cg ? provider_header then
          cg.provider_header
        else if cg ? impl_header && lib.hasInfix "/" cg.impl_header then
          cg.impl_header
        else
          "src/${config.name}_impl.h";
    in
      ''
        echo "logos-module-builder: generating provider dispatch (${config.name})..."
        logos-cpp-generator --provider-header "$(pwd)/${headerPath}" \
          --output-dir ./generated_code
      '';

  # Cdylib authoring: the module is (or wraps) a cdylib exporting the common
  # module-impl C ABI (logos_module_impl.h in logos-protocol). The generator
  # emits only the uniform Qt-plugin glue from the LIDL contract; the C
  # exports come from the module's own language backend — the C++ SDK's
  # `--from-header --backend cdylib` wrapper or the Rust SDK's
  # `lidl-gen --provider`. The glue is identical either way.
  cdylibCodegen = config:
    let
      cg = config.codegen or {};
      lidlFile = cg.lidl or (throw "cdylib interface requires codegen.lidl in metadata.json");
      # Contract-first C++ flavor: when codegen names an impl_class, the
      # generator ALSO emits the C-ABI export wrapper (+ typed events) around
      # that hand-written Qt-free class. Without it (e.g. Rust modules whose
      # exports come from lidl-gen --provider) only the uniform glue is
      # generated.
      implClass = cg.impl_class or null;
      implHeaderRaw = cg.impl_header or "${config.name}_impl.h";
      implHeader =
        if lib.hasInfix "/" implHeaderRaw
        then builtins.baseNameOf implHeaderRaw
        else implHeaderRaw;
      implFlags =
        if implClass == null then ""
        else "--impl-class ${implClass} --impl-header ${implHeader}";
    in
      ''
        echo "logos-module-builder: generating cdylib Qt glue (${config.name})..."
        logos-qt-generator --lidl "${lidlFile}" \
          --backend cdylib \
          --output-dir ./generated_code
        ${lib.optionalString (implClass != null) ''
          # Contract-first C++ flavor: the Qt-FREE C-ABI export wrapper
          # (+ typed event emitters) around the hand-written impl class.
          logos-cpp-generator --lidl "${lidlFile}" \
            --backend cdylib \
            ${implFlags} \
            --output-dir ./generated_code
        ''}
      '';

  # UI plugin backends (type=ui_qml + interface=universal): the USER
  # writes the .rep (the view contract) and the *Backend class (deriving
  # <RepClass>SimpleSource + LogosModuleContext); the qt generator emits
  # only the *Interface.h and the *Plugin glue that wires
  # LogosModules/context into the backend on initLogos.
  uiCodegen = config:
    let
      cg = config.codegen or {};
      repFile = cg.rep or "src/${config.name}.rep";
      backendFlags =
        lib.optionalString (cg ? backend_class) " --backend-class ${cg.backend_class}"
        + lib.optionalString (cg ? backend_header) " --backend-header ${cg.backend_header}";
    in
      ''
        echo "logos-module-builder: generating ui plugin glue (${config.name})..."
        logos-qt-generator --backend ui \
          --metadata metadata.json \
          --rep "${repFile}"${backendFlags} \
          --output-dir ./generated_code
      '';

  autoCodegen = config:
    if config.interface == "universal" && (config.type or "core") == "ui_qml"
      then uiCodegen config
    else if config.interface == "universal" then universalCodegen config
    else if config.interface == "provider" then providerCodegen config
    else if config.interface == "cdylib" then cdylibCodegen config
    else "";

  # Order: optional ext copy -> optional darwin fixup -> codegen -> user hook
  # Note: mkLogosModule main builds already copy externals in logos-plugin-qt buildPlugin
  # (externalLibCopies). Use copyExternals=true only for contexts without that (e.g. unit tests).
  # Stamp the logos-protocol semver the module is being built against into
  # the metadata.json the plugin embeds (Q_PLUGIN_METADATA). One number
  # governs Logos load/call compatibility (same MAJOR <=> compatible);
  # liblogos reads it pre-load. Runs before cmake/moc so the embedded copy
  # carries the field; modules built by older builders simply lack it and
  # load permissively ("legacy").
  stampProtocolVersion = protocolVersion:
    if protocolVersion == null then "" else ''
      if [ -f ./metadata.json ]; then
        jq '. + {logos_protocol_version: "${protocolVersion}"}' ./metadata.json           > ./metadata.json.lp-stamp && mv ./metadata.json.lp-stamp ./metadata.json
        echo "Stamped logos_protocol_version=${protocolVersion} into metadata.json"
      fi
    '';

  compose = { config, externalLibs, userPre, fixDarwin ? false, copyExternals ? false, protocolVersion ? null }:
    let
      stamp = stampProtocolVersion protocolVersion;
      copy = if copyExternals then copyExternalLibsToLib externalLibs else "";
      codegen = autoCodegen config;
      fix = if fixDarwin then fixupDarwinDylibs else "";
    in
      stamp + copy + fix + codegen + userPre;

in {
  inherit defaultImplClassFromName copyExternalLibsToLib fixupDarwinDylibs universalCodegen providerCodegen uiCodegen autoCodegen compose stampProtocolVersion;
}
