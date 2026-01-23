# Migration Guide

This guide explains how to migrate existing Logos modules to use `logos-module-builder`.

## Overview

Migrating to `logos-module-builder` typically reduces build configuration from ~500+ lines to ~50 lines:

| Before | After |
|--------|-------|
| `flake.nix` (~85 lines) | `flake.nix` (~15 lines) |
| `nix/default.nix` (~45 lines) | `module.yaml` (~30 lines) |
| `nix/lib.nix` (~90 lines) | - |
| `nix/include.nix` (~75 lines) | - |
| `CMakeLists.txt` (~300 lines) | `CMakeLists.txt` (~25 lines) |
| **~595 lines total** | **~70 lines total** |

## Step-by-Step Migration

### Step 1: Create `module.yaml`

Create a new `module.yaml` file by extracting configuration from your existing files:

#### From `metadata.json`:
```yaml
name: your_module        # from "name"
version: 1.0.0           # from "version"
type: core               # from "type"
category: general        # from "category"
```

#### From `flake.nix`:
```yaml
dependencies:            # from flake inputs that are other modules
  - waku_module
  - chat_module
```

#### From `nix/default.nix`:
```yaml
nix_packages:
  build:                 # from buildInputs that aren't Qt
    - protobuf
    - abseil-cpp
  runtime:               # from runtime dependencies
    - zstd
```

#### From `nix/lib.nix` or external library setup:
```yaml
external_libraries:
  - name: libwaku
    vendor_path: "lib"   # or flake_input if using flake
```

#### From `CMakeLists.txt`:
```yaml
cmake:
  find_packages:         # from find_package() calls
    - Protobuf
  extra_sources:         # from PLUGIN_SOURCES
    - src/helper.cpp
  proto_files:           # from proto compilation
    - src/message.proto
```

### Step 2: Simplify `flake.nix`

Replace your entire `flake.nix` with:

```nix
{
  description = "Your Module Description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
    
    # Add module dependencies as inputs
    logos-waku-module.url = "github:logos-co/logos-waku-module";
  };

  outputs = { self, logos-module-builder, nixpkgs, logos-waku-module }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      
      # Pass module dependencies
      moduleInputs = {
        waku_module = logos-waku-module;
      };
    };
}
```

### Step 3: Simplify `CMakeLists.txt`

Replace your entire `CMakeLists.txt` with:

```cmake
cmake_minimum_required(VERSION 3.14)
project(YourModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Define the module
logos_module(
    NAME your_module
    SOURCES 
        src/your_module_interface.h
        src/your_module_plugin.h
        src/your_module_plugin.cpp
    # Add if needed:
    # EXTERNAL_LIBS libfoo
    # FIND_PACKAGES Protobuf
    # PROTO_FILES src/message.proto
)
```

### Step 4: Delete `nix/` Directory

Remove the entire `nix/` directory:
- `nix/default.nix`
- `nix/lib.nix`
- `nix/include.nix`

These are now handled by `logos-module-builder`.

### Step 5: Update `.gitignore`

Add generated files to `.gitignore`:

```gitignore
# Build outputs
build/
result

# Generated code (from nix builds)
generated_code/
```

### Step 6: Test the Migration

```bash
# Build with nix
nix build

# Check outputs
ls -la result/lib/
ls -la result/include/
```

## Migration Examples

### Simple Module (No External Libraries)

**Before** (`logos-chat-module`):
- 5 config files, ~400 lines

**After**:
```yaml
# module.yaml
name: chat
version: 1.0.0
type: core
category: chat
description: "Chat module for Logos"

dependencies:
  - waku_module

nix_packages:
  build:
    - protobuf
    - abseil-cpp
  runtime:
    - zstd
    - krb5

cmake:
  find_packages:
    - Protobuf
    - Threads
  proto_files:
    - src/protobuf/message.proto
```

### Module with External Library

**Before** (`logos-waku-module`):
- 5 config files, ~535 lines
- Complex libwaku handling

**After**:
```yaml
# module.yaml
name: waku_module
version: 1.0.0
type: core
category: network
description: "Waku network protocol module"

dependencies: []

external_libraries:
  - name: waku
    vendor_path: "lib"

cmake:
  extra_include_dirs:
    - lib
```

### Module Building External Library from Source

**Before** (`logos-wallet-module`):
- Complex Go build in nix
- Custom build scripts

**After**:
```yaml
# module.yaml
name: wallet_module
version: 1.0.0
type: core
category: wallet
description: "Wallet module for Logos"

nix_packages:
  build:
    - gnumake
    - go

external_libraries:
  - name: gowalletsdk
    flake_input: "github:status-im/go-wallet-sdk/commit"
    build_command: "make shared-library"
    go_build: true

cmake:
  extra_include_dirs:
    - lib
```

## Troubleshooting

### Build fails with "LogosModule.cmake not found"

Ensure `LOGOS_MODULE_BUILDER_ROOT` is set in the nix build environment. The `mkLogosModule` function sets this automatically.

### External library not found

Check that:
1. The library is correctly specified in `external_libraries`
2. For flake inputs, the URL is correct
3. For vendor paths, the directory exists
4. The `build_command` produces output matching `output_pattern`

### Generated headers missing

Ensure:
1. `logos-cpp-sdk` is correctly referenced
2. `metadata.json` exists in the source directory
3. The module name matches between `module.yaml` and `metadata.json`

### Module dependencies not resolved

Module dependencies must be:
1. Listed in `dependencies` in `module.yaml`
2. Added as flake inputs in `flake.nix`
3. Passed via `moduleInputs` to `mkLogosModule`

## Getting Help

- Check the [examples](../examples/) directory for working examples
- Review the [configuration reference](./configuration.md)
- Open an issue on GitHub
