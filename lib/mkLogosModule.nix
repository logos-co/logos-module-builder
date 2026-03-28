# Core module builder function
# This is the main entry point for building Logos modules.
# Plugin compilation and header generation are delegated to a backend selected
# by metadata.json "type": core modules use coreBackend, UI modules use uiBackend.
{ nixpkgs, lib, common, parseMetadata, builderRoot, uiBackend, coreBackend, nix-bundle-lgx, logos-standalone-app }:

{
  # Required: Path to the module source
  src,

  # Required: Path to the metadata.json configuration file
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

  # Optional: override the logos-standalone-app used for `nix run`.
  # By default, UI modules (type = "ui") automatically get apps.default wired up
  # using the standalone app bundled with logos-module-builder.
  logosStandalone ? null,
}:

let
  # Parse the module configuration
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];

  # Select backend based on module type: core modules are swappable, UI stays Qt
  selectedBackend =
    if config.type == "core" then coreBackend
    else uiBackend;

  # Import sub-builders (backend-agnostic)
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;

  # Helper to get a package from nixpkgs by name
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

      # Build external libraries if any (backend-agnostic)
      externalLibs = mkExternalLib.buildExternalLibs {
        inherit pkgs config;
        externalInputs = resolvedExternalLibs;
      };

      # Delegate plugin compilation to the backend
      moduleLib = selectedBackend.buildPlugin {
        inherit pkgs src config preConfigure postInstall;
        moduleDeps = resolvedModuleDeps;
        inherit externalLibs;
        extraNativeBuildInputs = extraNativeBuildInputs ++ buildPkgs;
        extraBuildInputs = extraBuildInputs ++ runtimePkgs;
      };

      # Delegate header generation to the backend
      moduleInclude = selectedBackend.buildHeaders {
        inherit pkgs src config;
        pluginLib = moduleLib;
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

  # Development shell (delegates to backend for deps)
  devShells = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      backendShell = selectedBackend.devShellInputs pkgs;
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = backendShell.nativeBuildInputs ++ buildPkgs;
        buildInputs = backendShell.buildInputs ++ runtimePkgs;
        shellHook = ''
          ${backendShell.shellHook}
          echo "Logos ${config.name} module development environment"
          echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
          echo "LOGOS_MODULE_ROOT: $LOGOS_MODULE_ROOT"
          echo "LOGOS_MODULE_BUILDER_ROOT: $LOGOS_MODULE_BUILDER_ROOT"
        '';
      };
    }
  );

  # LGX package outputs (nix-bundle-lgx provided by the builder)
  nixBundleLgx = nix-bundle-lgx;

  optionalLgx =
    {
      packages = forAllSystems (system:
        let
          bundleLgx = nixBundleLgx.bundlers.${system}.default;
          bundleLgxPortable = nixBundleLgx.bundlers.${system}.portable;
          moduleLib = packages.${system}.lib;
        in {
          lgx = bundleLgx moduleLib;
          lgx-portable = bundleLgxPortable moduleLib;
        }
      );
    };

  # Resolve the standalone app: explicit override > built-in from module-builder
  resolvedStandalone =
    if logosStandalone != null then logosStandalone
    else if config.type == "ui" then logos-standalone-app
    else null;

  optionalApps =
    if resolvedStandalone == null then {}
    else {
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # Collect all module dependencies (direct + transitive) for bundling
          allDeps = common.collectAllModuleDeps system flakeInputs config.dependencies;
        in {
          default = mkStandaloneApp {
            inherit pkgs;
            standalone   = resolvedStandalone.packages.${system}.default;
            plugin       = packages.${system}.default;
            metadataFile = configFile;
            dirName      = "logos-${config.name}-plugin-dir";
            format       = "qt-plugin";
            moduleDeps   = allDeps;
          };
        }
      );
    };

  # Merge LGX outputs into packages
  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (optionalLgx.packages.${system} or {})
  ) packages;

in {
  packages = mergedPackages;
  inherit devShells config;
  metadataJson = builtins.readFile configFile;
} // optionalApps
