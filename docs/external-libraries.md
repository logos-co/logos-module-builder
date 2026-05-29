# External Libraries Guide

How to wrap external C/C++ libraries in Logos modules.

## Overview

Logos modules can wrap external C/C++ libraries to expose their functionality to the Logos ecosystem. There are four well-formed approaches, distinguished by where the library's source/binary lives and who compiles it:

1. **Vendor/Pre-built** — A `lib<name>.{so,dylib}` committed to `vendor_path` (simplest, no build step at module-build time)
2. **Flake Input (build from source)** — Library source as a `flake = false` input, built by `mkExternalLib` using the entry's `build_command`
3. **Flake Input (Nix package)** — Library provided by another flake that already has its own `packages.<system>.default` output
4. **Vendor compiled from source** — Source files committed to `vendor_path` (or a git submodule mounted there), the module builder compiles them via a `build_command`/`build_script` declared in `metadata.json` — no manual `gcc` or copy-to-lib step

All four resolve through the same `mkExternalLib.buildExternalLibs` pipeline into `{ <name> = derivation-or-null }`, after which the buildPlugin staging copies the result into the plugin's `lib/`. See [configuration.md → nix.external_libraries](configuration.md#nixexternal_libraries) for the canonical field reference and a side-by-side decision matrix.

## Approach 1: Vendor / Pre-built Library

Best for: Pre-built proprietary libraries or binaries you already have compiled.

### Setup

1. Place the pre-built library in `lib/` and **git-track it** (Nix only sees tracked files):
```bash
cp /path/to/libmylib.dylib lib/
git add lib/libmylib.dylib lib/libmylib.h
```

2. Configure `metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      { "name": "mylib", "vendor_path": "lib" }
    ],
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

3. `flake.nix` stays simple — no extra inputs needed:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

## Approach 2: Flake Input (Build from Source)

Best for: Libraries with clean build systems (make, cmake, etc.) whose source you want pinned as a flake input.

### Configuration

`flake.nix`:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";

    my-lib-src = {
      url = "github:org/my-lib/v1.0.0";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        mylib = inputs.my-lib-src;
      };
    };
}
```

`metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "mylib",
        "build_command": "make shared",
        "output_pattern": "build/libmylib.*"
      }
    ],
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

### Build Command Options

```json
{ "build_command": "make" }
{ "build_command": "make shared-library" }
{ "build_command": "mkdir build && cd build && cmake .. && make" }
{ "build_command": "./build.sh" }
```

### Go Libraries

For Go libraries that produce C shared libraries:

```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "gowalletsdk",
        "build_command": "make shared-library",
        "go_build": true
      }
    ]
  }
}
```

The `go_build: true` flag sets up `GOCACHE`, `GOPATH`, `CGO_ENABLED=1`, and the Go toolchain in the build environment.

## Approach 3: Flake Input (Nix Package)

Best for: Libraries that already have their own `flake.nix` producing a Nix derivation with `lib/` and `include/` outputs. The module builder detects this automatically — if the resolved input is a Nix derivation, it's used directly; no extra flags needed in `metadata.json`.

### How detection works

The module builder calls `lib.isDerivation` on the resolved input:
- **Derivation** (a specific package output) → used directly, no build step
- **Raw source** (non-flake input, `flake = false`) → built with `make` / custom command (Approach 2)

When you point `externalLibInputs` at a specific package output (or use the structured format with `packages`), the resolved value is always a derivation, so it's used as-is.

### Configuration

`flake.nix`:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    my-lib.url = "github:org/my-lib";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        mylib = inputs.my-lib;
      };
    };
}
```

`metadata.json` — only the name is needed:
```json
{
  "nix": {
    "external_libraries": [
      { "name": "mylib" }
    ],
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

If `my-lib` has `packages.${system}.default`, the module builder resolves to that derivation and uses it directly. If it's a non-flake source repo, it falls back to building with `make`.

### Per-variant packages

If the flake input provides multiple package outputs (e.g. a dev build and a portable build), use the structured `externalLibInputs` format:

```nix
externalLibInputs = {
  mylib = {
    input = inputs.my-lib;
    packages = {
      default = "lib";           # used for nix build .#lib
      portable = "lib-portable"; # used for nix build .#lib-portable
    };
  };
};
```

## Approach 4: Vendor Compiled from Source

Best for: Libraries whose source files live in the module repo (committed directly or mounted via a git submodule), where you don't want to commit a binary. The builder compiles them as their own nix derivation rooted at `${moduleSrc}/${vendor_path}` and stages the result into `lib/`. Same pipeline as Approach 2, but the source comes from inside the module repo instead of a flake input.

### Setup — source files committed directly

1. Commit your library's source to `lib/` (or another `vendor_path` directory) — just the source, no binary:
```bash
ls lib/
# libmylib.c  libmylib.h
git add lib/libmylib.c lib/libmylib.h
```

2. Configure `metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "mylib",
        "vendor_path": "lib",
        "build_command": "$CC -shared -fPIC -O2 -o $LIB_BASENAME libmylib.c"
      }
    ],
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

The `build_command` runs from `vendor_path` with `LIB_NAME`/`LIB_EXT`/`LIB_BASENAME` exported (see [configuration.md → Shape B](configuration.md#shape-b--vendor-compiled-from-source) for the env-var reference). The staged dylib gets `install_name @rpath/lib<name>.dylib` applied automatically on Darwin.

3. `flake.nix` stays simple — no flake input needed for the library itself:
```nix
{
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

### Setup — source mounted as a git submodule

If the library's source is upstream-maintained and you'd rather track it as a git submodule:

```bash
git submodule add https://github.com/org/my-lib vendor/my-lib
```

`metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "mylib",
        "vendor_path": "vendor/my-lib",
        "build_command": "make shared"
      }
    ]
  }
}
```

For more elaborate builds, use `build_script` and point at a shell script tracked in your repo (path resolved relative to `vendor_path` or the project root):

```json
{
  "name": "mylib",
  "vendor_path": "vendor/my-lib",
  "build_script": "scripts/build-mylib.sh"
}
```

The script runs with the same env-var contract; it does **not** need to copy outputs to `lib/` — `mkExternalLib` discovers `lib<name>.{so,dylib,a}` in the build's working directory automatically (override discovery with `output_pattern` if your build writes elsewhere).

## CMake Integration

### Basic Linking

In `CMakeLists.txt`:
```cmake
logos_module(
    NAME my_module
    SOURCES ...
    EXTERNAL_LIBS
        mylib
)
```

This will:
1. Search for library in `lib/`
2. Add `lib/` to include directories
3. Link the library
4. Copy library to output directory

### Manual Linking

For more control:
```cmake
# After logos_module()
find_library(EXTRA_LIB extralib PATHS ${CMAKE_CURRENT_SOURCE_DIR}/lib)
target_link_libraries(my_module_module_plugin PRIVATE ${EXTRA_LIB})
```

## Plugin Implementation

### Including Headers

```cpp
// In my_module_plugin.h
#include "lib/libmylib.h"  // Include the C header
```

### Using the Library

```cpp
// In my_module_plugin.cpp
#include "my_module_plugin.h"
#include "lib/libmylib.h"

void MyModulePlugin::init() {
    mylib_handle* handle = mylib_init();
    if (!handle) {
        qWarning() << "Failed to initialize mylib";
        return;
    }
    m_handle = handle;
}

void MyModulePlugin::cleanup() {
    if (m_handle) {
        mylib_cleanup(m_handle);
        m_handle = nullptr;
    }
}
```

### Memory Management

C libraries often return allocated memory. Always free it:

```cpp
QString MyModulePlugin::getData() {
    char* result = mylib_get_data(m_handle);
    QString output = QString::fromUtf8(result);
    mylib_free_string(result);  // Don't forget!
    return output;
}
```

### Callbacks

For C callbacks, use static methods:

```cpp
// Header
class MyModulePlugin {
private:
    static void callback(int code, const char* msg, void* user_data);
};

// Implementation
void MyModulePlugin::callback(int code, const char* msg, void* user_data) {
    auto* plugin = static_cast<MyModulePlugin*>(user_data);
    emit plugin->eventResponse("callback", QVariantList() << code << QString::fromUtf8(msg));
}

void MyModulePlugin::subscribe() {
    mylib_subscribe(m_handle, callback, this);  // Pass 'this' as user_data
}
```

## Platform Considerations

### macOS

Libraries need correct install names. The builder automatically runs:
```bash
install_name_tool -id "@rpath/libmylib.dylib" libmylib.dylib
```

For the plugin:
```bash
install_name_tool -change "/old/path/libmylib.dylib" "@rpath/libmylib.dylib" my_module_plugin.dylib
```

### Linux

Libraries are found via `$ORIGIN` RPATH:
```bash
patchelf --set-rpath '$ORIGIN' my_module_plugin.so
```

### Troubleshooting

**Library not found at runtime:**
```bash
# Check RPATH on macOS
otool -L my_module_plugin.dylib

# Check RPATH on Linux
readelf -d my_module_plugin.so | grep RPATH
ldd my_module_plugin.so
```

**Symbol not found:**
```bash
# List symbols in library
nm -gU libmylib.dylib

# Check if symbol is referenced
nm -u my_module_plugin.dylib | grep mylib
```

**Library not copied to result/lib:**

For vendor libraries: ensure the `.dylib`/`.so` is git-tracked:
```bash
git add lib/libmylib.dylib
```

## Complete Example: Wallet Module

Here's how the wallet module wraps go-wallet-sdk:

`flake.nix`:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    go-wallet-sdk = {
      url = "github:status-im/go-wallet-sdk/v1.0.0";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        gowalletsdk = inputs.go-wallet-sdk;
      };
    };
}
```

`metadata.json`:
```json
{
  "name": "wallet_module",
  "version": "1.0.0",
  "type": "core",
  "category": "wallet",
  "main": "wallet_module_plugin",
  "dependencies": [],
  "nix": {
    "packages": { "build": ["gnumake", "go"], "runtime": [] },
    "external_libraries": [
      {
        "name": "gowalletsdk",
        "build_command": "make shared-library",
        "go_build": true
      }
    ],
    "cmake": { "extra_include_dirs": ["lib"] }
  }
}
```

`wallet_module_plugin.cpp`:
```cpp
#include "lib/libgowalletsdk.h"

bool WalletModulePlugin::initWallet(const QString& rpcUrl) {
    char* err = nullptr;
    m_handle = GoWSK_ethclient_NewClient(rpcUrl.toUtf8().constData(), &err);
    if (err) {
        QString error = QString::fromUtf8(err);
        GoWSK_FreeCString(err);
        qWarning() << "Wallet init failed:" << error;
        return false;
    }
    return true;
}
```
