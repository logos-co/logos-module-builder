# Nix API Reference

Complete reference for logos-module-builder Nix functions.

## Overview

The logos-module-builder exposes its API via `lib` attribute:

```nix
logos-module-builder.lib.mkLogosModule { ... }
```

## mkLogosModule

The main function to build a complete Logos module.

### Syntax

```nix
mkLogosModule {
  src = ./.;
  configFile = ./module.yaml;
  
  # Optional
  moduleInputs = { };
  externalLibInputs = { };
  extraBuildInputs = [ ];
  extraNativeBuildInputs = [ ];
  configOverrides = { };
  preConfigure = "";
  postInstall = "";
}
```

### Parameters

#### src (required)
Path to the module source directory.

```nix
src = ./.;
```

#### configFile (required)
Path to the `module.yaml` configuration file.

```nix
configFile = ./module.yaml;
```

#### moduleInputs (optional)
Flake inputs for Logos module dependencies. Keys must match dependency names in `module.yaml`.

```nix
moduleInputs = {
  waku_module = logos-waku-module;
  chat = logos-chat-module;
};
```

These are used to:
1. Copy generated headers at build time
2. Resolve runtime dependencies

#### externalLibInputs (optional)
Flake inputs for external C/C++ libraries. Keys must match library names in `module.yaml`.

```nix
externalLibInputs = {
  go_wallet_sdk = go-wallet-sdk-src;
  mylib = mylib-src;
};
```

#### extraBuildInputs (optional)
Additional Nix packages to add to `buildInputs`.

```nix
extraBuildInputs = with pkgs; [
  openssl
  libsodium
];
```

#### extraNativeBuildInputs (optional)
Additional Nix packages to add to `nativeBuildInputs` (build-time only).

```nix
extraNativeBuildInputs = with pkgs; [
  rustc
  cargo
];
```

#### configOverrides (optional)
Override values from `module.yaml`. Merged recursively.

```nix
configOverrides = {
  version = "2.0.0";
  nix_packages = {
    build = [ "extra-package" ];
  };
};
```

#### preConfigure (optional)
Shell commands to run before CMake configuration.

```nix
preConfigure = ''
  # Custom setup
  echo "Running custom preConfigure"
  ./scripts/generate-something.sh
'';
```

#### postInstall (optional)
Shell commands to run after installation.

```nix
postInstall = ''
  # Custom post-install
  mkdir -p $out/share
  cp extra-files/* $out/share/
'';
```

### Return Value

Returns an attribute set with:

```nix
{
  packages = {
    <system> = {
      default = <combined package>;
      <name>-lib = <library package>;
      <name>-include = <headers package>;
      lib = <library package>;
      include = <headers package>;
    };
  };
  
  devShells = {
    <system> = {
      default = <dev shell>;
    };
  };
  
  config = <parsed config>;
  metadataJson = <metadata.json content>;
}
```

### Example

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
    logos-waku-module.url = "github:logos-co/logos-waku-module";
  };

  outputs = { self, logos-module-builder, nixpkgs, logos-waku-module }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      moduleInputs = {
        waku_module = logos-waku-module;
      };
      extraBuildInputs = [ ];
      preConfigure = ''
        echo "Building my module..."
      '';
    };
}
```

## parseModuleYaml

Parse a `module.yaml` file.

### fromYAML

Parse a YAML string.

```nix
let
  yaml = builtins.readFile ./module.yaml;
  config = logos-module-builder.lib.parseModuleYaml.fromYAML yaml;
in config.name  # "my_module"
```

### parseModuleConfig

Parse YAML and apply defaults.

```nix
let
  yaml = builtins.readFile ./module.yaml;
  config = logos-module-builder.lib.parseModuleYaml.parseModuleConfig yaml;
in {
  inherit (config) name version type category description;
  inherit (config) dependencies nix_packages external_libraries cmake;
}
```

### parseFile

Read and parse a file.

```nix
let
  config = logos-module-builder.lib.parseModuleYaml.parseFile ./module.yaml;
in config.name
```

## common

Utility functions.

### systems

List of supported systems.

```nix
logos-module-builder.lib.common.systems
# [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
```

### forAllSystems

Run function for all systems.

```nix
logos-module-builder.lib.common.forAllSystems nixpkgs (system: pkgs: {
  # ...
})
```

### getLibExtension

Get library extension for platform.

```nix
logos-module-builder.lib.common.getLibExtension pkgs
# "dylib" on macOS, "so" on Linux
```

### getPluginFilename

Get plugin filename for module.

```nix
logos-module-builder.lib.common.getPluginFilename pkgs "my_module"
# "my_module_plugin.dylib" or "my_module_plugin.so"
```

### commonNativeBuildInputs

Standard native build inputs.

```nix
logos-module-builder.lib.common.commonNativeBuildInputs pkgs
# [ cmake ninja pkg-config qt6.wrapQtAppsNoGuiHook ]
```

### commonBuildInputs

Standard build inputs.

```nix
logos-module-builder.lib.common.commonBuildInputs pkgs
# [ qt6.qtbase qt6.qtremoteobjects ]
```

### generateMetadataJson

Generate metadata.json content from config.

```nix
logos-module-builder.lib.common.generateMetadataJson config
# '{"name":"my_module","version":"1.0.0",...}'
```

### nameFormats

Convert module name to various formats.

```nix
logos-module-builder.lib.common.nameFormats "my_module"
# { snake = "my_module"; pascal = "MyModule"; camel = "myModule"; upper = "MY_MODULE"; }
```

## Lower-level Builders

For advanced use cases, you can use the lower-level builders directly.

### mkModuleLib

Build the plugin library.

```nix
logos-module-builder.lib.mkModuleLib.build {
  pkgs = ...;
  src = ...;
  config = ...;
  commonArgs = ...;
  logosSdk = ...;
  moduleDeps = { };
  externalLibs = { };
  preConfigure = "";
  postInstall = "";
}
```

### mkModuleInclude

Build generated headers.

```nix
logos-module-builder.lib.mkModuleInclude.build {
  pkgs = ...;
  src = ...;
  config = ...;
  commonArgs = ...;
  logosSdk = ...;
  lib = <built library>;
}
```

### mkExternalLib

Build external libraries.

```nix
logos-module-builder.lib.mkExternalLib.buildExternalLibs {
  pkgs = ...;
  config = ...;
  externalInputs = { };
}
```

## version

Library version string.

```nix
logos-module-builder.lib.version
# "0.1.0"
```
