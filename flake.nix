{
  description = "Logos Module Builder - Shared library for building Logos modules with minimal boilerplate";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos.url = "github:logos-co/logos-liblogos";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-liblogos }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosLiblogos = logos-liblogos.packages.${system}.default;
      });
      
      # Import the library functions
      lib = import ./lib {
        inherit nixpkgs logos-cpp-sdk logos-liblogos;
        inherit (nixpkgs) lib;
      };
    in
    {
      # Export the library functions for use by modules
      lib = lib;
      
      # Also expose as an overlay for convenience
      overlays.default = final: prev: {
        logosModuleBuilder = lib;
      };
      
      # Provide the cmake module as a package
      packages = forAllSystems ({ pkgs, ... }: {
        cmake-module = pkgs.runCommand "logos-module-cmake" {} ''
          mkdir -p $out/share/cmake/LogosModule
          cp ${./cmake/LogosModule.cmake} $out/share/cmake/LogosModule/LogosModule.cmake
        '';
        
        default = self.packages.${pkgs.system}.cmake-module;
      });
      
      # Templates for scaffolding new modules
      templates = {
        default = {
          path = ./templates/minimal-module;
          description = "Minimal Logos module template";
        };
        
        with-external-lib = {
          path = ./templates/external-lib-module;
          description = "Logos module template with external library";
        };
      };
      
      # Development shell for working on the builder itself
      devShells = forAllSystems ({ pkgs, logosSdk, logosLiblogos, ... }: {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.yq  # For YAML parsing in scripts
          ];
          buildInputs = [
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
          ];
          
          shellHook = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_ROOT="${logosLiblogos}"
            echo "Logos Module Builder development environment"
          '';
        };
      });
    };
}
