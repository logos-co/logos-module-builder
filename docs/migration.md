# Migration Guide

This guide explains how to migrate existing Logos modules to use `logos-module-builder`.

## Overview

Migrating to `logos-module-builder` typically reduces build configuration from ~500+ lines to ~50 lines:

| Before | After |
|--------|-------|
| `flake.nix` (~85 lines) | `flake.nix` (~10 lines) |
| `nix/default.nix` (~45 lines) | `metadata.json` (~30 lines) |
| `nix/lib.nix` (~90 lines) | - |
| `nix/include.nix` (~75 lines) | - |
| `CMakeLists.txt` (~300 lines) | `CMakeLists.txt` (~25 lines) |
| **~595 lines total** | **~65 lines total** |

## Step-by-Step Migration

### Step 1: Create `metadata.json`

Create a unified `metadata.json` by merging your existing configuration. The top-level fields are embedded into the Qt plugin at compile time via `Q_PLUGIN_METADATA`, and the `"nix"` block is used by the build system.

#### From existing `metadata.json` or Qt plugin config:
```json
{
  "name": "your_module",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "main": "your_module_plugin",
  "dependencies": ["waku_module", "chat_module"]
}
```

#### Add `"nix"` block from `nix/default.nix` and `flake.nix`:
```json
{
  "name": "your_module",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "main": "your_module_plugin",
  "dependencies": ["waku_module", "chat_module"],

  "nix": {
    "packages": {
      "build": ["protobuf", "abseil-cpp"],
      "runtime": ["zstd"]
    },
    "external_libraries": [
      { "name": "libwaku", "vendor_path": "lib" }
    ],
    "cmake": {
      "find_packages": ["Protobuf"],
      "extra_sources": ["src/helper.cpp"],
      "extra_include_dirs": ["lib"]
    }
  }
}
```

### Step 2: Simplify `flake.nix`

Replace your entire `flake.nix` with:

```nix
{
  description = "Your Module Description";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";

    # Input name must match the dependency name in metadata.json
    waku_module.url = "github:logos-co/logos-waku-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;  # dependencies[] auto-resolved from flakeInputs
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

### Step 5: Delete old `module.yaml` (if present)

If you had a `module.yaml`, its contents have now been merged into `metadata.json`. Delete it.

### Step 6: Update `.gitignore`

Add generated files to `.gitignore`:

```gitignore
# Build outputs
build/
result

# Generated code (from nix builds)
generated_code/
```

**Important:** Pre-built vendor libraries (e.g. `lib/libwaku.dylib`) must be git-tracked. Nix only sees tracked files.

### Step 7: Test the Migration

```bash
# Track new files with git first
git add metadata.json flake.nix CMakeLists.txt src/

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

**After** (`metadata.json`):
```json
{
  "name": "chat",
  "version": "1.0.0",
  "type": "core",
  "category": "chat",
  "description": "Chat module for Logos",
  "main": "chat_plugin",
  "dependencies": ["waku_module"],

  "nix": {
    "packages": {
      "build": ["protobuf", "abseil-cpp"],
      "runtime": ["zstd", "krb5"]
    },
    "external_libraries": [],
    "cmake": {
      "find_packages": ["Protobuf", "Threads"],
      "extra_sources": []
    }
  }
}
```

### Module with External Library

**Before** (`logos-waku-module`):
- 5 config files, ~535 lines
- Complex libwaku handling

**After** (`metadata.json`):
```json
{
  "name": "waku_module",
  "version": "1.0.0",
  "type": "core",
  "category": "network",
  "description": "Waku network protocol module",
  "main": "waku_module_plugin",
  "dependencies": [],

  "nix": {
    "packages": { "build": [], "runtime": [] },
    "external_libraries": [
      { "name": "waku", "vendor_path": "lib" }
    ],
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

### Module Building External Library from Source

**Before** (`logos-wallet-module`):
- Complex Go build in nix
- Custom build scripts

**After** (`metadata.json` + `flake.nix`):

`metadata.json`:
```json
{
  "name": "wallet_module",
  "version": "1.0.0",
  "type": "core",
  "category": "wallet",
  "description": "Wallet module for Logos",
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

`flake.nix`:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    go-wallet-sdk = { url = "github:status-im/go-wallet-sdk/commit"; flake = false; };
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

## Troubleshooting

### Build fails with "LogosModule.cmake not found"

Ensure `LOGOS_MODULE_BUILDER_ROOT` is set in the nix build environment. The `mkLogosModule` function sets this automatically.

### External library not found

Check that:
1. The library is correctly specified in `nix.external_libraries`
2. For flake inputs, the key in `externalLibInputs` matches `name` in metadata
3. For vendor paths, the directory and library files exist and are git-tracked
4. The binary is git-tracked (`git add lib/libwaku.dylib`)

### Generated headers missing

Ensure:
1. `logos-cpp-sdk` is correctly referenced
2. `metadata.json` exists in the source directory and is git-tracked

### Module dependencies not resolved

Module dependencies are resolved automatically from `flakeInputs`. Ensure:
1. Listed in `dependencies` in `metadata.json`
2. Added as flake inputs in `flake.nix` with matching names
3. `flakeInputs = inputs` is passed to `mkLogosModule`

## Getting Help

- Check the [examples](../examples/) directory for working examples
- Review the [configuration reference](./configuration.md)
- Open an issue on GitHub
