# Core module builder function
# This is the main entry point for building Logos modules.
# Plugin compilation and header generation are delegated to a backend selected
# by metadata.json "type": core modules use coreBackend, UI modules use uiBackend.
{ nixpkgs, lib, common, parseMetadata, builderRoot, uiBackend, coreBackend, logos-cpp-sdk, logos-module, logos-test-framework, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app }:

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

  # Optional: Unit test configuration. When provided, a checks.<system>.unit-tests
  # output is automatically generated using logos-test-framework.
  #   tests = {
  #     dir = ./tests;        # Required: directory containing test sources + CMakeLists.txt
  #     mockCLibs = [];       # Optional: C libraries to mock at link time
  #     preConfigure = "";    # Optional: custom preConfigure hook
  #     extraBuildInputs = [];
  #     extraCmakeFlags = [];
  #   };
  tests ? null,
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
  modulePreConfigure = import ./modulePreConfigure.nix { inherit lib; };

  # When this flake ships cmake/LogosModule.cmake, override LOGOS_MODULE_BUILDER_ROOT
  # so the extended macros (generated_code glob, metadata copy, Go static libs) are used.
  # Otherwise let the backend's default take over — it already sets
  # LOGOS_MODULE_BUILDER_ROOT to its own root which has cmake/LogosModule.cmake.
  hasBuilderCmake = builtins.pathExists (builderRoot + "/cmake/LogosModule.cmake");

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

      # Resolve a single externalLibInputs entry for a given variant.
      # Supports both simple (bare flake input) and structured ({ input, packages }) formats.
      resolveExtInput = variant: name: value:
        if builtins.isAttrs value && value ? input then
          let
            flakeInput = value.input;
            packages = value.packages or {};
            pkgName = packages.${variant} or packages.default or "default";
          in
            if flakeInput ? packages.${system}.${pkgName}
            then flakeInput.packages.${system}.${pkgName}
            else builtins.throw ''
              External lib "${name}": flake input does not provide packages.${system}.${pkgName}.
              Check the "externalLibInputs" structured entry and ensure the flake input exposes the expected package.
            ''
        else
          if value ? packages.${system}.default then value.packages.${system}.default else value;

      # Whether any external lib input declares per-variant packages
      hasVariants = lib.any (v: builtins.isAttrs v && v ? input && v ? packages)
        (lib.attrValues externalLibInputs);

      buildPkgs   = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.runtime);

      # Pre-resolve default variant external libs (always needed, avoids
      # duplicate evaluation when hasVariants triggers a second buildVariant).
      defaultResolvedExternalLibs = lib.mapAttrs (resolveExtInput "default") externalLibInputs;
      defaultExternalLibs = mkExternalLib.buildExternalLibs {
        inherit pkgs config;
        externalInputs = defaultResolvedExternalLibs;
      };

      # Resolve SDK deps for this system — injected into the backend
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;

      # Build the plugin for a given external-lib variant ("default" or "portable")
      buildVariant = variant:
        let
          externalLibs =
            if variant == "default" then defaultExternalLibs
            else mkExternalLib.buildExternalLibs {
              inherit pkgs config;
              externalInputs = lib.mapAttrs (resolveExtInput variant) externalLibInputs;
            };

          userPreConfigure =
            if builtins.isFunction preConfigure
            then preConfigure { inherit externalLibs; }
            else preConfigure;

          preConfigureStr = modulePreConfigure.compose {
            inherit config externalLibs;
            userPre = userPreConfigure;
            fixDarwin = false;
            # logos-plugin-qt buildPlugin already stages external libs into lib/
            copyExternals = false;
          };

          goCmakeFlags = lib.optionals (config.go_static_lib_names != []) [
            "-DLOGOS_MODULE_GO_STATIC_LIBS=${lib.concatStringsSep ";" config.go_static_lib_names}"
          ];
        # Delegate plugin compilation to the backend.
        # The backend only knows about Qt + logosModule (interface.h).
        # SDK (generator, lib, headers) is injected via extra* args.
        in selectedBackend.buildPlugin {
          inherit pkgs src config postInstall logosModule;
          preConfigure = preConfigureStr;
          moduleDeps = resolvedModuleDeps;
          inherit externalLibs;
          extraNativeBuildInputs = extraNativeBuildInputs ++ buildPkgs ++ [ logosSdk ];
          extraBuildInputs = extraBuildInputs ++ runtimePkgs;
          extraCmakeFlags = [ "-DLOGOS_CPP_SDK_ROOT=${logosSdk}" ] ++ goCmakeFlags;
          extraEnv = {
            LOGOS_CPP_SDK_ROOT = "${logosSdk}";
          } // lib.optionalAttrs hasBuilderCmake {
            LOGOS_MODULE_BUILDER_ROOT = "${toString builderRoot}";
          };
        };

      moduleLib = buildVariant "default";
      moduleLibPortable = if hasVariants then buildVariant "portable" else null;

      # Delegate header generation to the backend
      moduleInclude = selectedBackend.buildHeaders {
        inherit pkgs src config logosSdk;
        pluginLib = moduleLib;
      };

      # Combined package - copy files instead of symlinks.
      # The `//` merge exposes src + version on the derivation so downstream
      # bundlers (nix-bundle-lgx) can locate metadata.json.
      combined = (pkgs.runCommand "logos-${config.name}-module" {} ''
        mkdir -p $out/lib $out/include

        # Copy library files (not symlinks)
        if [ -d "${moduleLib}/lib" ]; then
          cp -rL ${moduleLib}/lib/* $out/lib/
        fi

        # Copy include files (not symlinks) — use find to avoid nullglob issues
        if [ -d "${moduleInclude}/include" ] && [ -n "$(find ${moduleInclude}/include -maxdepth 1 -not -name '.*' -not -path ${moduleInclude}/include -print -quit)" ]; then
          cp -rL ${moduleInclude}/include/* $out/include/
        fi
      '') // { inherit src; version = config.version; };

    in {
      # Individual outputs (e.g., nix build .#chat-lib)
      "${config.name}-lib" = moduleLib;
      "${config.name}-include" = moduleInclude;

      # Short aliases (e.g., nix build .#lib)
      lib = moduleLib;
      include = moduleInclude;

      # Default package - combined lib + include (nix build)
      default = combined;
    } // lib.optionalAttrs (moduleLibPortable != null) {
      "${config.name}-lib-portable" = moduleLibPortable;
      lib-portable = moduleLibPortable;
    }
  );

  # Development shell (delegates to backend for deps)
  devShells = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;
      backendShell = selectedBackend.devShellInputs pkgs { inherit logosModule; };
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = backendShell.nativeBuildInputs ++ buildPkgs ++ [ logosSdk ];
        buildInputs = backendShell.buildInputs ++ runtimePkgs;
        shellHook = ''
          ${backendShell.shellHook}
          export LOGOS_CPP_SDK_ROOT="${logosSdk}"
          ${lib.optionalString hasBuilderCmake ''export LOGOS_MODULE_BUILDER_ROOT="${toString builderRoot}"''}
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
          installDev = nix-bundle-logos-module-install.bundlers.${system}.dev;
          installPortable = nix-bundle-logos-module-install.bundlers.${system}.portable;
          moduleLib = packages.${system}.lib;
          # Use the portable-linked plugin for lgx-portable when available
          moduleLibForPortable =
            packages.${system}.lib-portable or moduleLib;
        in {
          lgx = bundleLgx moduleLib;
          install = installDev moduleLib;
          lgx-portable = bundleLgxPortable moduleLibForPortable;
          install-portable = installPortable moduleLibForPortable;
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

  # Build unit tests — explicit config wins, otherwise auto-detect tests/CMakeLists.txt
  mkTests = import ./mkLogosModuleTests.nix {
    inherit nixpkgs lib common parseMetadata;
    inherit logos-cpp-sdk;
    logos-test-framework = logos-test-framework;
  };

  resolvedTests =
    if tests != null then tests
    else if builtins.pathExists (src + "/tests/CMakeLists.txt") then {
      dir = src + "/tests";
    }
    else null;

  testChecks =
    if resolvedTests == null then {}
    else mkTests {
      inherit src flakeInputs externalLibInputs;
      configFile = configFile;
      testDir = resolvedTests.dir;
      mockCLibs = resolvedTests.mockCLibs or [];
      preConfigure = resolvedTests.preConfigure or preConfigure;
      extraBuildInputs = resolvedTests.extraBuildInputs or [];
      extraCmakeFlags = resolvedTests.extraCmakeFlags or [];
    };

  optionalTests =
    if testChecks == {} then {}
    else { checks = testChecks; };

  # Also expose unit-tests as a package so `nix build .#unit-tests` works
  testPackages =
    if testChecks == {} then {}
    else lib.mapAttrs (_system: sysChecks:
      { unit-tests = sysChecks.unit-tests; }
    ) testChecks;

  finalPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (testPackages.${system} or {})
  ) mergedPackages;

in {
  packages = finalPackages;
  inherit devShells config;
  metadataJson = builtins.readFile configFile;
} // optionalApps // optionalTests
