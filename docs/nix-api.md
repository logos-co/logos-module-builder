# Nix API Reference

Complete reference for logos-module-builder Nix functions.

## Overview

The logos-module-builder exposes its API via `lib` attribute:

```nix
logos-module-builder.lib.mkLogosModule { ... }
```

## mkLogosModule

The main function to build a C++ Qt plugin module.

### Syntax

```nix
mkLogosModule {
  src = ./.;
  configFile = ./metadata.json;

  # Optional
  flakeInputs = inputs;        # Pass all flake inputs — deps auto-resolved
  externalLibInputs = { };     # For external C libs fetched as flake inputs
  extraBuildInputs = [ ];
  extraNativeBuildInputs = [ ];
  configOverrides = { };
  preConfigure = "";
  postInstall = "";
  logosStandalone = null;      # Pass logos-standalone-app for `nix run` support
}
```

### Parameters

#### src (required)
Path to the module source directory.

```nix
src = ./.;
```

#### configFile (required)
Path to the `metadata.json` configuration file.

```nix
configFile = ./metadata.json;
```

#### flakeInputs (optional)
All flake `inputs`. The builder automatically filters this by `dependencies` in `metadata.json` to resolve module dependencies — you don't need to pass them individually.

```nix
outputs = inputs@{ logos-module-builder, ... }:
  logos-module-builder.lib.mkLogosModule {
    src = ./.;
    configFile = ./metadata.json;
    flakeInputs = inputs;  # dependencies[] in metadata.json are resolved automatically from input names
  };
```

#### externalLibInputs (optional)
Flake inputs for external C/C++ libraries that need to be built from source. Keys must match library names in `metadata.json`'s `nix.external_libraries`. For pre-built vendor libraries, use `vendor_path` in `metadata.json` instead — no `externalLibInputs` needed.

```nix
externalLibInputs = {
  gowalletsdk = inputs.go-wallet-sdk;
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
Override values from `metadata.json`. Merged recursively.

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

#### logosStandalone (optional)
Pass the `logos-standalone-app` flake input to register `apps.default` for `nix run`. Only valid when `metadata.json` has `"type": "ui"`.

```nix
logosStandalone = logos-standalone-app;
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
      lgx = <lgx package>;              # only when nix-bundle-lgx is in flakeInputs
      lgx-portable = <portable lgx>;    # only when nix-bundle-lgx is in flakeInputs
    };
  };

  devShells = {
    <system> = {
      default = <dev shell>;
    };
  };

  apps = { ... };  # only when logosStandalone is set

  config = <parsed config>;
  metadataJson = <metadata.json content>;
}
```

### Example

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    waku_module.url = "github:logos-co/logos-waku-module";  # input name must match dependency name
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      preConfigure = ''
        echo "Building my module..."
      '';
    };
}
```

---

## mkLogosQmlModule

Builder for pure QML UI modules. No C++ compilation — stages QML files, `metadata.json`, and icons into a plugin directory.

### Syntax

```nix
mkLogosQmlModule {
  src = ./.;
  configFile = ./metadata.json;

  # Optional
  flakeInputs = inputs;
  logosStandalone = null;  # Pass logos-standalone-app for `nix run`
}
```

### Return Value

```nix
{
  packages = {
    <system> = {
      default = <plugin directory>;
      lib = <lib-layout package for nix-bundle-lgx>;
      lgx = <lgx package>;              # only when nix-bundle-lgx is in flakeInputs
      lgx-portable = <portable lgx>;    # only when nix-bundle-lgx is in flakeInputs
    };
  };
  apps = { ... };  # only when logosStandalone is set
  config = <parsed config>;
  metadataJson = <metadata.json content>;
}
```

---

## parseMetadata

Parse a `metadata.json` file.

### parseModuleConfig

Parse JSON content and apply defaults.

```nix
let
  config = logos-module-builder.lib.parseMetadata.parseModuleConfig
    (builtins.readFile ./metadata.json);
in {
  inherit (config) name version type category description;
  inherit (config) dependencies nix_packages external_libraries cmake;
}
```

---

## common

Utility functions.

### systems

List of supported systems.

```nix
logos-module-builder.lib.common.systems
# [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
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

Build external libraries from flake inputs.

```nix
logos-module-builder.lib.mkExternalLib.buildExternalLibs {
  pkgs = ...;
  config = ...;
  externalInputs = { };
}
```

### mkStandaloneApp

Build the `apps.default` entry for `nix run`.

```nix
logos-module-builder.lib.mkStandaloneApp {
  pkgs = ...;
  standalone = logos-standalone-app.packages.${system}.default;
  plugin = self.packages.${system}.default;
  metadataFile = ./metadata.json;
  format = "qt-plugin";  # or "qml"
}
```

## version

Library version string.

```nix
logos-module-builder.lib.version
# "0.1.0"
```
