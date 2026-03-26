# Builder for pure QML UI modules.
# No C++ compilation — stages QML files + metadata.json + icons into a plugin directory.
{ nixpkgs, lib, common, parseMetadata }:

{
  # Required: path to the QML source directory
  src,

  # Required: path to metadata.json
  configFile,

  # Optional: all flake inputs — dependencies in metadata.json are resolved automatically
  flakeInputs ? {},

  # Required for nix run: pass the logos-standalone-app flake input directly
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

  # LGX package outputs (when nix-bundle-lgx is in flakeInputs)
  nixBundleLgx = flakeInputs.nix-bundle-lgx or null;

  optionalLgx =
    if nixBundleLgx == null then {}
    else {
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

  mergedPackages =
    if optionalLgx == {} then packages
    else lib.mapAttrs (system: sysPkgs:
      sysPkgs // (optionalLgx.packages.${system} or {})
    ) packages;

  optionalApps =
    if logosStandalone == null then {}
    else {
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          pluginDir = packages.${system}.default;
          run = pkgs.writeShellApplication {
            name = "run-logos-standalone-ui";
            runtimeInputs = [ logosStandalone.packages.${system}.default ];
            text = ''exec ${logosStandalone.packages.${system}.default}/bin/logos-standalone-app "${pluginDir}" "$@"'';
          };
        in {
          default = { type = "app"; program = "${run}/bin/run-logos-standalone-ui"; };
        }
      );
    };

in {
  packages = mergedPackages;
  inherit config;
  metadataJson = builtins.readFile configFile;
} // optionalApps
