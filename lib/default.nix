# Main entry point for logos-module-builder library
# This file exports all the builder functions
{ nixpkgs, logos-cpp-sdk, logos-module, nix-bundle-lgx, logos-standalone-app, lib, builderRoot }:

let
  # Import common utilities
  common = import ./common.nix { inherit lib nix-bundle-lgx; };

  # Import the metadata parser (reads metadata.json)
  parseMetadata = import ./parseMetadata.nix { inherit lib; };

  # Import the core module builder (C++ Qt plugin modules)
  mkLogosModule = import ./mkLogosModule.nix {
    inherit nixpkgs logos-cpp-sdk logos-module nix-bundle-lgx logos-standalone-app lib;
    inherit common parseMetadata builderRoot;
  };

  # Import the QML module builder (pure QML UI modules)
  mkLogosQmlModule = import ./mkLogosQmlModule.nix {
    inherit nixpkgs nix-bundle-lgx logos-standalone-app lib common parseMetadata;
  };

  # Import the CBOR C++ module builder (cbor-exe and cbor-plugin backends, Qt-free)
  mkLogosCborModule = import ./mkLogosCborModule.nix {
    inherit nixpkgs logos-cpp-sdk nix-bundle-lgx lib common parseMetadata builderRoot;
  };

  # Import the Rust module builder (Rust CBOR modules)
  mkLogosRustModule = import ./mkLogosRustModule.nix {
    inherit nixpkgs logos-cpp-sdk nix-bundle-lgx lib common parseMetadata;
  };

  # Import sub-builders
  mkModuleLib = import ./mkModuleLib.nix { inherit lib common; };
  mkModuleInclude = import ./mkModuleInclude.nix { inherit lib common; };
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;

  # Auto-routing builder: dispatches to the correct backend builder based on
  # the language and backend fields in metadata.json.
  #   language = "rust"                           -> mkLogosRustModule
  #   backend  = "cbor-exe" | "cbor-plugin"       -> mkLogosCborModule
  #   otherwise (default: language=cpp, qt-plugin) -> mkLogosModule
  mkModule = args:
    let
      config = parseMetadata.parseModuleConfig (builtins.readFile args.configFile);
    in
      if config.language == "rust" then mkLogosRustModule args
      else if config.backend == "cbor-exe" || config.backend == "cbor-plugin" then mkLogosCborModule args
      else mkLogosModule args;

in {
  # Auto-routing builder (picks backend from metadata.json)
  inherit mkModule;

  # Main builders
  inherit mkLogosModule;       # C++ Qt plugin modules
  inherit mkLogosQmlModule;    # Pure QML UI modules
  inherit mkLogosCborModule;   # C++ CBOR modules (Qt-free)
  inherit mkLogosRustModule;   # Rust CBOR modules

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
