{
  description = "Rust External Library Module — wraps a C library from a Rust crate";

  # Identical to a C++ module's inputs: the builder provides both the code
  # generator and the logos-rust-sdk source the crate links. The external C
  # library is named in metadata.json (nix.rust / nix.packages), not here.
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
