# Builder for pure QML UI modules.
# No C++ compilation — stages QML files + metadata.json + icons into a plugin directory.
{ nixpkgs, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app, lib, common, parseMetadata }:

{
  # Required: path to the QML source directory
  src,

  # Required: path to metadata.json
  configFile,

  # Optional: all flake inputs — dependencies in metadata.json are resolved automatically
  flakeInputs ? {},

  # Optional: override the logos-standalone-app used for `nix run`.
  # By default, QML UI modules automatically get apps.default wired up
  # using the standalone app bundled with logos-module-builder.
  logosStandalone ? null,
}:

let
  config = parseMetadata.parseModuleConfig (builtins.readFile configFile);

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  iconFiles = lib.optional (config.icon != null) (src + "/${config.icon}");

  packages = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      iconInstall = pkgs.lib.concatStringsSep "\n" (map (icon: ''
        mkdir -p $out/icons
        cp ${icon} $out/icons/${builtins.baseNameOf (toString icon)}
      '') iconFiles);

      # Flat plugin dir: what logos-standalone-app receives
      pluginDir = (pkgs.runCommand "logos-${config.name}-plugin-dir" {} ''
        mkdir -p $out
        find ${src} -maxdepth 1 -name "*.qml" -exec cp {} $out/ \;
        cp ${configFile} $out/metadata.json
        ${iconInstall}
      '') // { inherit src; };
    in {
      default = pluginDir;
      # lib/ layout expected by nix-bundle-lgx:
      #   $out/lib/   — QML files, icons, and metadata.json
      lib = (pkgs.runCommand "logos-${config.name}-lib" {} ''
        mkdir -p $out/lib
        find ${pluginDir} -maxdepth 1 -name "*.qml" -exec cp {} $out/lib/ \;
        if [ -d "${pluginDir}/icons" ]; then
          cp -r ${pluginDir}/icons $out/lib/
        fi
        cp ${configFile} $out/lib/metadata.json
      '') // { inherit src; };
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
        in {
          lgx = bundleLgx moduleLib;
          lgx-portable = bundleLgxPortable moduleLib;
          install = installDev moduleLib;
          install-portable = installPortable moduleLib;
        }
      );
    };

  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (optionalLgx.packages.${system} or {})
  ) packages;

  mkStandaloneApp = import ./mkStandaloneApp.nix;

  # Resolve the standalone app: explicit override > built-in from module-builder
  resolvedStandalone =
    if logosStandalone != null then logosStandalone
    else logos-standalone-app;

  optionalApps = {
    apps = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Collect all module dependencies (direct + transitive) for bundling
        allDeps = common.collectAllModuleDeps system flakeInputs config.dependencies;
      in {
        default = mkStandaloneApp {
          inherit pkgs;
          standalone   = resolvedStandalone.packages.${system}.default;
          qmlSrc       = src;
          metadataFile = configFile;
          dirName      = "logos-${config.name}-plugin-dir";
          format       = "qml";
          moduleDeps   = allDeps;
        };
      }
    );
  };

in {
  packages = mergedPackages;
  inherit config;
  metadataJson = builtins.readFile configFile;
} // optionalApps
