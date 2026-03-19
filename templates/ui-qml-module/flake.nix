{
  description = "Logos QML UI Module — replace with your description";

  inputs = {
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    nixpkgs.follows = "logos-cpp-sdk/nixpkgs";

    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    logos-standalone-app.inputs.logos-liblogos.inputs.nixpkgs.follows =
      "logos-cpp-sdk/nixpkgs";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-standalone-app }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
    in {
      packages = forAllSystems ({ pkgs }: let
        plugin = pkgs.stdenv.mkDerivation {
          pname = "logos-ui-qml-example-plugin";
          version = "1.0.0";
          src = ./.;

          dontUnpack = false;
          phases = [ "unpackPhase" "installPhase" ];

          installPhase = ''
            runHook preInstall

            dest="$out/lib"
            mkdir -p "$dest"

            cp $src/Main.qml      "$dest/Main.qml"
            cp $src/metadata.json "$dest/metadata.json"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "QML UI module example for Logos";
            platforms = platforms.unix;
          };
        };
      in {
        default = plugin;
        lib = plugin;
      });

      # `nix run .` launches this module in logos-standalone-app.
      # Files are installed to $out/lib/ so we pass that subdirectory.
      apps = forAllSystems ({ pkgs }: let
        standaloneAppPkg = logos-standalone-app.packages.${pkgs.system}.default;
        plugin = self.packages.${pkgs.system}.default;
        runScript = pkgs.writeShellScript "run-ui-qml-example-standalone" ''
          exec ${standaloneAppPkg}/bin/logos-standalone-app "${plugin}/lib" "$@"
        '';
      in {
        default = {
          type = "app";
          program = "${runScript}";
        };
      });
    };
}
