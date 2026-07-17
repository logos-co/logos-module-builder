{
  description = "Logos Module Builder - Shared library for building Logos modules with minimal boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    # Optional newer rustc for crates whose deps out-pace the nixpkgs rustc
    # (opt-in per module via metadata `nix.rust.toolchain`).
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    # SDK and module deps — owned by this builder, injected into backends
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-cpp-sdk.inputs.logos-protocol.follows = "logos-protocol";
    # Protocol layer (transports + lp_* C ABI + the protocol semver every
    # module gets stamped with) and the Qt developer layer modules link.
    logos-protocol.url = "github:logos-co/logos-protocol";
    logos-qt-sdk.url = "github:logos-co/logos-qt-sdk";
    logos-qt-sdk.inputs.logos-protocol.follows = "logos-protocol";
    logos-qt-sdk.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-module.url = "github:logos-co/logos-module";
    # UI modules (type: ui, ui_qml) always use Qt
    logos-plugin-qt.url = "github:logos-co/logos-plugin-qt";
    # Core modules (type: core) use this backend — defaults to Qt, swappable later
    logos-plugin-core.url = "github:logos-co/logos-plugin-qt";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    nix-bundle-logos-module-install.url = "github:logos-co/nix-bundle-logos-module-install";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    # Test framework for module unit tests
    logos-test-framework.url = "github:logos-co/logos-test-framework";
    logos-test-framework.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    # The Rust SDK provides logos-lidl-gen (the generator the builder runs for
    # codegen.rust modules) and the SDK source the crate links. logos-rust-sdk
    # depends BACK on this builder for its own integration tests, so its
    # logos-module-builder input is cut with `follows` to break the cycle — we
    # only consume its lidl-gen package + source tree, never its tests. The other
    # branch-pinned test-only inputs are cut too so they aren't fetched.
    logos-rust-sdk.url = "github:logos-co/logos-rust-sdk/92a5c720c58f784cd944c940756f7b69a264dc07";
    logos-rust-sdk.inputs.logos-nix.follows = "logos-nix";
    logos-rust-sdk.inputs.logos-module-builder.follows = "logos-cpp-sdk";
    logos-rust-sdk.inputs.logos-logoscore-cli.follows = "logos-cpp-sdk";
    nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-protocol, logos-qt-sdk, logos-module, logos-plugin-qt, logos-plugin-core, nix-bundle-logos-module-install, nix-bundle-lgx, logos-standalone-app, logos-test-framework, logos-rust-sdk, rust-overlay ? null, ... }:
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
        inherit logos-cpp-sdk logos-protocol logos-qt-sdk logos-module logos-test-framework logos-rust-sdk;
        inherit rust-overlay;
        inherit (nixpkgs) lib;
        uiBackend = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
        coreBackend = logos-plugin-core.rawLib or logos-plugin-core.lib;
        builderRoot = ./.;
      };
    in
    {
      # Export the library functions for use by modules
      lib = lib;

      # The logos-rust-sdk source tree at the rev this builder pins — exposed so a
      # codegen.rust module can stage it as `../logos-rust-sdk-src` to generate its
      # Cargo.lock against the SAME SDK the builder links, without needing a
      # logos-rust-sdk input in the module's own flake.
      packages = forAllSystems ({ pkgs, ... }: {
        rust-sdk-src = pkgs.runCommand "logos-rust-sdk-src" {} "cp -r ${logos-rust-sdk} $out";
      });

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

        ui-qml-backend = {
          path = ./templates/ui-qml-backend;
          description = "Logos ui_qml module with C++ backend (process-isolated) and QML view";
        };

        ui-qml = {
          path = ./templates/ui-qml;
          description = "Logos ui_qml module (QML-only, no C++ backend)";
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
        # Integration test: builds and runs unit tests via logos-test-framework
        test-framework-integration = import ./tests/test-framework-integration.nix {
          inherit pkgs;
          mkLogosModuleTests = lib.mkLogosModuleTests;
          inherit (lib) parseMetadata;
          fixturesRoot = ./tests/fixtures;
        };
        # Integration test: verifies static library (.a) support in EXTERNAL_LIBS
        static-extlib = import ./tests/test-static-extlib.nix {
          inherit pkgs;
        };
        # Integration test: a Rust cdylib module with an external system build dep
        # declared via the `nix.rust` block — proves pkg-config/openssl-style deps
        # reach the crate's buildRustPackage compile.
        rust-native-dep = import ./tests/test-rust-native-dep.nix {
          inherit pkgs;
          mkLogosModule = lib.mkLogosModule;
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
