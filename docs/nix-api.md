# Nix API Reference

Complete reference for logos-module-builder Nix functions.

## Overview

The logos-module-builder exposes its API via `lib` attribute:

```nix
logos-module-builder.lib.mkLogosModule { ... }     # core + legacy UI widgets
logos-module-builder.lib.buildCppPlugin { ... }    # shared C++ build pipeline (used by logos-app-builder)
```

> **Note:** `mkLogosQmlModule`, `mkStandaloneApp`, and `collectAllModuleDeps` have been moved to [`logos-app-builder`](https://github.com/logos-co/logos-app-builder). Use `logos-app-builder.lib.mkLogosQmlModule` for `ui_qml` modules and `logos-app-builder.lib.mkLogosApp` to add standalone app launching to legacy UI modules.

## mkLogosModule

Builder for core C++ modules and legacy UI widget modules. For `ui_qml` modules (QML view with optional C++ backend), use [`logos-app-builder.lib.mkLogosQmlModule`](https://github.com/logos-co/logos-app-builder) instead.

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
  preConfigure = "";           # String or function: { externalLibs }: "..."
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
Flake inputs for external C/C++ libraries. Keys must match library names in `metadata.json`'s `nix.external_libraries`. For pre-built vendor libraries, use `vendor_path` in `metadata.json` instead — no `externalLibInputs` needed.

The builder auto-detects whether the resolved input is a Nix derivation (via `lib.isDerivation`). If it is, the derivation is used directly. If it's raw source, it's built with `make` / custom command. No flags needed in `metadata.json`.

**Simple format** — bare flake input, resolves to `packages.${system}.default`:

```nix
externalLibInputs = {
  gowalletsdk = inputs.go-wallet-sdk;
};
```

**Structured format** — per-variant package mappings. When any entry uses this format, the builder produces both `lib` and `lib-portable` outputs, each linked against the corresponding external lib variant. The `lgx` output bundles `lib` and `lgx-portable` bundles `lib-portable`.

```nix
externalLibInputs = {
  logos_pm = {
    input = inputs.logos-package-manager;
    packages = {
      default = "lib";           # → input.packages.${system}.lib
      portable = "lib-portable"; # → input.packages.${system}.lib-portable
    };
  };
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

#### metadata.json: `interface`, `codegen`, and Go static libs (automatic)

The builder prepends steps before your `preConfigure`:

- **`"interface": "universal"`** — runs `logos-cpp-generator --from-header` on `src/<name>_impl.h` (impl class derived from the module name, e.g. `accounts_module` → `AccountsModuleImpl`). Optional overrides:

  ```json
  "interface": "universal",
  "codegen": {
    "impl_header": "src/custom_impl.h",
    "impl_class": "CustomImpl"
  }
  ```

- **`"interface": "provider"`** — runs `logos-cpp-generator --provider-header` on `src/<name>_impl.h`. Override with `"codegen": { "provider_header": "src/other.h" }`.

- **External libraries** — `logos-plugin-qt` already copies flake-built externals into `lib/` before your hook; you usually do **not** need to `cp` them in `preConfigure`.

- **`go_build: true`** on an `nix.external_libraries` entry — passes `-DLOGOS_MODULE_GO_STATIC_LIBS=…` to CMake so `LogosModule.cmake` links the static archive with whole-archive / `-force_load` as needed.

When this flake contains `cmake/LogosModule.cmake`, `LOGOS_MODULE_BUILDER_ROOT` is overridden to point at **this** flake's source so the extended macros are used (auto `metadata.json` copy into the build dir, `generated_code/*.cpp` glob, Go linking). If that path is missing (older published revisions), `LOGOS_MODULE_BUILDER_ROOT` is **not** overridden — the backend's default takes over, pointing at its own root which already provides `cmake/LogosModule.cmake`.

#### preConfigure (optional)
Extra shell commands (or a function) appended **after** the automatic codegen / setup above.

**String form** — plain shell commands:

```nix
preConfigure = ''
  echo "Running custom preConfigure"
  ./scripts/generate-something.sh
'';
```

**Function form** — receives `{ externalLibs }` with resolved store paths keyed by library name:

```nix
preConfigure = { externalLibs }: ''
  # Only when you need something beyond the defaults
  echo "extra step using ${externalLibs.mylib}"
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

```nix
{
  packages = {
    <system> = {
      default = <combined package>;
      <name>-lib = <library package>;
      <name>-include = <headers package>;
      lib = <library package>;
      include = <headers package>;
      lgx = <lgx package>;              # always included
      lgx-portable = <portable lgx>;    # always included
      install = <dev install package>;  # always included
      install-portable = <portable install package>;  # always included

      # Only when externalLibInputs uses structured format with variants:
      <name>-lib-portable = <portable library package>;
      lib-portable = <portable library package>;
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

> **Note:** `mkLogosModule` no longer produces `apps` output. To add standalone app launching (`nix run`) to a UI module, use [`logos-app-builder.lib.mkLogosApp`](https://github.com/logos-co/logos-app-builder).

### Example

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
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

## mkLogosQmlModule (moved to logos-app-builder)

> **Moved:** This function is now in [`logos-app-builder.lib.mkLogosQmlModule`](https://github.com/logos-co/logos-app-builder).

```nix
# Use logos-app-builder, not logos-module-builder:
logos-app-builder.lib.mkLogosQmlModule {
  src = ./.;
  configFile = ./metadata.json;
  flakeInputs = inputs;
}
```

See the [logos-app-builder README](https://github.com/logos-co/logos-app-builder) for full API documentation, parameters, return values, and examples.

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

### nameFormats

Convert module name to various formats.

```nix
logos-module-builder.lib.common.nameFormats "my_module"
# { snake = "my_module"; pascal = "MyModule"; camel = "myModule"; upper = "MY_MODULE"; }
```

## Lower-level Builders

For advanced use cases, you can use some lower-level builders directly. Plugin compilation has been delegated to backends — `mkModuleLib` and `mkModuleInclude` no longer exist.

### Plugin Backends

Plugin compilation is delegated to a backend (e.g. `logos-plugin-qt`). The active backends are exposed as `uiBackend` and `coreBackend`:

```nix
logos-module-builder.lib.uiBackend.buildPlugin { ... }
logos-module-builder.lib.uiBackend.buildHeaders { ... }
logos-module-builder.lib.coreBackend.buildPlugin { ... }
```

These are internal implementation details — most modules don't need to call them directly.

### mkExternalLib

Build/resolve external libraries from flake inputs. Returns an attrset mapping library names to derivations. If a resolved input is already a Nix derivation (`lib.isDerivation`), it is used directly; otherwise the source is built with `make` / custom command.

```nix
logos-module-builder.lib.mkExternalLib.buildExternalLibs {
  pkgs = ...;
  config = ...;
  externalInputs = { };
}
```

### mkStandaloneApp (moved to logos-app-builder)

> **Moved:** This function is now in [`logos-app-builder.lib.mkStandaloneApp`](https://github.com/logos-co/logos-app-builder).

```nix
logos-app-builder.lib.mkStandaloneApp {
  pkgs = ...;
  standalone = logos-standalone-app.packages.${system}.default;
  plugin = self.packages.${system}.default;
  metadataFile = ./metadata.json;
  dirName = "logos-my-module-plugin-dir";  # optional
  format = "qt-plugin";                    # or "qml"
  moduleDeps = { };                        # resolved module deps (LGX packages)
}
```

### collectAllModuleDeps (moved to logos-app-builder)

> **Moved:** This function is now in [`logos-app-builder.lib.collectAllModuleDeps`](https://github.com/logos-co/logos-app-builder).

```nix
logos-app-builder.lib.collectAllModuleDeps system flakeInputs depNames
# { waku_module = <lgx derivation>; chat = <lgx derivation>; ... }
```

## version

Library version string.

```nix
logos-module-builder.lib.version
# "0.2.0"
```
