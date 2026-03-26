# Experimental - do not use

# Logos Module Builder

A shared Nix flake library that provides reusable functions for building Logos modules with minimal boilerplate.

## Overview

Instead of duplicating ~600 lines of build configuration across every module, this library lets you define a module with a single `metadata.json` file and your source code.

| Without Builder | With Builder | Reduction |
|-----------------|--------------|-----------|
| ~600 lines config | ~70 lines config | **88%** |
| 5 config files | 2 config files | **60%** |

## Quick Start

### 1. Create your module directory

```
my-module/
├── metadata.json        # Single config file (~30 lines)
├── flake.nix            # Minimal flake (~10 lines)
├── CMakeLists.txt       # CMake config (~25 lines)
└── src/                 # Source files
    ├── my_module_interface.h
    ├── my_module_plugin.h
    └── my_module_plugin.cpp
```

### 2. Define your module in `metadata.json`

```json
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "description": "My custom Logos module",
  "main": "my_module_plugin",
  "dependencies": ["waku_module"],

  "nix": {
    "packages": {
      "build": ["protobuf"],
      "runtime": ["zstd"]
    },
    "external_libraries": [],
    "cmake": { "find_packages": [], "extra_sources": [] }
  }
}
```

### 3. Create a minimal `flake.nix`

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

### 4. Build your module

```bash
git init && git add -A   # Nix needs files tracked by git
nix build                # Build everything
nix build .#lib          # Build just the library
nix build .#lgx          # Build .lgx package (requires nix-bundle-lgx input)
nix build .#lgx-portable # Build portable .lgx package
```

### UI modules: `nix run` with logos-standalone-app

For **`type: ui`** (C++ Qt widget) and **`type: ui_qml`** (QML) modules, pass `logosStandalone` to register `apps.default`:

**C++ Qt widget** (`mkLogosModule`):
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
```

**QML-only** (`mkLogosQmlModule` — no C++ compilation):
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
```

Then `nix run .` launches the module in `logos-standalone-app`.

See `templates/ui-module`, `templates/ui-qml-module`, and `lib/mkLogosQmlModule.nix`.

## Features

- **~90% reduction in boilerplate** per module
- **Single source of truth** via `metadata.json` — used by Nix build and embedded into Qt plugins at compile time
- **Automatic CMake configuration** via `LogosModule.cmake`
- **External library support** (vendor pre-built or flake-input source)
- **Cross-platform** (macOS, Linux)
- **Auto-resolved module dependencies** from `flakeInputs`
- **Built-in LGX packaging** — `nix build .#lgx` and `nix build .#lgx-portable` when `nix-bundle-lgx` is in `flakeInputs`

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Create your first module |
| [Quick Reference](docs/quick-reference.md) | Cheat sheet for common tasks |
| [Configuration Reference](docs/configuration.md) | Complete `metadata.json` specification |
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
# Minimal core module
nix flake init -t github:logos-co/logos-module-builder

# C++ UI module (with nix run)
nix flake init -t github:logos-co/logos-module-builder#ui-module

# QML UI module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-module

# Module with external library
nix flake init -t github:logos-co/logos-module-builder#with-external-lib
```

## AI Assistant Skills

For AI assistants (Claude, Cursor, etc.), we provide skill files:

| Skill | Description |
|-------|-------------|
| [create-logos-module](skills/create-logos-module.md) | Step-by-step guide to create a new module |
| [create-ui-module](skills/create-ui-module.md) | Create a C++ Qt widget UI module |
| [create-qml-module](skills/create-qml-module.md) | Create a pure QML UI module |
| [update-logos-module](skills/update-logos-module.md) | Guide to update/modify existing modules |

## Architecture

```
logos-module-builder/
├── lib/                    # Nix library functions
│   ├── mkLogosModule.nix   # Main builder for C++ Qt plugin modules
│   ├── mkLogosQmlModule.nix # Builder for pure QML UI modules
│   ├── mkStandaloneApp.nix # apps.default for logos-standalone-app
│   ├── mkModuleLib.nix     # Library builder
│   ├── mkModuleInclude.nix # Header generator
│   ├── mkExternalLib.nix   # External library handler
│   └── parseMetadata.nix   # metadata.json parser
├── cmake/
│   └── LogosModule.cmake   # Reusable CMake module
├── templates/              # Module templates
├── examples/               # Working examples
├── docs/                   # Documentation
└── skills/                 # AI assistant skills
```

## License

MIT
