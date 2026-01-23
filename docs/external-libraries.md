# External Libraries Guide

How to wrap external C/C++ libraries in Logos modules.

## Overview

Logos modules can wrap external C/C++ libraries to expose their functionality to the Logos ecosystem. There are three approaches:

1. **Flake Input** - Library source as a flake input, built during nix build
2. **Vendor Submodule** - Library in vendor/ directory, built via script
3. **Pre-built** - Library already compiled in lib/ directory

## Approach 1: Flake Input

Best for: Libraries with clean build systems (make, cmake, etc.)

### Configuration

**flake.nix:**
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    
    # Add the library as a non-flake input
    my-lib-src = {
      url = "github:org/my-lib/v1.0.0";
      flake = false;
    };
  };

  outputs = { self, logos-module-builder, my-lib-src, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      externalLibInputs = {
        mylib = my-lib-src;
      };
    };
}
```

**module.yaml:**
```yaml
external_libraries:
  - name: mylib
    flake_input: "github:org/my-lib"  # For documentation
    build_command: "make shared"       # Build command
    output_pattern: "build/libmylib.*" # Where to find output
```

### Build Command Options

```yaml
# Simple make
build_command: "make"

# Make with target
build_command: "make shared-library"

# CMake
build_command: "mkdir build && cd build && cmake .. && make"

# Custom script in the library
build_command: "./build.sh"
```

### Go Libraries

For Go libraries that produce C shared libraries:

```yaml
external_libraries:
  - name: gowalletsdk
    flake_input: "github:status-im/go-wallet-sdk"
    build_command: "make shared-library"
    go_build: true  # Enable Go build environment
```

The `go_build: true` flag sets up:
- `GOCACHE` and `GOPATH` directories
- `CGO_ENABLED=1`
- Go toolchain in build environment

## Approach 2: Vendor Submodule

Best for: Libraries requiring custom build scripts or complex setup.

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

3. Configure module.yaml:
```yaml
external_libraries:
  - name: mylib
    vendor_path: "vendor/my-lib"
    build_script: "scripts/build-mylib.sh"
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

## Approach 3: Pre-built Library

Best for: Proprietary libraries or libraries with complex build requirements.

### Setup

1. Place pre-built library in `lib/`:
```
my-module/
├── lib/
│   ├── libmylib.so      # or .dylib
│   └── libmylib.h       # header file
└── ...
```

2. Configure module.yaml:
```yaml
external_libraries:
  - name: mylib
    vendor_path: "lib"  # Just reference the lib directory
```

## CMake Integration

### Basic Linking

In CMakeLists.txt:
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

# Find additional library
find_library(EXTRA_LIB extralib PATHS ${CMAKE_CURRENT_SOURCE_DIR}/lib)

# Link it
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
    // Call C library functions
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

## Complete Example: Wallet Module

Here's how the wallet module wraps go-wallet-sdk:

**flake.nix:**
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    go-wallet-sdk = {
      url = "github:status-im/go-wallet-sdk/v1.0.0";
      flake = false;
    };
  };

  outputs = { self, logos-module-builder, go-wallet-sdk, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      externalLibInputs = {
        gowalletsdk = go-wallet-sdk;
      };
    };
}
```

**module.yaml:**
```yaml
name: wallet_module
external_libraries:
  - name: gowalletsdk
    flake_input: "github:status-im/go-wallet-sdk"
    build_command: "make shared-library"
    go_build: true
```

**wallet_module_plugin.cpp:**
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
