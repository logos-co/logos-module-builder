{
  description = "Logos QML UI Module — replace with your description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";

    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
  };

  outputs = { logos-module-builder, logos-standalone-app, nixpkgs, ... }: {
    apps = nixpkgs.lib.genAttrs
      [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
      (system: {
        default = logos-module-builder.lib.mkStandaloneApp {
          pkgs = import nixpkgs { inherit system; };
          standalone = logos-standalone-app.packages.${system}.default;
          qmlSrc = ./.;
          metadataFile = ./metadata.json;
          # iconFiles = [ ./icons/my.png ];
          format = "qml";
        };
      });
  };
}
