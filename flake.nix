{
  description = "Logos Module Builder - Shared library for building Logos modules with minimal boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    # SDK and module deps — owned by this builder, injected into backends
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-module.url = "github:logos-co/logos-module";
    # UI modules (type: ui, ui_qml) always use Qt
    logos-plugin-qt.url = "github:logos-co/logos-plugin-qt";
    # Core modules (type: core) use this backend — defaults to Qt, swappable later
    logos-plugin-core.url = "github:logos-co/logos-plugin-qt";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    nix-bundle-logos-module-install.url = "github:logos-co/nix-bundle-logos-module-install";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-module, logos-plugin-qt, logos-plugin-core, nix-bundle-logos-module-install, nix-bundle-lgx, logos-standalone-app, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });

      # Import the library functions
      # Use rawLib from backends — we inject logos-cpp-sdk/logos-module ourselves
      lib = import ./lib {
        inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app;
        inherit logos-cpp-sdk logos-module;
        inherit (nixpkgs) lib;
        uiBackend = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
        coreBackend = logos-plugin-core.rawLib or logos-plugin-core.lib;
        builderRoot = ./.;
      };
    in
    {
      # Export the library functions for use by modules
      lib = lib;

      # Also expose as an overlay for convenience
      overlays.default = final: prev: {
        logosModuleBuilder = lib;
      };

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

        ui-module = {
          path = ./templates/ui-module;
          description = "Logos UI module (C++ Qt widget) with logos-standalone-app runner";
        };

        ui-qml-module = {
          path = ./templates/ui-qml-module;
          description = "Logos QML UI module with logos-standalone-app runner";
        };
      };

      # Tests — pure Nix evaluation tests (no compilation)
      checks = forAllSystems ({ pkgs, system, ... }: {
        default = import ./tests {
          inherit pkgs;
          inherit (nixpkgs) lib;
          inherit (lib) parseMetadata common mkExternalLib;
        };
        # Integration test: actually builds a QML module from a fixture
        qml-integration = import ./tests/test-qml-integration.nix {
          inherit pkgs;
          mkLogosQmlModule = lib.mkLogosQmlModule;
          fixturesRoot = ./tests/fixtures;
        };
      });

      # Development shell for working on the builder itself
      devShells = forAllSystems ({ pkgs, system, ... }:
        let
          logosSdk = logos-cpp-sdk.packages.${system}.default;
          logosModule = logos-module.packages.${system}.default;
          uiLib = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
          backendShell = uiLib.devShellInputs pkgs { inherit logosModule; };
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = backendShell.nativeBuildInputs ++ [
              logosSdk
              pkgs.yq  # For YAML parsing in scripts
            ];
            buildInputs = backendShell.buildInputs;
            shellHook = ''
              ${backendShell.shellHook}
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              echo "Logos Module Builder development environment"
            '';
          };
        }
      );
    };
}
