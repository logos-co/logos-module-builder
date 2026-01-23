{
  description = "External Library Module - Example wrapping an external C library";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
    
    # Example: External library as a flake input
    # Replace with your actual library source
    example-lib = {
      url = "github:example/example-lib";
      flake = false;  # Non-flake source
    };
  };

  outputs = { self, logos-module-builder, nixpkgs, example-lib }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      
      # Pass the external library input to the builder
      externalLibInputs = {
        example_lib = example-lib;
      };
    };
}
