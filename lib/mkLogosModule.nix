# Core module builder function
# This is the main entry point for building Logos modules
{ nixpkgs, logos-cpp-sdk, logos-module, lib, common, parseMetadata, builderRoot }:

{
  # Required: Path to the module source
  src,
  
  # Required: Path to the module.yaml configuration file
  configFile,

  # Optional: all flake inputs — dependencies in metadata.json are resolved automatically
  flakeInputs ? {},

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

  # Optional: wire up apps.default for `nix run` via logos-standalone-app.
  # Pass the logos-standalone-app flake input directly. Only valid when metadata.json type = ui.
  logosStandalone ? null,
}:

let
  # Parse the module configuration
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];
  
  # Import sub-builders
  mkModuleLib = import ./mkModuleLib.nix { inherit lib common; };
  mkModuleInclude = import ./mkModuleInclude.nix { inherit lib common; };
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;
  
  # Helper to get a package from nixpkgs by name
  # Includes strict evaluation to catch any lazy evaluation issues
  getPkg = pkgs: name:
    let evaluatedName = builtins.seq name name;
    in if builtins.isString evaluatedName
       then lib.getAttrFromPath (lib.splitString "." evaluatedName) pkgs
       else builtins.throw "getPkg expected string but got ${builtins.typeOf evaluatedName}";

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  # Package outputs
  packages = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;
      
      # Resolve module dependencies from inputs
      moduleInputs = lib.filterAttrs (n: _: builtins.elem n config.dependencies) flakeInputs;
      resolvedModuleDeps = lib.mapAttrs (_: input:
        if input ? packages.${system}.default then input.packages.${system}.default else input
      ) moduleInputs;
      
      # Resolve external library inputs
      resolvedExternalLibs = lib.mapAttrs (_: input:
        if input ? packages.${system}.default then input.packages.${system}.default else input
      ) externalLibInputs;

      buildPkgs   = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.runtime);

      commonArgs = {
        pname = "logos-${config.name}-module";
        version = config.version;
        nativeBuildInputs = common.commonNativeBuildInputs pkgs ++ [ logosSdk ] ++ extraNativeBuildInputs ++ buildPkgs;
        buildInputs       = common.commonBuildInputs pkgs ++ extraBuildInputs ++ runtimePkgs;
        cmakeFlags        = common.commonCmakeFlags { inherit logosSdk logosModule; };
        env = {
          LOGOS_CPP_SDK_ROOT = "${logosSdk}";
          LOGOS_MODULE_ROOT = "${logosModule}";
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
        
        # Copy include files (not symlinks) — use find to avoid nullglob issues
        if [ -d "${moduleInclude}/include" ] && [ -n "$(find ${moduleInclude}/include -maxdepth 1 -not -name '.*' -not -path ${moduleInclude}/include -print -quit)" ]; then
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
      logosModule = logos-module.packages.${system}.default;
      
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = common.commonNativeBuildInputs pkgs ++ buildPkgs;
        buildInputs = common.commonBuildInputs pkgs ++ runtimePkgs;
        
        shellHook = ''
          export LOGOS_CPP_SDK_ROOT="${logosSdk}"
          export LOGOS_MODULE_ROOT="${logosModule}"
          echo "Logos ${config.name} module development environment"
          echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
          echo "LOGOS_MODULE_ROOT: $LOGOS_MODULE_ROOT"
        '';
      };
    }
  );

  optionalApps =
    if logosStandalone == null then {}
    else if config.type != "ui" then builtins.throw "mkLogosModule: logosStandalone requires metadata.json type: ui"
    else {
      apps = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = mkStandaloneApp {
            inherit pkgs;
            standalone   = logosStandalone.packages.${system}.default;
            plugin       = packages.${system}.default;
            metadataFile = configFile;
            dirName      = "logos-${config.name}-plugin-dir";
            format       = "qt-plugin";
          };
        }
      );
    };

in {
  inherit packages devShells config;
  metadataJson = builtins.readFile configFile;
} // optionalApps
