# Core module builder function
# This is the main entry point for building Logos modules
{ nixpkgs, logos-cpp-sdk, logos-liblogos, lib, common, parseModuleYaml, builderRoot }:

{
  # Required: Path to the module source
  src,
  
  # Required: Path to the module.yaml configuration file
  configFile,
  
  # Optional: Additional flake inputs for module dependencies
  moduleInputs ? {},
  
  # Optional: Additional flake inputs for external libraries
  externalLibInputs ? {},
  
  # Optional: Extra build inputs to add
  extraBuildInputs ? [],
  
  # Optional: Extra native build inputs to add
  extraNativeBuildInputs ? [],
  
  # Optional: Override any config values
  configOverrides ? {},
  
  # Optional: Custom preConfigure hook
  preConfigure ? "",
  
  # Optional: Custom postInstall hook
  postInstall ? "",
}:

let
  # Parse the module configuration
  rawConfig = parseModuleYaml.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];
  
  # Import sub-builders
  mkModuleLib = import ./mkModuleLib.nix { inherit lib common; };
  mkModuleInclude = import ./mkModuleInclude.nix { inherit lib common; };
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  
  # Helper to get a package from nixpkgs by name
  # Includes strict evaluation to catch any lazy evaluation issues
  getPkg = pkgs: name:
    let
      # Force evaluation of name to catch any issues early
      evaluatedName = builtins.seq name name;
    in
      if builtins.isString evaluatedName then
        let
          parts = lib.splitString "." evaluatedName;
        in lib.getAttrFromPath parts pkgs
      else
        builtins.throw "getPkg expected string but got ${builtins.typeOf evaluatedName}. This usually indicates a YAML parsing issue.";
  
  # Build for all systems
  forAllSystems = f: lib.genAttrs common.systems (system: f system);
  
in {
  # Package outputs
  packages = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosLiblogos = logos-liblogos.packages.${system}.default;
      
      # Resolve module dependencies from inputs
      resolvedModuleDeps = lib.mapAttrs (name: input:
        if input ? packages.${system}.default
        then input.packages.${system}.default
        else input
      ) moduleInputs;
      
      # Resolve external library inputs
      resolvedExternalLibs = lib.mapAttrs (name: input:
        if input ? packages.${system}.default
        then input.packages.${system}.default
        else input
      ) externalLibInputs;
      
      # Get nix packages for build and runtime
      # Validate lists before processing to catch parsing issues early
      buildPkgNames = 
        let pkgList = config.nix_packages.build;
        in if builtins.isList pkgList 
           then lib.filter builtins.isString pkgList
           else [];
      runtimePkgNames = 
        let pkgList = config.nix_packages.runtime;
        in if builtins.isList pkgList 
           then lib.filter builtins.isString pkgList
           else [];
      buildPkgs = map (getPkg pkgs) buildPkgNames;
      runtimePkgs = map (getPkg pkgs) runtimePkgNames;
      
      # Common derivation arguments
      commonArgs = {
        pname = "logos-${config.name}-module";
        version = config.version;
        
        nativeBuildInputs = common.commonNativeBuildInputs pkgs 
          ++ [ logosSdk ]
          ++ extraNativeBuildInputs
          ++ buildPkgs;
        
        buildInputs = common.commonBuildInputs pkgs 
          ++ extraBuildInputs
          ++ runtimePkgs;
        
        cmakeFlags = common.commonCmakeFlags { inherit logosSdk logosLiblogos; };
        
        env = {
          LOGOS_CPP_SDK_ROOT = "${logosSdk}";
          LOGOS_LIBLOGOS_ROOT = "${logosLiblogos}";
          LOGOS_MODULE_BUILDER_ROOT = "${builderRoot}";
        };
        
        meta = with lib; {
          description = config.description;
          platforms = platforms.unix;
        };
      };
      
      # Build external libraries if any
      externalLibs = mkExternalLib.buildExternalLibs {
        inherit pkgs config;
        externalInputs = resolvedExternalLibs;
      };
      
      # Build the library package
      moduleLib = mkModuleLib.build {
        inherit pkgs src config commonArgs logosSdk preConfigure postInstall;
        moduleDeps = resolvedModuleDeps;
        inherit externalLibs;
      };
      
      # Build the include package (generated headers)
      moduleInclude = mkModuleInclude.build {
        inherit pkgs src config commonArgs logosSdk;
        lib = moduleLib;
      };
      
      # Combined package - copy files instead of symlinks
      combined = pkgs.runCommand "logos-${config.name}-module" {} ''
        mkdir -p $out/lib $out/include
        
        # Copy library files (not symlinks)
        if [ -d "${moduleLib}/lib" ]; then
          cp -rL ${moduleLib}/lib/* $out/lib/
        fi
        
        # Copy include files (not symlinks)
        if [ -d "${moduleInclude}/include" ]; then
          cp -rL ${moduleInclude}/include/* $out/include/
        fi
      '';
      
    in {
      # Individual outputs (e.g., nix build .#chat-lib)
      "${config.name}-lib" = moduleLib;
      "${config.name}-include" = moduleInclude;
      
      # Short aliases (e.g., nix build .#lib)
      lib = moduleLib;
      include = moduleInclude;
      
      # Default package - combined lib + include (nix build)
      default = combined;
    }
  );
  
  # Development shell
  devShells = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosLiblogos = logos-liblogos.packages.${system}.default;
      
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = common.commonNativeBuildInputs pkgs ++ buildPkgs;
        buildInputs = common.commonBuildInputs pkgs ++ runtimePkgs;
        
        shellHook = ''
          export LOGOS_CPP_SDK_ROOT="${logosSdk}"
          export LOGOS_LIBLOGOS_ROOT="${logosLiblogos}"
          echo "Logos ${config.name} module development environment"
          echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
          echo "LOGOS_LIBLOGOS_ROOT: $LOGOS_LIBLOGOS_ROOT"
        '';
      };
    }
  );
  
  # Export the parsed config for introspection
  inherit config;
  
  # Export metadata.json content
  metadataJson = common.generateMetadataJson config;
}
