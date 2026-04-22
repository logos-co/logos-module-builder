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
      implClass = cg.impl_class or defaultImplClassFromName config.name;
      ihRaw = cg.impl_header or "${config.name}_impl.h";
      fromPath =
        if lib.hasInfix "/" ihRaw then ihRaw else "src/${ihRaw}";
      # Include string embedded in generated glue (basename when path is qualified)
      implHeaderInclude =
        if lib.hasInfix "/" ihRaw then builtins.baseNameOf ihRaw else ihRaw;
    in
      ''
        echo "logos-module-builder: generating universal module glue (${config.name})..."
        logos-cpp-generator --from-header "${fromPath}" \
          --backend qt \
          --impl-class ${implClass} \
          --impl-header ${implHeaderInclude} \
          --metadata metadata.json \
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

  cFfiCodegen = config:
    let
      cg = config.codegen or {};
      cHeader = cg.c_header or (throw "c-ffi interface requires codegen.c_header in metadata.json");
      cHeaderInclude = builtins.baseNameOf cHeader;
      prefix = cg.c_prefix or null;
      prefixFlag = if prefix != null then "--prefix ${prefix}" else "";
    in
      ''
        echo "logos-module-builder: generating c-ffi Qt plugin (${config.name})..."
        logos-cpp-generator --from-c-header "${cHeader}" \
          --metadata metadata.json \
          --backend qt \
          --c-header-include ${cHeaderInclude} \
          --output-dir ./generated_code \
          ${prefixFlag}
      '';

  autoCodegen = config:
    if config.interface == "universal" then universalCodegen config
    else if config.interface == "provider" then providerCodegen config
    else if config.interface == "c-ffi" then cFfiCodegen config
    else "";

  # Order: optional ext copy -> optional darwin fixup -> (for c-ffi: user hook first, then codegen)
  #        (for others: codegen first, then user hook)
  # Note: mkLogosModule main builds already copy externals in logos-plugin-qt buildPlugin
  # (externalLibCopies). Use copyExternals=true only for contexts without that (e.g. unit tests).
  compose = { config, externalLibs, userPre, fixDarwin ? false, copyExternals ? false }:
    let
      copy    = if copyExternals then copyExternalLibsToLib externalLibs else "";
      codegen = autoCodegen config;
      fix     = if fixDarwin then fixupDarwinDylibs else "";
      # c-ffi modules build their external library in userPre (e.g. cargo build),
      # so the C header is only available after userPre runs. Run userPre first.
      codegenAndUser =
        if config.interface == "c-ffi" then userPre + codegen
        else codegen + userPre;
    in
      copy + fix + codegenAndUser;

in {
  inherit defaultImplClassFromName copyExternalLibsToLib fixupDarwinDylibs universalCodegen providerCodegen cFfiCodegen autoCodegen compose;
}
