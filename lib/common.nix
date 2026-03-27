# Common utilities shared across all builder functions
{ lib }:

let
  # Recursively collect all module dependencies (direct + transitive) from flake
  # inputs, using each module's exported config.dependencies to walk the tree.
  # Returns a flat attrset: { moduleName = lgxDerivation; ... }
  # Uses the LGX package output (packages.lgx) which bundles the plugin plus
  # any external libraries it depends on.  Falls back to packages.default.
  #
  # system:   target system string (e.g. "x86_64-linux")
  # inputs:   flake inputs attrset to search for dependency modules
  # depNames: list of dependency name strings to resolve
  collectAllModuleDeps = system: inputs: depNames:
    let
      depInputs = lib.filterAttrs (n: _: builtins.elem n depNames) inputs;

      direct = lib.mapAttrs (_: input:
        if input ? packages.${system}.lgx
        then input.packages.${system}.lgx
        else if input ? packages.${system}.default
        then input.packages.${system}.default
        else input
      ) depInputs;

      transitive = builtins.foldl' (acc: name:
        let
          input = depInputs.${name};
          tdeps = (input.config or {}).dependencies or [];
          tinputs = input.inputs or {};
        in
          if tdeps == [] then acc
          else acc // (collectAllModuleDeps system tinputs tdeps)
      ) {} (builtins.attrNames depInputs);
    in
      # direct overrides transitive so the closest (most specific) dep wins
      transitive // direct;

in {
  inherit collectAllModuleDeps;

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
  commonCmakeFlags = { logosSdk, logosModule }: [
    "-GNinja"
    "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
    "-DLOGOS_MODULE_ROOT=${logosModule}"
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
