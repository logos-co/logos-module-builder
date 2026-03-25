{
  description = "External Library Module — wraps a pre-built or vendored C/C++ library";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";

    # If your external library is a flake input (source to be built by Nix),
    # add it here and pass it via externalLibInputs below.
    # example-lib = {
    #   url = "github:example/example-lib";
    #   flake = false;
    # };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # If using a flake-input external library (uncomment and adapt):
      # externalLibInputs = {
      #   example_lib = inputs.example-lib;
      # };
    };
}
