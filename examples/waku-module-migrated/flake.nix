{
  description = "Logos Waku Module - Migrated to use logos-module-builder";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
  };

  outputs = { self, logos-module-builder, nixpkgs }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      
      # Custom preConfigure to handle libwaku which is pre-built
      preConfigure = ''
        # libwaku is expected to be in lib/ directory
        # In a real deployment, this would be copied from a nix derivation
        # or built from vendor/nwaku
        if [ ! -f lib/libwaku.dylib ] && [ ! -f lib/libwaku.so ]; then
          echo "Warning: libwaku not found in lib/"
          echo "Please build libwaku using build_libwaku.sh or provide pre-built library"
        fi
      '';
    };
}
