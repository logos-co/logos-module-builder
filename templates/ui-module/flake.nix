{
  description = "Logos UI Module (C++ Qt widget) — replace with your description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-nix.url = "github:logos-co/logos-nix";
    nixpkgs.follows = "logos-nix/nixpkgs";

    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    # Keep nixpkgs aligned to avoid two copies of Qt in the closure.
    logos-standalone-app.inputs.nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = { self, logos-module-builder, logos-standalone-app, nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # Build the module (packages, devShells, config, metadataJson) via the
      # standard module builder.  apps is added below without touching mkLogosModule.
      moduleOutputs = logos-module-builder.lib.mkLogosModule {
        src = ./.;
        configFile = ./module.yaml;
      };
    in
      moduleOutputs // {
        # `nix run .` launches the built plugin in logos-standalone-app.
        apps = forAllSystems (system:
          let
            pkgs = import nixpkgs { inherit system; };
            standalone = logos-standalone-app.packages.${system}.default;
            plugin = moduleOutputs.packages.${system}.default;
            # logos-standalone expects a directory containing both the shared
            # library and metadata.json.  mkLogosModule splits them across
            # $out/lib/ and $out/share/, so stage them together here.
            pluginDir = pkgs.runCommand "ui-example-plugin-dir" {} ''
              mkdir -p $out
              cp ${plugin}/lib/*_plugin.*  $out/
              cp ${./metadata.json} $out/metadata.json
            '';
            run = pkgs.writeShellScript "run-ui-example-standalone" ''
              exec ${standalone}/bin/logos-standalone-app "${pluginDir}" "$@"
            '';
          in {
            default = { type = "app"; program = "${run}"; };
          }
        );
      };
}
