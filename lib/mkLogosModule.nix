# Core module builder function
# This is the main entry point for building Logos modules
{ nixpkgs, logos-cpp-sdk, logos-liblogos, lib, common, parseModuleYaml }:

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
  getPkg = pkgs: name:
    let
      parts = lib.splitString "." name;
    in lib.getAttrFromPath parts pkgs;
  
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
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;
      
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
      
      # Combined package
      combined = pkgs.symlinkJoin {
        name = "logos-${config.name}-module";
        paths = [ moduleLib moduleInclude ];
      };
      
    in {
      # Individual outputs
      "${config.name}-lib" = moduleLib;
      "${config.name}-include" = moduleInclude;
      lib = moduleLib;
      include = moduleInclude;
      
      # Default package (combined)
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
