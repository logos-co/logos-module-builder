# Logos Module Builder

A shared Nix flake library that provides reusable functions for building Logos modules with minimal boilerplate.

## Overview

Instead of duplicating ~600 lines of build configuration across every module, this library allows you to define a module with just a `module.yaml` configuration file and your source code.

| Without Builder | With Builder | Reduction |
|-----------------|--------------|-----------|
| ~600 lines config | ~70 lines config | **88%** |
| 5 config files | 2 config files | **60%** |

## Quick Start

### 1. Create your module directory

```
my-module/
├── module.yaml           # Module configuration (~30 lines)
├── flake.nix            # Minimal flake (~15 lines)
├── CMakeLists.txt       # CMake config (~25 lines)
├── metadata.json        # Runtime metadata
└── src/                 # Source files
    ├── my_module_interface.h
    ├── my_module_plugin.h
    └── my_module_plugin.cpp
```

### 2. Define your module in `module.yaml`

```yaml
name: my_module
version: 1.0.0
type: core
category: general
description: "My custom Logos module"

# Logos module dependencies
dependencies:
  - waku_module

# Additional nix packages needed
nix_packages:
  build:
    - protobuf
  runtime:
    - zstd
```

### 3. Create a minimal `flake.nix`

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

### 4. Build your module

```bash
nix build          # Build everything
nix build .#lib    # Build just the library
```

## Features

- **~90% reduction in boilerplate** per module
- **Single source of truth** for build logic
- **Automatic CMake configuration** via `LogosModule.cmake`
- **External library support** (flake inputs or vendor submodules)
- **Cross-platform** (macOS, Linux)
- **Declarative configuration** via `module.yaml`

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Create your first module |
| [Quick Reference](docs/quick-reference.md) | Cheat sheet for common tasks |
| [Configuration Reference](docs/configuration.md) | Complete `module.yaml` specification |
| [CMake Reference](docs/cmake-reference.md) | `LogosModule.cmake` functions |
| [Nix API Reference](docs/nix-api.md) | `mkLogosModule` and other functions |
| [External Libraries Guide](docs/external-libraries.md) | Wrap C/C++ libraries |
| [Migration Guide](docs/migration.md) | Migrate existing modules |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |

## Examples

| Example | Description |
|---------|-------------|
| [minimal-module](examples/minimal-module) | Basic module with no external dependencies |
| [waku-module-migrated](examples/waku-module-migrated) | Example migration showing 91% config reduction |

## Templates

Use `nix flake init` with our templates:

```bash
# Minimal module
nix flake init -t github:logos-co/logos-module-builder

# Module with external library
nix flake init -t github:logos-co/logos-module-builder#with-external-lib
```

## AI Assistant Skills

For AI assistants (Claude, Cursor, etc.), we provide skill files:

| Skill | Description |
|-------|-------------|
| [create-logos-module](skills/create-logos-module.md) | Step-by-step guide to create a new module |
| [update-logos-module](skills/update-logos-module.md) | Guide to update/modify existing modules |

## Architecture

```
logos-module-builder/
├── lib/                    # Nix library functions
│   ├── mkLogosModule.nix   # Main builder function
│   ├── mkModuleLib.nix     # Library builder
│   ├── mkModuleInclude.nix # Header generator
│   └── mkExternalLib.nix   # External library handler
├── cmake/
│   └── LogosModule.cmake   # Reusable CMake module
├── templates/              # Module templates
├── examples/               # Working examples
├── docs/                   # Documentation
└── skills/                 # AI assistant skills
```

## License

MIT
