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
nix build                    # Build everything
nix build .#lib              # Build just the library
nix build .#lgx              # Build .lgx package
nix build .#lgx-portable     # Build portable .lgx package
nix build .#install          # Build, package, and install (dev)
nix build .#install-portable # Build, package, and install (portable)
```

### UI modules: `nix run` with logos-standalone-app

For `type: "ui_qml"` modules, `logos-module-builder` automatically wires up `apps.default` so `nix run .` launches the module in `logos-standalone-app`. No separate `logos-standalone-app` input is needed — it is bundled inside `logos-module-builder`.

**With C++ backend** (`mkLogosQmlModule` — validates `"type": "ui_qml"` + `"view"` field, compiles backend when `"main"` is set):

The C++ plugin runs in a separate `ui-host` process (process-isolated), and the QML view is loaded in the host application. Communication happens via Qt Remote Objects over a private socket. Use `logos.module()` from QML to access the backend replica.

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add backend dependencies as inputs:
    # calc_module.url = "github:logos-co/logos-tutorial?dir=logos-calc-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

**QML-only** (`mkLogosQmlModule` — no C++ compilation, runs in-process):
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

Then `nix run .` launches the module in `logos-standalone-app`. Dependencies listed in `metadata.json` are automatically bundled from their LGX packages and loaded at runtime.

See `templates/ui-qml-backend`, `templates/ui-qml`, and `lib/mkLogosQmlModule.nix`.

### UI integration tests

For `ui_qml` modules, `mkLogosQmlModule` auto-detects `.mjs` test files in the `tests/` directory and wires up integration testing using [logos-qt-mcp](https://github.com/logos-co/logos-qt-mcp)'s test framework. No extra flake inputs needed.

```bash
# Run tests hermetically (builds everything, launches headless, runs tests)
nix build .#integration-test -L

# Build the test framework for interactive use (one-time)
nix build .#test-framework -o result-mcp

# Run tests interactively (app must be running with inspector on :3768)
node tests/ui-tests.mjs
```

Tests use the QML inspector to interact with the running UI — finding elements, clicking buttons, verifying text. Example test file (`tests/ui-tests.mjs`):

```javascript
import { resolve } from "node:path";

// CI sets LOGOS_QT_MCP automatically; for interactive use: nix build .#test-framework -o result-mcp
const root = process.env.LOGOS_QT_MCP || new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(root, "test-framework/framework.mjs"));

test("my_module: loads UI", async (app) => {
  await app.waitFor(
    async () => { await app.expectTexts(["Hello"]); },
    { timeout: 15000, interval: 500, description: "UI to load" }
  );
});

run();
```

See the [logos-qt-mcp](https://github.com/logos-co/logos-qt-mcp) test framework for available assertions and helpers.

## Features

- **~90% reduction in boilerplate** per module
- **Single source of truth** via `metadata.json` — used by Nix build and embedded into Qt plugins at compile time
- **Automatic CMake configuration** via `LogosModule.cmake`
- **External library support** (vendor pre-built or flake-input source)
- **Cross-platform** (macOS, Linux)
- **Auto-resolved module dependencies** from `flakeInputs`
- **Built-in LGX packaging** — `nix build .#lgx` and `nix build .#lgx-portable` included automatically
- **Built-in install outputs** — `nix build .#install` and `nix build .#install-portable` bundle and install via lgpm in one step
- **Auto-detected UI integration tests** — put `.mjs` test files in `tests/` and get `nix build .#integration-test` for free

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
# Minimal core module (backend/logic, no UI)
nix flake init -t github:logos-co/logos-module-builder

# C++ UI module — view module with C++ backend + QML view (process-isolated)
nix flake init -t github:logos-co/logos-module-builder#ui-qml-backend

# QML-only UI module (no C++ backend, in-process)
nix flake init -t github:logos-co/logos-module-builder#ui-qml

# Module with external library
nix flake init -t github:logos-co/logos-module-builder#with-external-lib
```

## AI Assistant Skills

For AI assistants (Claude, Cursor, etc.), we provide skill files:

| Skill | Description |
|-------|-------------|
| [create-logos-module](skills/create-logos-module.md) | Step-by-step guide to create a new core module |
| [create-ui-module](skills/create-ui-module.md) | Create a ui_qml module with C++ backend + QML view (process-isolated) |
| [create-qml-module](skills/create-qml-module.md) | Create a ui_qml module (QML-only, in-process) |
| [update-logos-module](skills/update-logos-module.md) | Guide to update/modify existing modules |

## Testing

The builder has a pure Nix evaluation test suite (no compilation required). Tests cover metadata parsing, utility functions, external library helpers, and template validity.

```bash
# Run tests via nix
nix build '.#checks.x86_64-linux.default'

# Or use nix flake check (runs all checks for the current system)
nix flake check

# From the logos-workspace
ws test logos-module-builder
```

Tests are in `tests/` and are organized into:

| File | What it tests |
|------|---------------|
| `test-parse-metadata.nix` | `metadata.json` parsing, defaults, required fields, type coercion |
| `test-common.nix` | Name formats, platform helpers, recursive merge, dependency collection |
| `test-external-lib.nix` | External library detection, name extraction, vendor build scripts |
| `test-templates.nix` | All 4 templates parse correctly, expected files exist, field consistency |

## Architecture

```
logos-module-builder/
├── lib/                    # Nix library functions
│   ├── mkLogosModule.nix   # Builder for core + legacy UI widget modules
│   ├── mkLogosQmlModule.nix # Builder for ui_qml modules (QML view + optional C++ backend)
│   ├── buildCppPlugin.nix  # Shared C++ plugin build pipeline
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
