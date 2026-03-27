{
  description = "Logos QML UI Module — replace with your description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
