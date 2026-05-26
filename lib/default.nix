# Main entry point for logos-module-builder library
# This file exports all the builder functions.
# The actual plugin build logic is delegated to the pluginBackend (e.g. logos-plugin-qt).
#
# logos-cpp-sdk and logos-module are owned by this builder and injected into
# backends — backends never resolve these deps themselves.
#
# App-specific builders (mkLogosQmlModule, mkStandaloneApp) have been moved to
# logos-app-builder. This library exposes buildCppPlugin so app-builder can
# reuse the C++ compilation pipeline.
{ nixpkgs, lib, uiBackend, coreBackend, logos-cpp-sdk, logos-module, logos-test-framework, nix-bundle-lgx, nix-bundle-logos-module-install, builderRoot }:

let
  # Import common utilities (backend-agnostic)
  common = import ./common.nix { inherit lib; };

  # Import the metadata parser (reads metadata.json)
  parseMetadata = import ./parseMetadata.nix { inherit lib; };

  # Import the core module builder (routes to the right backend by type)
  mkLogosModule = import ./mkLogosModule.nix {
    inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install lib;
    inherit common parseMetadata builderRoot uiBackend coreBackend;
    inherit logos-cpp-sdk logos-module logos-test-framework;
  };

  # Import the shared C++ plugin build pipeline
  buildCppPlugin = import ./buildCppPlugin.nix {
    inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install lib;
    inherit common parseMetadata logos-cpp-sdk logos-module uiBackend coreBackend;
  };

  # Import sub-builders that remain backend-agnostic
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };

  # Import the test builder
  mkLogosModuleTests = import ./mkLogosModuleTests.nix {
    inherit nixpkgs lib common parseMetadata;
    inherit logos-cpp-sdk logos-test-framework;
  };

in {
  # Main builders
  inherit mkLogosModule;
  inherit mkLogosModuleTests;

  # Shared C++ build pipeline (used by logos-app-builder for ui_qml backends)
  inherit buildCppPlugin;

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
