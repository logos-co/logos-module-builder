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
`LogosModuleContext`. Its public methods *are* the module's API. Everything else
is **generated** from `src/my_module_impl.h` — you never hand-write it:

- `generated_code/my_module.lidl` — the contract, derived from your impl header
- `my_module_cdylib_glue.{h,cpp}` — the Qt plugin `logos_host` loads
  (`Q_PLUGIN_METADATA`, `onInit` wiring)
- `my_module_module_impl.cpp` + `my_module_types.h` — the Qt-free C-ABI export
  wrapper around your impl class (plus `my_module_events_cdylib.cpp` when the
  header declares `logos_events:`)

(An earlier revision generated `my_module_interface.h` + `my_module_plugin.{h,cpp}`
instead; neither file name is emitted any more.)

A `core` module that ships a plugin must declare an `interface`. Omitting it is
refused at evaluation rather than silently generating no glue, so the classic
hand-written interface + plugin path is no longer a way to build one; the
alternative to `"universal"` is `"cdylib"` (bring your own C ABI plus a committed
`codegen.lidl`). Legacy `type: "ui"` widget modules are unaffected.

### 2. Define your module in `metadata.json`

```json
{
  "name": "my_module",
  "display_name": "My Module",
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
nix build .#generate         # Emit a ready-to-build codebase (all code generators run)
nix build .#lgx              # Build .lgx package
nix build .#lgx-portable     # Build portable .lgx package
nix build .#install          # Build, package, and install (dev)
nix build .#install-portable # Build, package, and install (portable)
```

`nix build .#generate` runs every code generator that is part of the build —
`logos-cpp-generator` (`--general-only` + dependency/interface wrappers) and the
interface-specific glue (LIDL, Qt glue, C-ABI dispatch, UI plugin glue) — and
leaves the result in `result/`: the module source plus a fully-populated
`generated_code/`. Inspect the generated glue, or build it directly from the
module's `nix develop` shell (which exports the `LOGOS_*_ROOT` vars) without
re-running any generator. The output is exactly what a normal build compiles. It
is produced for every C++ module and for UI modules with a C++ backend (QML-only
modules have no generators to run).

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

### UI modules: the dev loop

`nix run .` re-evaluates the flake and rebuilds the plugin on every invocation —
including for a one-character QML edit, because `src` covers the whole tree. For
iterating on a view, build the launcher once and relaunch it instead:

```bash
nix build .#ui-dev                     # once
./result/bin/run-logos-standalone-ui   # relaunch after C++ changes
```

`ui-dev` is the same wrapper `nix run` uses — dependency modules bundled and
loaded the same way — exposed as a package so it lands in `./result/bin`.

Run it from the repo root and it finds your QML source automatically (looking
for the `view` entry under `src/<viewDir>/` then `<viewDir>/`, matching where the
build looks). From then on **QML edits need no rebuild at all**: save a file and
the view re-renders in about 200 ms, with the backend process left running.

It prints what it picked up on startup:

```
run-logos-standalone-ui: hot-reloading QML from /path/to/my-ui/src/qml
  (export DEV_QML_PATH to override, or LOGOS_QML_HOT_RELOAD=0 to disable)
```

Set `DEV_QML_PATH` yourself for a non-standard layout, or run from outside the
repo to use the installed QML instead. Reloading rebuilds only the QML: a
module's C++ backend runs in a separate `ui-host` process and keeps its state,
while QML-side state (scroll position, text fields) resets. A syntax error is
logged with its line number and the next save that compiles restores the view.
`LOGOS_QML_HOT_RELOAD=0` disables watching.

`ui-dev` is a development target: it is not part of `packages.default` and is
never bundled into `.lgx` packages.

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
- **Ready-to-build source output** — `nix build .#generate` runs every code generator and emits the module source + a fully-populated `generated_code/` in `result/`
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
| `test-collectAllModuleDeps.nix` | Transitive dependency collection over mock flake inputs |
| `test-external-lib.nix` | External library detection, name extraction, vendor build scripts |
| `test-static-extlib.nix` | Static `.a` archives in `EXTERNAL_LIBS` (build-time link, no runtime copy) |
| `test-templates.nix` | All 4 templates parse correctly, expected files exist, field consistency |
| `test-fixtures.nix` | Parsing the real `metadata.json` files under `tests/fixtures/` |
| `test-module-pre-configure.nix` | Which codegen `interface` selects; the removed `"provider"` must throw |
| `test-consumer-api-style.nix` | `codegen.consumer_api_style` and the safety gate on it |
| `test-qt-host-repoint.nix` | Which Qt host runtime `logos_module()` links, and how it refuses |
| `test-view-interface-abi.nix` | Module-side and host-side view-plugin interface declarations must not drift |
| `test-qml-integration.nix` | Builds a `ui_qml` fixture and checks the output derivation |
| `test-framework-integration.nix` | Builds and runs a fixture module's unit tests via `mkLogosModuleTests` |
| `test-rust-native-dep.nix` | The `nix.rust` block feeding a Rust crate's native build deps |

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
  `<RepClass>SimpleSource` + `LogosUiPluginContext`; the `*Plugin`/`*Interface`
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
│   ├── default.nix         # Library entry point — imports sub-builders, passes backends
│   ├── mkLogosModule.nix   # Builder for core + legacy UI widget modules
│   ├── mkLogosQmlModule.nix # Builder for ui_qml modules (QML view + optional C++ backend)
│   ├── buildCppPlugin.nix  # Shared C++ plugin build pipeline
│   ├── mkLogosModuleTests.nix # Builder for a module's own unit tests
│   ├── modulePreConfigure.nix # preConfigure codegen, selected by `interface`
│   ├── mkStandaloneApp.nix # apps.default for logos-standalone-app
│   ├── mkExternalLib.nix   # External library handler
│   ├── parseMetadata.nix   # metadata.json parser
│   └── common.nix          # Shared utilities (systems, name helpers, dep collection)
├── cmake/
│   └── LogosModule.cmake   # Reusable CMake module
├── templates/              # Module templates
├── docs/                   # Documentation
└── skills/                 # AI assistant skills
```

## License

MIT
