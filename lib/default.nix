# Main entry point for logos-module-builder library
# This file exports all the builder functions.
# The actual plugin build logic is delegated to the pluginBackend (e.g. logos-plugin-qt).
{ nixpkgs, lib, uiBackend, coreBackend, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app, builderRoot }:

let
  # Import common utilities (backend-agnostic)
  common = import ./common.nix { inherit lib nix-bundle-lgx; };

  # Import the metadata parser (reads metadata.json)
  parseMetadata = import ./parseMetadata.nix { inherit lib; };

  # Import the core module builder (routes to the right backend by type)
  mkLogosModule = import ./mkLogosModule.nix {
    inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app lib;
    inherit common parseMetadata builderRoot uiBackend coreBackend;
  };

  # Import the QML module builder (pure QML UI modules — no plugin compilation)
  mkLogosQmlModule = import ./mkLogosQmlModule.nix {
    inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app lib common parseMetadata;
  };

  # Import sub-builders that remain backend-agnostic
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;

in {
  # Main builders
  inherit mkLogosModule;       # C++ Qt plugin modules (delegates to pluginBackend)
  inherit mkLogosQmlModule;    # Pure QML UI modules

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
