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
└── src/                 # Source files (universal authoring model)
    ├── my_module_impl.h
    └── my_module_impl.cpp
```

In the **universal** authoring model you write only an impl class deriving
`LogosModuleContext`. Its public methods *are* the module's API. The Qt plugin
glue (`my_module_interface.h`, `my_module_plugin.{h,cpp}`, `Q_PLUGIN_METADATA`,
`initLogos` wiring) is **generated** from `src/my_module_impl.h` — you never
hand-write it. The classic hand-written interface + plugin path still works for
backward compatibility, but the templates and the recommended path are universal.

### 2. Define your module in `metadata.json`

```json
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
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

### Executable doc-tests

`doctests/` holds step-by-step, runnable tutorials (run in CI by the
Doc-Tests workflow via the shared
[`doctest`](https://github.com/logos-co/logos-doctest) CLI, each building
real modules against the commit under test):

- **wrap-external-lib-1…4** — the four ways an external C/C++ library can
  reach a module build (in-repo source, prebuilt binaries, external source
  built with `make`, an external Nix flake).
- **cross-language-composition** — the C++ ↔ Rust feature-parity showcase:
  a contract-first C++ cdylib module, a Rust-first module (trait → `.lidl`),
  and a universal C++ consumer, with typed calls and a typed event crossing
  the language boundary in both directions.
- **cross-language-composition-reverse** — the mirror image: contract-first
  Rust, a pure-C++ universal module in the middle (typed deps + `logos_events:`
  emission), and a Rust-first consumer subscribing to the C++ module's typed
  event. Between the two compositions, every authoring/consumption direction
  of the parity matrix is exercised.
- **ui-typed-backend** — the universal authoring model for UI modules
  (`type: "ui_qml"` + `interface: "universal"`): you write the `.rep` (the
  view contract — SLOTs, PROPs, SIGNALs) and a `*Backend` class deriving
  `<RepClass>SimpleSource` + `LogosModuleContext`; the `*Plugin`/`*Interface`
  classes are generated. The backend gets typed dependency calls and typed
  event subscriptions (armed in `onContextReady()`), here feeding a `.rep`
  PROP that auto-syncs into QML.
- **cdylib-qt-free-outbound** — a `interface: "cdylib"` C++ module calling its
  dependency through `modules().<dep>...` with **no Qt in its own code**: the
  generated typed wrappers call the logos-protocol `lp_*` C ABI directly
  (`logos::LpClient`), so Qt stays confined to the QRO transport and the plugin
  glue. A counter + a relay that forwards to it, driven through `logoscore`.

Run one locally:

```bash
nix run github:logos-co/logos-doctest -- run \
  doctests/cross-language-composition.test.yaml \
  --verbose --release-for logos-module-builder=<commit-to-test>
```

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
├── docs/                   # Documentation
└── skills/                 # AI assistant skills
```

## License

MIT
