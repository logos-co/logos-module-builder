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

  # STOPGAP-CTOR-REGEX: drop this once logos-cpp-sdk's impl_header_parser ctor
  # regex accepts decl-specifiers (`explicit`, etc.). No upstream issue filed yet.
  sanitizeImplHeader = implClass: headerPath: ''
    _sih_p=${headerPath}
    sed -E -i 's/^([[:space:]]*)explicit[[:space:]]+(${implClass}[[:space:]]*\()/\1\2/' "$_sih_p"
    awk '
      BEGIN { depth = 0 }
      /^[[:space:]]*#[[:space:]]*if[[:space:]]+0([[:space:]]|$)/                 { depth++; next }
      depth > 0 && /^[[:space:]]*#[[:space:]]*(ifndef|ifdef|if)([[:space:]]|$)/  { depth++; next }
      depth > 0 && /^[[:space:]]*#[[:space:]]*endif([[:space:]]|$)/              { depth--; next }
      depth == 0
    ' "$_sih_p" > "$_sih_p.tmp" && mv "$_sih_p.tmp" "$_sih_p"
    sed -E -i 's/\bsize_t\b/uint64_t/g; s/\bint\b/int64_t/g' "$_sih_p"
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
        # Universal modules are header-first cdylibs: same Qt-free mechanism as
        # the `cdylib` interface, but the LIDL contract is DERIVED from the impl
        # header instead of hand-committed. The author still writes only the
        # impl class (deriving LogosModuleContext); the module's own TUs stay
        # Qt-free and its outbound modules().<dep> calls go through the lp_* C
        # ABI (apiStyle=lp). Qt is confined to the generated uniform glue.
        #
        # 1. Derive the LIDL contract from the impl header. Doubles as the
        #    published events sidecar consumed by dependents' typed-event codegen.
        #    The header is sanitized into a temp copy first: cpp-generator's
        #    line-based parser can't handle `explicit` ctors, `#if 0` blocks, or
        #    platform-width integer types.
        _codegen_src_dir="$(mktemp -d)"
        cp "${fromPath}" "$_codegen_src_dir/${implHeaderInclude}"
        ${sanitizeImplHeader implClass "\"$_codegen_src_dir/${implHeaderInclude}\""}
        logos-cpp-generator --header-to-lidl "$_codegen_src_dir/${implHeaderInclude}" \
          --impl-class ${implClass} \
          --metadata metadata.json \
          -o ./generated_code/${config.name}.lidl
        # 2. The uniform Qt-plugin glue over the common module-impl C ABI
        #    (logos_host loads it unchanged — load ABI preserved).
        logos-qt-generator --lidl ./generated_code/${config.name}.lidl \
          --backend cdylib \
          --output-dir ./generated_code
        # 3. The Qt-FREE C-ABI export wrapper (+ typed event emitters) around
        #    the hand-written impl class.
        logos-cpp-generator --lidl ./generated_code/${config.name}.lidl \
          --backend cdylib \
          --impl-class ${implClass} \
          --impl-header ${implHeaderInclude} \
          --output-dir ./generated_code
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
      # A rust-first module (codegen.rust.trait) derives its .lidl from the trait;
      # the builder stages it at generated_code/<name>.lidl (mkLogosModule's
      # lidlStaging), so no codegen.lidl is needed. Otherwise it's the committed
      # contract named by codegen.lidl.
      lidlFile =
        if ((cg.rust or {}).trait or null) != null
        then "generated_code/${config.name}.lidl"
        else (cg.lidl or (throw "cdylib interface requires codegen.lidl in metadata.json"));
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
  # <RepClass>SimpleSource + LogosUiPluginContext); the qt generator emits
  # only the *Interface.h and the *Plugin glue that wires the (Qt-typed)
  # LogosModules aggregate into the backend on initLogos.
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

  # preCodegen runs AFTER the protocol-version stamp / external copy / darwin fix
  # but BEFORE codegen — used to stage a builder-derived .lidl (rust-first) into
  # the tree where cdylibCodegen will read codegen.lidl.
  compose = { config, externalLibs, userPre, fixDarwin ? false, copyExternals ? false, protocolVersion ? null, preCodegen ? "" }:
    let
      stamp = stampProtocolVersion protocolVersion;
      copy = if copyExternals then copyExternalLibsToLib externalLibs else "";
      codegen = autoCodegen config;
      fix = if fixDarwin then fixupDarwinDylibs else "";
    in
      stamp + copy + fix + preCodegen + codegen + userPre;

in {
  inherit defaultImplClassFromName copyExternalLibsToLib fixupDarwinDylibs sanitizeImplHeader universalCodegen providerCodegen uiCodegen autoCodegen compose stampProtocolVersion;
}
