# External Libraries Guide

How to wrap external C/C++ libraries in Logos modules.

## Overview

Logos modules can wrap external C/C++ libraries to expose their functionality to the Logos ecosystem. There are two approaches:

1. **Vendor/Pre-built** — Library already compiled, in the `lib/` directory (simplest)
2. **Flake Input** — Library source as a flake input, built during nix build

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
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";

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

## Approach 3: Vendor Submodule (Build from Source in Repo)

Best for: Libraries requiring custom build scripts, where source lives in a git submodule.

### Setup

1. Add library as git submodule:
```bash
git submodule add https://github.com/org/my-lib vendor/my-lib
```

2. Create build script:
```bash
# scripts/build-mylib.sh
#!/bin/bash
cd vendor/my-lib
make clean
make shared
cp build/libmylib.* ../../lib/
```

### Custom Build Scripts

Build scripts receive no arguments and should:
1. Build the library
2. Copy outputs to `lib/` directory

Example for nwaku/libwaku:
```bash
#!/bin/bash
set -e

cd vendor/nwaku

# Build libwaku
make libwaku

# Copy to lib/
mkdir -p ../../lib
cp build/libwaku.* ../../lib/
cp library/libwaku.h ../../lib/
```

3. Configure `metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "mylib",
        "vendor_path": "vendor/my-lib",
        "build_script": "scripts/build-mylib.sh"
      }
    ]
  }
}
```

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
