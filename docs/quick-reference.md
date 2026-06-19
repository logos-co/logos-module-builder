# Quick Reference

Cheat sheet for common logos-module-builder tasks.

## Create a New Module

```bash
# 1. Create directory
mkdir logos-my-module && cd logos-my-module

# 2. Create metadata.json
cat > metadata.json << 'EOF'
{
  "name": "my_module",
  "display_name": "My Module",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
  "category": "general",
  "description": "My module",
  "main": "my_module_plugin",
  "dependencies": [],
  "nix": {
    "packages": { "build": [], "runtime": [] },
    "external_libraries": [],
    "cmake": { "find_packages": [], "extra_sources": [] }
  }
}
EOF

# 3. Create flake.nix
cat > flake.nix << 'EOF'
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
EOF

# 4. Create CMakeLists.txt
cat > CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
logos_module(NAME my_module SOURCES src/my_module_impl.h src/my_module_impl.cpp)
EOF

# 5. Create source files in src/ directory (universal model: impl class only)
mkdir -p src
# (see templates for source file content)

# 6. Track files and build
git init && git add -A
nix build
```

## metadata.json Quick Reference

```json
{
  "name": "module_name",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
  "category": "general",
  "description": "A Logos module",
  "main": "module_name_plugin",
  "dependencies": ["waku_module", "other_module"],

  "nix": {
    "packages": {
      "build": ["protobuf", "abseil-cpp"],
      "runtime": ["zstd"]
    },
    "external_libraries": [
      { "name": "mylib", "vendor_path": "lib" }
    ],
    "cmake": {
      "find_packages": ["Protobuf", "Threads"],
      "extra_sources": ["src/helper.cpp"],
      "extra_include_dirs": ["include"],
      "extra_link_libraries": ["pthread"]
    }
  }
}
```

## CMakeLists.txt Quick Reference

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)

include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

logos_module(
    NAME my_module
    SOURCES
        src/my_module_impl.h
        src/my_module_impl.cpp
        src/helper.cpp
    EXTERNAL_LIBS
        mylib
    FIND_PACKAGES
        Protobuf
    PROTO_FILES
        src/message.proto
    LINK_LIBRARIES
        pthread
)
```

## flake.nix Quick Reference

### Basic Module
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

### With Module Dependencies
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
      flakeInputs = inputs;  # waku_module resolved automatically from dependencies[]
    };
}
```

### With External Library (flake input, built from source)
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    mylib = { url = "github:org/mylib"; flake = false; };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        mylib = inputs.mylib;
      };
    };
}
```

### ui_qml Module (QML view + optional C++ backend)
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add backend module dependencies as inputs if needed
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

## Source File Templates (universal model)

You write only the impl class. The `*_interface.h` and `*_plugin.{h,cpp}` glue
(`Q_PLUGIN_METADATA`, `initLogos`) is generated from `src/my_module_impl.h`.
Module code is Qt-free — use `std::string`.

### Impl Header (`src/my_module_impl.h`)
```cpp
#pragma once

#include <string>
#include "logos_module_context.h"

class MyModuleImpl : public LogosModuleContext
{
public:
    /// Returns a processed string. Public methods are the module API.
    std::string myMethod(const std::string& input);

logos_events:
    /// Typed event; subscribers use `modules().my_module.onProcessed(...)`.
    void processed(const std::string& result);
};
```

### Impl Implementation (`src/my_module_impl.cpp`)
```cpp
#include "my_module_impl.h"

std::string MyModuleImpl::myMethod(const std::string& input) {
    std::string result = "Result: " + input;
    processed(result);   // generated event body fans out to subscribers
    return result;
}
```

`LogosModuleContext` gives you `modules().<dep>.method(...)` for typed calls into
dependencies, typed event subscriptions, and an `onContextReady()` hook (override
it to arm subscriptions once the module is wired).

### UI C++ backend (universal `ui_qml`)

For a C++ UI module (`"type": "ui_qml"` + `"interface": "universal"`) you write a
`.rep` view contract plus a `*Backend` class deriving the generated
`<RepClass>SimpleSource` and `LogosUiPluginContext`. Point `codegen.rep` at the
`.rep` and use `REP_FILE` in `CMakeLists.txt`:

```cpp
// src/my_ui.rep — the QtRO view contract
class MyUi {
    SLOT(int add(int a, int b))
    PROP(QString status="Ready" READONLY)
}
```

```cpp
// src/my_ui_backend.h
#pragma once
#include "rep_my_ui_source.h"
#include "logos_ui_plugin_context.h"

class MyUiBackend : public MyUiSimpleSource, public LogosUiPluginContext {
public:
    int add(int a, int b) override;   // feed PROPs via setStatus(...)
};
```

```cmake
logos_module(
    NAME my_ui
    REP_FILE src/my_ui.rep
    SOURCES
        src/my_ui_backend.h
        src/my_ui_backend.cpp
    INCLUDE_DIRS
        src
)
```

## Common Commands

```bash
# Build module (combined lib + include)
nix build

# Build just the library
nix build .#lib

# Build just the generated headers
nix build .#include

# Build .lgx packages
nix build .#lgx
nix build .#lgx-portable

# Run UI module in logos-standalone-app
nix run .

# Enter dev shell
nix develop

# Build specific output (alternative syntax)
nix build .#my_module-lib
nix build .#my_module-include

# Check flake
nix flake check

# Update flake inputs
nix flake update
```
