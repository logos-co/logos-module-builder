# Logos Module Builder Documentation

Welcome to the Logos Module Builder documentation. This library dramatically simplifies creating and maintaining Logos modules by reducing boilerplate from ~600 lines to ~70 lines.

## Documentation Index

### Getting Started
- [Getting Started Guide](./getting-started.md) - Create your first module in 10 minutes
- [Quick Reference](./quick-reference.md) - Cheat sheet for common tasks

### Reference
- [Configuration Reference](./configuration.md) - Complete `metadata.json` specification
- [CMake Reference](./cmake-reference.md) - LogosModule.cmake functions and options
- [Nix API Reference](./nix-api.md) - mkLogosModule and other Nix functions

### Guides
- [Migration Guide](./migration.md) - Migrate existing modules to use the builder
- [External Libraries Guide](./external-libraries.md) - Wrap C/C++ libraries in modules
- [Troubleshooting](./troubleshooting.md) - Common issues and solutions

## Overview

### What is Logos Module Builder?

Logos Module Builder is a shared Nix flake library that provides:

1. **`mkLogosModule`** - A Nix function that builds complete C++ Qt plugin modules
2. **`mkLogosQmlModule`** - A Nix function that stages pure QML UI modules
3. **`LogosModule.cmake`** - A CMake module that handles all build boilerplate
4. **`metadata.json`** - A single configuration file per module, read by both Qt and Nix

### Why Use It?

| Without Builder | With Builder |
|-----------------|--------------|
| 5 config files | 2 config files |
| ~600 lines of build config | ~70 lines of build config |
| Copy-paste boilerplate | Declarative configuration |
| Manual dependency handling | Automatic dependency resolution |
| Complex CMake | Simple CMake |

### Quick Example

**Before** (traditional approach):
```
my-module/
├── flake.nix           # 85 lines
├── CMakeLists.txt      # 300 lines
├── nix/
│   ├── default.nix     # 45 lines
│   ├── lib.nix         # 90 lines
│   └── include.nix     # 75 lines
└── src/...
```

**After** (with logos-module-builder):
```
my-module/
├── flake.nix           # 10 lines
├── metadata.json       # 30 lines
├── CMakeLists.txt      # 25 lines
└── src/...
```

## Installation

Add `logos-module-builder` as a flake input:

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

## Support

- [GitHub Issues](https://github.com/logos-co/logos-module-builder/issues)
- [Logos Discord](https://discord.gg/logos)
