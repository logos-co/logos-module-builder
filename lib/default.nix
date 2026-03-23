# Main entry point for logos-module-builder library
# This file exports all the builder functions
{ nixpkgs, logos-cpp-sdk, logos-module, lib, builderRoot }:

let
  # Import common utilities
  common = import ./common.nix { inherit lib; };
  
  # Import the YAML parser
  parseModuleYaml = import ./parseModuleYaml.nix { inherit lib; };
  
  # Import the core module builder
  mkLogosModule = import ./mkLogosModule.nix { 
    inherit nixpkgs logos-cpp-sdk logos-module lib;
    inherit common parseModuleYaml builderRoot;
  };
  
  # Import sub-builders
  mkModuleLib = import ./mkModuleLib.nix { inherit lib common; };
  mkModuleInclude = import ./mkModuleInclude.nix { inherit lib common; };
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;

in {
  # Main function to build a complete module
  inherit mkLogosModule;

  # apps.default for logos-standalone-app
  inherit mkStandaloneApp;
  
  # Lower-level builders for advanced use cases
  inherit mkModuleLib;
  inherit mkModuleInclude;
  inherit mkExternalLib;
  
  # Utilities
  inherit parseModuleYaml;
  inherit common;
  
  # Version info
  version = "0.1.0";
}
