# ui_qml module builder — QML view + optional C++ backend (process-isolated).
# Calls buildCppPlugin only when config.main is set; the resulting `combined`
# output bundles the plugin .so (when present) with the QML view directory.
{ nixpkgs, lib, common, parseMetadata, logos-cpp-sdk, logos-protocol ? null, logos-qt-sdk ? null, logos-module, uiBackend, coreBackend, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app, nix-bundle-dir, nix-bundle-appimage, nix-bundle-macos-app }:

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

  # Optional: artwork for the redistributable app binaries. `png` (256x256) is
  # the desktop/AppImage icon, `icns` the macOS bundle icon. bin-appimage and
  # bin-macos-app are exposed only when the matching file is given.
  appIcons ? {},
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
    inherit nixpkgs lib common parseMetadata logos-cpp-sdk logos-protocol logos-qt-sdk logos-module uiBackend coreBackend nix-bundle-lgx nix-bundle-logos-module-install;
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
  appRuntimeLayout = import ./appRuntimeLayout.nix;
  mkAppBundle = import ./mkAppBundle.nix;

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
          install -D -m644 ${icon} $out/lib/${config.icon}
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

      # Auto-generate a qmldir at the entry directory declaring a unique
      # per-module URI. Qt reads this qmldir when the entry file's implicit
      # "." import loads, and uses its `module` line as the import's URI —
      # non-empty and per-module. Without this, Qt's process-global
      # composite-type name cache (keyed by (name, uri)) would let
      # same-basename types (e.g. two Card.qml files in two different
      # modules) cross-match across engines loaded in the same host process,
      # producing the "Invalid null URL" cascade
      #
      # Skipped if the author already shipped a qmldir at the entry dir.
      QMLDIR_TARGET="$out/lib/${viewDir}/qmldir"
      if [ ! -f "$QMLDIR_TARGET" ]; then
        mkdir -p "$(dirname "$QMLDIR_TARGET")"
        echo "module com.logos.module.${config.name}" > "$QMLDIR_TARGET"
        echo "Generated qmldir at ${viewDir}/qmldir (module com.logos.module.${config.name})"
      else
        echo "Author-provided qmldir at ${viewDir}/qmldir preserved"
      fi
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
      # Default: lib/ layout for both backend and QML-only modules.
      default = combined;
    } // lib.optionalAttrs hasBackend {
      "${config.name}-lib" = moduleLib;
      lib = moduleLib;

      # Ready-to-build codebase: all code generators run, emitted as a source
      # tree (nix build .#generate). Only for modules with a C++ backend —
      # QML-only modules have no generators to run.
      generate = built.perSystem.${system}.moduleGenerate;
      "${config.name}-generate" = built.perSystem.${system}.moduleGenerate;
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

  # Redistributable binaries. The host is the portable standalone build — an
  # unwrapped binary nix-bundle-dir can relocate, with the inspector compiled out.
  appBundlePackages = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      standalone = resolvedStandalone.packages.${system}.portable;
    in mkAppBundle {
      inherit pkgs lib system config standalone;
      inherit nix-bundle-dir nix-bundle-appimage nix-bundle-macos-app;
      icons = appIcons;
      layout = appRuntimeLayout {
        inherit pkgs standalone;
        plugin       = packages.${system}.default;
        metadataFile = configFile;
        dirName      = "logos-${config.name}-plugin-dir";
        format       = if hasBackend then "qt-plugin" else "qml";
        moduleDeps   = common.collectAllModuleDeps system flakeInputs config.dependencies;
      };
    }
  );

  # Auto-detect UI integration tests: scan tests/ for .mjs files and produce
  # an integration-test package using logos-standalone-app's mkPluginTest.
  testsDir = src + "/tests";
  hasTestsDir = builtins.pathExists testsDir;
  testFiles =
    if hasTestsDir then
      let
        entries = builtins.attrNames (builtins.readDir testsDir);
        mjsFiles = builtins.filter (name: lib.hasSuffix ".mjs" name) entries;
      in map (name: testsDir + "/${name}") mjsFiles
    else [];
  hasUiTests = testFiles != [];

  integrationTestPackages = lib.optionalAttrs hasUiTests (forAllSystems (system:
    let
      mkPluginTest = resolvedStandalone.lib.${system}.mkPluginTest;
      pkgs = pkgsFor system;
      allDeps = common.collectAllModuleDeps system flakeInputs config.dependencies;
    in {
      integration-test = mkPluginTest {
        inherit pkgs testFiles;
        pluginPkg = packages.${system}.default;
        moduleDeps = allDeps;
        name = "${config.name}-integration-test";
      };

      # Expose logos-qt-mcp so modules can build the test framework locally:
      #   nix build .#test-framework -o result-mcp
      test-framework = resolvedStandalone.packages.${system}.logos-qt-mcp;
    }
  ));

  # Merge view-module-specific LGX outputs, app bundles and integration tests
  # into packages
  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (lgxPackages.${system} or {}) // (appBundlePackages.${system} or {})
      // (integrationTestPackages.${system} or {})
  ) packages;

in {
  packages = mergedPackages;
  checks = lib.mapAttrs (_: sysPkgs: {
    integration-test = sysPkgs.integration-test;
  }) integrationTestPackages;
  devShells =
    if hasBackend
    then built.devShells
    else lib.genAttrs common.systems (system:
      { default = (pkgsFor system).mkShell {}; });
  inherit apps config;
  metadataJson = builtins.readFile configFile;
}
