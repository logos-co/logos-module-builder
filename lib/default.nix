# Main entry point for logos-module-builder library
# This file exports all the builder functions
{ nixpkgs, logos-cpp-sdk, logos-module, nix-bundle-lgx, logos-standalone-app, lib, builderRoot }:

let
  # Import common utilities
  common = import ./common.nix { inherit lib nix-bundle-lgx; };
  
  # Import the metadata parser (reads metadata.json)
  parseMetadata = import ./parseMetadata.nix { inherit lib; };

  # Import the core module builder
  mkLogosModule = import ./mkLogosModule.nix {
    inherit nixpkgs logos-cpp-sdk logos-module nix-bundle-lgx logos-standalone-app lib;
    inherit common parseMetadata builderRoot;
  };

  # Import the QML module builder (pure QML UI modules)
  mkLogosQmlModule = import ./mkLogosQmlModule.nix {
    inherit nixpkgs nix-bundle-lgx logos-standalone-app lib common parseMetadata;
  };
  
  # Import sub-builders
  mkModuleLib = import ./mkModuleLib.nix { inherit lib common; };
  mkModuleInclude = import ./mkModuleInclude.nix { inherit lib common; };
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;

in {
  # Main builders
  inherit mkLogosModule;       # C++ Qt plugin modules
  inherit mkLogosQmlModule;    # Pure QML UI modules

  # Lower-level standalone app builder
  inherit mkStandaloneApp;
  
  # Lower-level builders for advanced use cases
  inherit mkModuleLib;
  inherit mkModuleInclude;
  inherit mkExternalLib;
  
  # Utilities
  inherit parseMetadata;
  inherit common;
  
  # Version info
  version = "0.1.0";
}
