# Main entry point for logos-module-builder library
# This file exports all the builder functions.
# The actual plugin build logic is delegated to the pluginBackend (e.g. logos-plugin-qt).
#
# logos-cpp-sdk and logos-module are owned by this builder and injected into
# backends — backends never resolve these deps themselves.
{ nixpkgs, lib, uiBackend, coreBackend, logos-cpp-sdk, logos-module, logos-test-framework, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app, builderRoot }:

let
  # Import common utilities (backend-agnostic)
  common = import ./common.nix { inherit lib nix-bundle-lgx; };

  # Import the metadata parser (reads metadata.json)
  parseMetadata = import ./parseMetadata.nix { inherit lib; };

  # Import the core module builder (routes to the right backend by type)
  mkLogosModule = import ./mkLogosModule.nix {
    inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app lib;
    inherit common parseMetadata builderRoot uiBackend coreBackend;
    inherit logos-cpp-sdk logos-module logos-test-framework;
  };

  # Import the QML module builder (pure QML UI modules — no plugin compilation)
  mkLogosQmlModule = import ./mkLogosQmlModule.nix {
    inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app lib common parseMetadata;
  };

  # Import sub-builders that remain backend-agnostic
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;

  # Import the test builder
  mkLogosModuleTests = import ./mkLogosModuleTests.nix {
    inherit nixpkgs lib common parseMetadata;
    inherit logos-cpp-sdk logos-test-framework;
  };

in {
  # Main builders
  inherit mkLogosModule;       # C++ Qt plugin modules (delegates to pluginBackend)
  inherit mkLogosQmlModule;    # Pure QML UI modules
  inherit mkLogosModuleTests;  # Unit tests for modules

  # Lower-level standalone app builder
  inherit mkStandaloneApp;

  # Lower-level builders for advanced use cases
  inherit mkExternalLib;

  # Utilities
  inherit parseMetadata;
  inherit common;

  # The active plugin backends
  inherit uiBackend coreBackend;

  # Version info
  version = "0.2.0";
}
