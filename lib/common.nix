# Common utilities shared across all builder functions
{ lib }:

{
  # Supported target systems
  systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
  
  # Helper to run a function for all systems
  forAllSystems = nixpkgs: f: 
    lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ] 
      (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });
  
  # Determine library extension based on platform
  getLibExtension = pkgs:
    if pkgs.stdenv.hostPlatform.isDarwin then "dylib"
    else if pkgs.stdenv.hostPlatform.isWindows then "dll"
    else "so";
  
  # Get the library filename for a module
  getPluginFilename = pkgs: name:
    "${name}_plugin.${if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so"}";
  
  # Common native build inputs for all modules
  commonNativeBuildInputs = pkgs: [
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    pkgs.qt6.wrapQtAppsNoGuiHook
  ];
  
  # Common build inputs for all modules
  commonBuildInputs = pkgs: [
    pkgs.qt6.qtbase
    pkgs.qt6.qtremoteobjects
  ];
  
  # Common CMake flags for all modules
  commonCmakeFlags = { logosSdk, logosLiblogos }: [
    "-GNinja"
    "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
    "-DLOGOS_LIBLOGOS_ROOT=${logosLiblogos}"
  ];
  
  # Platform-specific post-build commands for library path fixing
  fixLibraryPaths = pkgs: libName: ''
    ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      # Fix install name on macOS
      if [ -f "$out/lib/${libName}.dylib" ]; then
        ${pkgs.darwin.cctools}/bin/install_name_tool -id "@rpath/${libName}.dylib" "$out/lib/${libName}.dylib"
      fi
    ''}
  '';
  
  # Generate metadata.json content from module config
  generateMetadataJson = config: builtins.toJSON {
    name = config.name;
    version = config.version or "1.0.0";
    description = config.description or "A Logos module";
    type = config.type or "core";
    category = config.category or "general";
    main = "${config.name}_plugin";
    dependencies = config.dependencies or [];
    include = config.include or [];
  };
  
  # Convert module name to various formats
  nameFormats = name: {
    # my_module -> my_module
    snake = name;
    # my_module -> MyModule
    pascal = lib.concatMapStrings (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) 
             (lib.splitString "_" name);
    # my_module -> myModule
    camel = let
      parts = lib.splitString "_" name;
      first = lib.head parts;
      rest = lib.tail parts;
    in first + lib.concatMapStrings (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) rest;
    # my_module -> MY_MODULE
    upper = lib.toUpper (lib.replaceStrings ["-"] ["_"] name);
  };
  
  # Merge two attribute sets recursively
  recursiveMerge = attrList:
    let
      f = attrPath:
        lib.zipAttrsWith (n: values:
          if lib.tail values == []
          then lib.head values
          else if lib.all lib.isList values
          then lib.unique (lib.concatLists values)
          else if lib.all lib.isAttrs values
          then f (attrPath ++ [n]) values
          else lib.last values
        );
    in f [] attrList;
}
