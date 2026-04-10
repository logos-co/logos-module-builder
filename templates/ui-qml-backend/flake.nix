{
  description = "Logos ui_qml module (C++ backend + QML view) — replace with your description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add core module dependencies as inputs (must match metadata.json "dependencies"), e.g.:
    # some_module.url = "github:logos-co/logos-some-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
