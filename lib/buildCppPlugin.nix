# Shared C++ plugin build pipeline — encapsulates config parsing, dependency
# resolution, plugin compilation (via backend), header generation, dev shells,
# and LGX bundling.  Callers (mkLogosModule, mkLogosQmlModule) compose final
# `packages` and `apps` outputs differently.
{ nixpkgs, lib, common, parseMetadata, logos-cpp-sdk, logos-module, uiBackend, coreBackend, nix-bundle-lgx, nix-bundle-logos-module-install }:

{
  src,
  configFile,
  flakeInputs ? {},
  externalLibInputs ? {},
  extraBuildInputs ? [],
  extraNativeBuildInputs ? [],
  configOverrides ? {},
  preConfigure ? "",
  postInstall ? "",
}:

let
  # Parse the module configuration
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];

  # Select backend based on module type: core modules are swappable, UI stays Qt
  selectedBackend =
    if config.type == "core" then coreBackend
    else uiBackend;

  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };

  getPkg = pkgs: name:
    let evaluatedName = builtins.seq name name;
    in if builtins.isString evaluatedName
       then lib.getAttrFromPath (lib.splitString "." evaluatedName) pkgs
       else builtins.throw "getPkg expected string but got ${builtins.typeOf evaluatedName}";

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  # Per-system build outputs
  perSystem = forAllSystems (system:
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

      # Resolve SDK deps for this system — injected into the backend
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;

      modulePreConfigure = import ./modulePreConfigure.nix { inherit lib; };

      buildPkgs   = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.runtime);

      # Pre-resolve default variant external libs (always needed, avoids
      # duplicate evaluation when hasVariants triggers a second buildVariant).
      defaultResolvedExternalLibs = lib.mapAttrs (resolveExtInput "default") externalLibInputs;
      defaultExternalLibs = mkExternalLib.buildExternalLibs {
        inherit pkgs config;
        externalInputs = defaultResolvedExternalLibs;
      };

      hasBuilderCmake = builtins.pathExists (src + "/cmake/LogosModule.cmake");

      goCmakeFlags = lib.optionals (config.go_static_lib_names or [] != []) [
        "-DLOGOS_MODULE_GO_STATIC_LIBS=${lib.concatStringsSep ";" config.go_static_lib_names}"
      ];

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
            copyExternals = false;
          };
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
            LOGOS_MODULE_BUILDER_ROOT = "${src}";
          };
        };

      moduleLib = buildVariant "default";
      moduleLibPortable = if hasVariants then buildVariant "portable" else null;

      # Delegate header generation to the backend
      moduleInclude = selectedBackend.buildHeaders {
        inherit pkgs src config logosSdk;
        pluginLib = moduleLib;
      };

    in {
      inherit pkgs moduleLib moduleLibPortable moduleInclude hasVariants;
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
  lgxPackages = forAllSystems (system:
    let
      bundleLgx = nix-bundle-lgx.bundlers.${system}.default;
      bundleLgxPortable = nix-bundle-lgx.bundlers.${system}.portable;
      installDev = nix-bundle-logos-module-install.bundlers.${system}.dev;
      installPortable = nix-bundle-logos-module-install.bundlers.${system}.portable;
      moduleLib = perSystem.${system}.moduleLib;
      # Use the portable-linked plugin for lgx-portable when available
      moduleLibForPortable =
        if perSystem.${system}.moduleLibPortable != null
        then perSystem.${system}.moduleLibPortable
        else moduleLib;
    in {
      lgx = bundleLgx moduleLib;
      install = installDev moduleLib;
      lgx-portable = bundleLgxPortable moduleLibForPortable;
      install-portable = installPortable moduleLibForPortable;
    }
  );

in {
  inherit config perSystem devShells lgxPackages;
}
