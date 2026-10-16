# ui_qml module builder — QML view + optional C++ backend (process-isolated).
# Calls buildCppPlugin only when config.main is set; the resulting `combined`
# output bundles the plugin .so (when present) with the QML view directory.
{ nixpkgs, lib, common, parseMetadata, logos-cpp-sdk, logos-protocol ? null, logos-qt-sdk ? null, logos-plugin-qt ? null, logos-view-module, logos-module, uiBackend, coreBackend, builderRoot, nix-bundle-lgx, nix-bundle-logos-module-install }:

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

  # Deprecated, ignored: `nix run` runs Basecamp now (mkBasecampApp.nix).
  # Still accepted so a flake that passes it keeps evaluating.
  logosStandalone ? null,
}:

let
  # QML views are copied from the module source minus docs, CI and lock files.
  moduleSrc = common.filterModuleSrc src;
  metadataJson = builtins.readFile configFile;

  # Parse metadata first so we can decide whether to build a C++ backend at all.
  #
  # NO platform here, and this file is the one that most needs saying why. Three
  # of the reads below — `config.type`, `config.view`, `config.main` — happen
  # above forAllSystems and decide the flake's output SHAPE, not just its
  # contents: `hasBackend` gates whether `packages.<sys>` even has a `-lib`
  # attribute. A per-system answer for `main` would make the ATTRIBUTE NAMES
  # differ between systems, which is not something a flake can express.
  #
  # A module cannot platform-key `main` at all — resolvePlatforms refuses it in
  # `topDeferred`, on every target and with no target, so the throw arrives at
  # the overlay rather than here. That refusal replaced an earlier arrangement
  # in which `main` WAS overlay-able and this read was supposed to be the thing
  # that caught it, via resolvePlatforms.poisonField. It was not: mkLogosModule's
  # only read of `config.main` is modulePreConfigure.nix:200's legacy-interface
  # guard, which only ever throws — so a CORE module keying it sailed through
  # with no diagnostic anywhere and shipped a manifest naming a plugin that does
  # exist on the non-base targets. A guard that fires for one module type and
  # silently does not for the other is not a guard.
  #
  # The reasoning for parsing with no platform here is unaffected: `type` and
  # `view` still decide output shape, and the plugin's file EXTENSION is already
  # handled centrally by common.getPluginFilename, so there is no case a
  # per-platform `main` serves that is not better served there.
  rawConfig = parseMetadata.parseModuleConfig { json = metadataJson; platform = null; };
  config = common.recursiveMerge [ rawConfig configOverrides ];

  # The resolved config per target, rebound as `config` inside every per-system
  # closure below.
  configFor = system: common.recursiveMerge [
    (parseMetadata.parseModuleConfig {
      json = metadataJson;
      platform = parseMetadata.platformForSystem system;
    })
    configOverrides
  ];

  # ── The document the ARTIFACT carries ─────────────────────────────────────
  #
  # `configFile` is the SOURCE, overlays unapplied. Ship it and a platform-keyed
  # field is resolved for the BUILD and not for the artifact: the loader, lgpm
  # and the .lgx manifest all read the base answer. That gap is why
  # `dependencies` was a refused overlay key.
  #
  # Written from `_raw` — the RESOLVED tree, which keeps the object entry form
  # that carries an installer's version/signer constraints. The normalised
  # `config` would flatten those to names.
  #
  # Null for a module with no `platforms` anywhere: there is nothing to resolve,
  # and the source file goes on reaching the artifact byte-identically.
  hasPlatformOverlays =
    let j = builtins.fromJSON metadataJson;
    in (j ? platforms) || (builtins.isAttrs (j.nix or null) && (j.nix ? platforms));
  resolvedMetadataFileFor = pkgs: system:
    if !hasPlatformOverlays then null
    else pkgs.writeText "metadata.json" (builtins.toJSON (configFor system)._raw);

  # The same answer as a path that always exists — the source file is the
  # resolved document for a module with nothing to resolve.
  shippedMetadataFor = pkgs: system:
    let f = resolvedMetadataFileFor pkgs system;
    in if f == null then configFile else f;

  # Validate: view modules must be type "ui_qml" with a "view" field.
  # The "main" backend library is OPTIONAL — if absent, the module is QML-only and
  # is loaded directly in-process by basecamp (no ui-host process).
  _ = assert config.type == "ui_qml" || builtins.throw
    "mkLogosQmlModule: metadata.json type must be \"ui_qml\", got \"${config.type}\"";
  assert config.view != null || builtins.throw
    "mkLogosQmlModule: metadata.json must specify a \"view\" field (e.g. \"qml/Main.qml\")";
  null;

  # Whether this module has a backend C++ plugin. QML-only modules omit "main".
  hasBackend = config.main != null;

  # Delegate compilation to the shared build pipeline (only when there's a backend).
  buildCppPlugin = import ./buildCppPlugin.nix {
    inherit nixpkgs lib common parseMetadata logos-cpp-sdk logos-protocol logos-qt-sdk logos-plugin-qt logos-view-module logos-module uiBackend coreBackend builderRoot nix-bundle-lgx nix-bundle-logos-module-install;
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


  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  mkBasecampApp = import ./mkBasecampApp.nix;
  basecampAppFor = system: mkBasecampApp {
    pkgs = pkgsFor system;
    inherit system common flakeInputs testFiles;
    name = (configFor system).name;
    installPkg = lgxPackages.${system}.install;
    dependencies = (configFor system).dependencies;
    viewEntry = (configFor system).view;
  };

  # pkgs accessor that works whether or not buildCppPlugin ran
  pkgsFor = system:
    if hasBackend
    then built.perSystem.${system}.pkgs
    else common.mkPkgs system;

  # Helper: create a combined derivation from a plugin lib + QML view from source.
  # Used for both default and portable variants. For QML-only modules, pluginLib is null.
  iconFiles = lib.optional (config.icon != null) (src + "/${config.icon}");

  mkCombined = system: pluginLib: suffix:
    let pkgs = pkgsFor system;
        resolvedConfig = configFor system;
        concreteDeps = common.classifyConcreteDeps {
          inherit system flakeInputs src;
          config = resolvedConfig;
          builderName = "mkLogosQmlModule";
        };
        resolvedInterfaceDeps = map (e: {
          inherit (e) name impl_class;
          path = if e.input != null
                 then (if flakeInputs ? ${e.input}
                       then "${flakeInputs.${e.input}}/${e.file}"
                       else throw "interface_dependencies: interface '${e.name}' references flake input '${e.input}', but no such input was passed to mkLogosQmlModule (declare it in flake.nix and pass it via flakeInputs).")
                 else common.srcPathOf src e.file;
        }) resolvedConfig.interface_dependencies;
        dependencyContractInstall = common.installLidlContracts {
          inherit pkgs;
          specs = concreteDeps.staticDeps ++ resolvedInterfaceDeps;
          destination = "$out/share/logos";
        };
        logosSdkBuild = logos-cpp-sdk.packages.${common.buildSystemFor system}.default;
        iconInstall = pkgs.lib.concatStringsSep "\n" (map (icon: ''
          install -D -m644 ${icon} $out/lib/${config.icon}
        '') iconFiles);
    in (pkgs.runCommand "logos-${config.name}-module${suffix}" {
      nativeBuildInputs = [ logosSdkBuild ];
    } ''
      mkdir -p $out/lib

      ${lib.optionalString (pluginLib != null) ''
        # Copy library files (not symlinks)
        if [ -d "${pluginLib}/lib" ]; then
          cp -rL ${pluginLib}/lib/* $out/lib/
        fi
        if [ -d "${pluginLib}/share" ]; then
          mkdir -p $out/share
          cp -rL ${pluginLib}/share/. $out/share/
        fi
      ''}

      # UI plugins have no callable module interface of their own. They still
      # carry every required, optional and interface dependency contract.
      ${dependencyContractInstall}

      # Include metadata.json and icons in the output. The RESOLVED document
      # when the module has overlays — this file is what lgpm and the .lgx
      # manifest read, so shipping the source here is what made a platform-keyed
      # field resolve for the build and not for the artifact.
      cp ${shippedMetadataFor pkgs system} $out/lib/metadata.json
      ${iconInstall}

      # Copy QML view files from source.
      # C++ modules keep QML under src/ (e.g. src/qml/Main.qml);
      # QML-only modules may keep them at the project root (e.g. Main.qml or qml/Main.qml).
      # When viewDir is "." we only copy the single QML file to avoid pulling in
      # the entire project root (which would conflict with metadata.json above).
      if [ -d "${moduleSrc}/src/${viewDir}" ] && [ "${viewDir}" != "." ]; then
        mkdir -p "$out/lib/${viewDir}"
        cp -r "${moduleSrc}/src/${viewDir}/." "$out/lib/${viewDir}/"
        echo "Copied QML view directory from src/${viewDir}"
      elif [ -d "${moduleSrc}/${viewDir}" ] && [ "${viewDir}" != "." ]; then
        mkdir -p "$out/lib/${viewDir}"
        cp -r "${moduleSrc}/${viewDir}/." "$out/lib/${viewDir}/"
        echo "Copied QML view directory from ${viewDir}"
      elif [ -f "${moduleSrc}/src/${config.view}" ]; then
        cp "${moduleSrc}/src/${config.view}" "$out/lib/${config.view}"
        echo "Copied QML entry file from src/${config.view}"
      elif [ -f "${moduleSrc}/${config.view}" ]; then
        cp "${moduleSrc}/${config.view}" "$out/lib/${config.view}"
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
    '') // {
      inherit src;
      version = config.version;
      lgxAssets = { lidl = "share/logos"; };
    };

  # Package outputs
  packages = forAllSystems (system:
    let
      config = configFor system;
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

      # The launcher `nix run` uses, as a package so it lands in ./result/bin.
      # Run from the repo root it hot-reloads the view from source:
      #   nix build .#ui-dev
      #   ./result/bin/run-logos-standalone-ui
      ui-dev = (basecampAppFor system).package;
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
  # lgpm install has the QML files.
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

  # tests/*.mjs run against Basecamp with `nix run .#ui-tests`.
  apps = lib.warnIf (logosStandalone != null)
    "mkLogosQmlModule: logosStandalone is ignored — `nix run .` runs the module in Basecamp; see LOGOS_BASECAMP in logos-module-builder's README."
    forAllSystems (system: { default = (basecampAppFor system).app; }
    // lib.optionalAttrs (testFiles != []) { ui-tests = (basecampAppFor system).testsApp; });

  testsDir = src + "/tests";
  testFiles =
    if builtins.pathExists testsDir then
      map (n: testsDir + "/${n}")
        (builtins.filter (lib.hasSuffix ".mjs")
          (builtins.attrNames (builtins.readDir testsDir)))
    else [];

  # Merge view-module-specific LGX outputs into packages
  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (lgxPackages.${system} or {})
  ) packages;

in {
  packages = mergedPackages;
  # Empty, but present for every system: UI tests left `nix flake check` for
  # `nix run .#ui-tests`, and a flake that adds its own checks onto these
  # (`mapAttrs (system: c: c // mine) module.checks`) would otherwise lose them.
  checks = lib.genAttrs common.systems (_: {});
  devShells =
    if hasBackend
    then built.devShells
    else lib.genAttrs common.systems (system:
      { default = (pkgsFor system).mkShell {}; });
  inherit apps config;
  # The RESOLVED config per target — see the `configFor` comment above.
  configFor = lib.genAttrs common.systems configFor;
  inherit metadataJson;
}
