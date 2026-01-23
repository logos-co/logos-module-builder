# Logos Module Builder Skills

These skills help you create and maintain Logos modules using the logos-module-builder framework.

## Available Skills

### 1. Create Logos Module
**File:** [create-logos-module.md](./create-logos-module.md)

Use when the user wants to:
- Create a new Logos module from scratch
- Build a plugin for the Logos platform
- Wrap a C/C++ library as a Logos module

**Trigger phrases:**
- "create a new Logos module"
- "make a module for Logos"
- "build a Logos plugin"
- "wrap this library for Logos"

### 2. Update Logos Module
**File:** [update-logos-module.md](./update-logos-module.md)

Use when the user wants to:
- Add methods to an existing module
- Add dependencies to a module
- Add external library support
- Migrate a legacy module to logos-module-builder
- Update module configuration

**Trigger phrases:**
- "add a method to the module"
- "add a dependency"
- "wrap a new library"
- "migrate this module"
- "update the module"

## Quick Reference

### Module Structure
```
logos-{name}-module/
├── flake.nix              # Nix configuration (15 lines)
├── module.yaml            # Module config (30 lines)
├── metadata.json          # Runtime metadata
├── CMakeLists.txt         # Build config (25 lines)
├── {name}_interface.h     # Public API
├── {name}_plugin.h        # Plugin header
└── {name}_plugin.cpp      # Implementation
```

### Minimal flake.nix
```nix
{
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";
  outputs = { self, logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
    };
}
```

### Minimal module.yaml
```yaml
name: my_module
version: 1.0.0
type: core
category: general
description: "My module"
dependencies: []
nix_packages:
  build: []
  runtime: []
external_libraries: []
cmake:
  find_packages: []
  extra_sources: []
  proto_files: []
```

### Minimal CMakeLists.txt
```cmake
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
logos_module(NAME my_module SOURCES my_module_interface.h my_module_plugin.h my_module_plugin.cpp)
```

## Documentation Links

- [Getting Started](https://github.com/logos-co/logos-module-builder/blob/main/docs/getting-started.md)
- [Configuration Reference](https://github.com/logos-co/logos-module-builder/blob/main/docs/configuration.md)
- [Migration Guide](https://github.com/logos-co/logos-module-builder/blob/main/docs/migration.md)
- [CMake Reference](https://github.com/logos-co/logos-module-builder/blob/main/docs/cmake-reference.md)
- [Troubleshooting](https://github.com/logos-co/logos-module-builder/blob/main/docs/troubleshooting.md)

## Repository

https://github.com/logos-co/logos-module-builder
