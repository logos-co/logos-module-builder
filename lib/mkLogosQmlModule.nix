# ui_qml module builder — QML view + optional C++ backend (process-isolated).
# Calls buildCppPlugin only when config.main is set; the resulting `combined`
# output bundles the plugin .so (when present) with the QML view directory.
{ nixpkgs, lib, common, parseMetadata, logos-cpp-sdk, logos-module, uiBackend, coreBackend, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app }:

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
  logosStandalone ? null,
}:

let
  # Parse metadata first so we can decide whether to build a C++ backend at all.
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];

  # Validate: view modules must be type "ui_qml" with a "view" field.
  # The "main" backend library is OPTIONAL — if absent, the module is QML-only and
  # is loaded directly in-process by basecamp/standalone (no ui-host process).
  _ = assert config.type == "ui_qml" || builtins.throw
    "mkLogosQmlModule: metadata.json type must be \"ui_qml\", got \"${config.type}\"";
  assert config.view != null || builtins.throw
    "mkLogosQmlModule: metadata.json must specify a \"view\" field (e.g. \"qml/Main.qml\")";
  null;

  # Whether this module has a backend C++ plugin. QML-only modules omit "main".
  hasBackend = config.main != null;

  # Delegate compilation to the shared build pipeline (only when there's a backend).
  buildCppPlugin = import ./buildCppPlugin.nix {
    inherit nixpkgs lib common parseMetadata logos-cpp-sdk logos-module uiBackend coreBackend nix-bundle-lgx nix-bundle-logos-module-install;
  };

  built =
    if hasBackend
    then buildCppPlugin {
      inherit src configFile flakeInputs externalLibInputs extraBuildInputs
              extraNativeBuildInputs configOverrides preConfigure postInstall;
    }
    else null;

  # The QML view directory is derived from the "view" field (e.g. "qml/Main.qml" -> "qml")
  viewDir = builtins.dirOf config.view;

  mkStandaloneApp = import ./mkStandaloneApp.nix;

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  # pkgs accessor that works whether or not buildCppPlugin ran
  pkgsFor = system:
    if hasBackend
    then built.perSystem.${system}.pkgs
    else import nixpkgs { inherit system; };

  # Helper: create a combined derivation from a plugin lib + QML view from source.
  # Used for both default and portable variants. For QML-only modules, pluginLib is null.
  iconFiles = lib.optional (config.icon != null) (src + "/${config.icon}");

  mkCombined = system: pluginLib: suffix:
    let pkgs = pkgsFor system;
        iconInstall = pkgs.lib.concatStringsSep "\n" (map (icon: ''
          mkdir -p $out/lib/icons
          cp ${icon} $out/lib/icons/${builtins.baseNameOf (toString icon)}
        '') iconFiles);
    in (pkgs.runCommand "logos-${config.name}-module${suffix}" {} ''
      mkdir -p $out/lib

      ${lib.optionalString (pluginLib != null) ''
        # Copy library files (not symlinks)
        if [ -d "${pluginLib}/lib" ]; then
          cp -rL ${pluginLib}/lib/* $out/lib/
        fi
      ''}

      # Include metadata.json and icons in the output
      cp ${configFile} $out/lib/metadata.json
      ${iconInstall}

      # Copy QML view files from source.
      # C++ modules keep QML under src/ (e.g. src/qml/Main.qml);
      # QML-only modules may keep them at the project root (e.g. Main.qml or qml/Main.qml).
      # When viewDir is "." we only copy the single QML file to avoid pulling in
      # the entire project root (which would conflict with metadata.json above).
      if [ -d "${src}/src/${viewDir}" ] && [ "${viewDir}" != "." ]; then
        mkdir -p "$out/lib/${viewDir}"
        cp -r "${src}/src/${viewDir}/." "$out/lib/${viewDir}/"
        echo "Copied QML view directory from src/${viewDir}"
      elif [ -d "${src}/${viewDir}" ] && [ "${viewDir}" != "." ]; then
        mkdir -p "$out/lib/${viewDir}"
        cp -r "${src}/${viewDir}/." "$out/lib/${viewDir}/"
        echo "Copied QML view directory from ${viewDir}"
      elif [ -f "${src}/src/${config.view}" ]; then
        cp "${src}/src/${config.view}" "$out/lib/${config.view}"
        echo "Copied QML entry file from src/${config.view}"
      elif [ -f "${src}/${config.view}" ]; then
        cp "${src}/${config.view}" "$out/lib/${config.view}"
        echo "Copied QML entry file: ${config.view}"
      else
        echo "Warning: QML view '${config.view}' not found in source"
      fi
    '') // { inherit src; version = config.version; };

  # For QML-only modules, the user-facing default is a flat directory
  # (Main.qml + metadata.json at root) matching the old mkLogosQmlModule.
  # The lib/-layout combined output is used internally for LGX bundling.
  mkFlatQmlDir = system:
    let pkgs = pkgsFor system;
        iconInstall = pkgs.lib.concatStringsSep "\n" (map (icon: ''
          mkdir -p $out/icons
          cp ${icon} $out/icons/${builtins.baseNameOf (toString icon)}
        '') iconFiles);
    in (pkgs.runCommand "logos-${config.name}-plugin-dir" {} ''
      mkdir -p $out
      if [ -d "${src}/src/${viewDir}" ] && [ "${viewDir}" != "." ]; then
        cp -r "${src}/src/${viewDir}" "$out/${viewDir}"
      elif [ -d "${src}/${viewDir}" ] && [ "${viewDir}" != "." ]; then
        cp -r "${src}/${viewDir}" "$out/${viewDir}"
      elif [ -f "${src}/src/${config.view}" ]; then
        cp "${src}/src/${config.view}" "$out/${config.view}"
      elif [ -f "${src}/${config.view}" ]; then
        cp "${src}/${config.view}" "$out/${config.view}"
      fi
      cp ${configFile} $out/metadata.json
      ${iconInstall}
    '') // { inherit src; version = config.version; };

  # Package outputs
  packages = forAllSystems (system:
    let
      moduleLib =
        if hasBackend then built.perSystem.${system}.moduleLib else null;
      moduleLibPortable =
        if hasBackend then built.perSystem.${system}.moduleLibPortable else null;

      combined = mkCombined system moduleLib "";
      combinedPortable =
        if moduleLibPortable != null
        then mkCombined system moduleLibPortable "-portable"
        else null;

    in {
      # Default: flat for QML-only (result/Main.qml), lib/ layout for backend
      default = if hasBackend then combined else mkFlatQmlDir system;
    } // lib.optionalAttrs hasBackend {
      "${config.name}-lib" = moduleLib;
      lib = moduleLib;
    } // lib.optionalAttrs (moduleLibPortable != null) {
      "${config.name}-lib-portable" = moduleLibPortable;
      lib-portable = moduleLibPortable;
    }
  );

  # LGX packages — bundle the combined output (plugin + QML), not just moduleLib.
  # This ensures the QML view directory is included in the .lgx package so that
  # lgpm install and mkStandaloneApp LGX extraction both have the QML files.
  lgxPackages = forAllSystems (system:
    let
      bundleLgx = nix-bundle-lgx.bundlers.${system}.default;
      bundleLgxPortable = nix-bundle-lgx.bundlers.${system}.portable;
      installDev = nix-bundle-logos-module-install.bundlers.${system}.dev;
      installPortable = nix-bundle-logos-module-install.bundlers.${system}.portable;

      moduleLib =
        if hasBackend then built.perSystem.${system}.moduleLib else null;
      moduleLibPortable =
        if hasBackend then built.perSystem.${system}.moduleLibPortable else null;

      combined = mkCombined system moduleLib "";
      # Use the portable-linked plugin + QML for portable bundles when available
      combinedForPortable =
        if moduleLibPortable != null
        then mkCombined system moduleLibPortable "-portable"
        else combined;
    in {
      lgx = bundleLgx combined;
      install = installDev combined;
      lgx-portable = bundleLgxPortable combinedForPortable;
      install-portable = installPortable combinedForPortable;
    }
  );

  # Resolve the standalone app: explicit override > built-in from module-builder
  resolvedStandalone =
    if logosStandalone != null then logosStandalone
    else logos-standalone-app;

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
        format       = if hasBackend then "qt-plugin" else "qml";
        moduleDeps   = allDeps;
      };
    }
  );

  # Merge view-module-specific LGX outputs into packages
  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (lgxPackages.${system} or {})
  ) packages;

in {
  packages = mergedPackages;
  devShells =
    if hasBackend
    then built.devShells
    else lib.genAttrs common.systems (system:
      { default = (pkgsFor system).mkShell {}; });
  inherit apps config;
  metadataJson = builtins.readFile configFile;
}
