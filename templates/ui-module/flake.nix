{
  description = "Logos UI Module (C++ Qt widget) — replace with your description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
  };

  outputs = { logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      logosStandalone = logos-standalone-app;
      # iconFiles = [ ./icons/my.png ];
    };
}
