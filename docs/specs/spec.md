# Logos Module Builder

## Overall Description

The Logos Module Builder is a shared build library that provides a declarative, configuration-driven pipeline for building Logos modules. It takes a module's source code and a `metadata.json` configuration file as input and produces ready-to-use plugin binaries, generated SDK headers, distributable packages, and development environments as output.

The builder is designed to:
- Reduce module build configuration from ~600 lines across 5 files to ~70 lines across 2-3 files
- Provide a single source of truth (`metadata.json`) for both build-time configuration and runtime plugin metadata
- Abstract away the plugin compilation backend so modules are not permanently coupled to a specific technology (e.g., Qt)
- Automatically resolve module dependencies, build external C/C++ libraries, generate type-safe SDK wrappers, and produce distributable packages
- Support multiple module types (core logic, C++ UI, QML UI) through a unified configuration schema

## Definitions & Acronyms

| Term | Definition |
|------|------------|
| **Module** | An independently developed plugin for the Logos platform, built as a shared library (.so/.dylib) |
| **Builder** | The `logos-module-builder` Nix flake library — the subject of this document |
| **Backend** | A pluggable compilation strategy (e.g., Qt plugin, future CBOR standalone) that the builder delegates to |
| **metadata.json** | The declarative configuration file that describes a module's identity, dependencies, and build settings |
| **Plugin** | The compiled shared library output of a module build (e.g., `my_module_plugin.so`) |
| **LGX** | Logos package format — a gzip tar archive containing platform-specific module variants for distribution |
| **SDK Headers** | Generated C++ wrapper classes that provide type-safe access to a module's methods from other modules |
| **External Library** | A third-party C/C++ library (e.g., a Go CGo static library) that a module depends on and the builder compiles from source |
| **Standalone App** | A host application (`logos-standalone-app`) that can load and run a single UI module for development and testing |
| **Flake Input** | A Nix flake dependency — modules declare other modules and external libraries as flake inputs |

## Domain Model

### Build Pipeline

The builder orchestrates a multi-stage pipeline for each module:

```
metadata.json + src/
       │
       ▼
  ┌─────────────┐
  │ Parse Config │  parseMetadata.nix
  └──────┬──────┘
         │
         ▼
  ┌──────────────┐     ┌────────────────┐
  │ Build Ext.   │────▶│ External Libs  │  mkExternalLib.nix
  │ Libraries    │     │ (.a / .dylib)  │
  └──────┬───────┘     └───────┬────────┘
         │                     │
         ▼                     │
  ┌──────────────┐             │
  │ Build Plugin │◀────────────┘  backend.buildPlugin
  │ (.so/.dylib) │
  └──────┬───────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  ┌─────┐  ┌───────┐
  │ LGX │  │Headers│  backend.buildHeaders
  └─────┘  └───────┘
```

### Configuration as Single Source of Truth

`metadata.json` serves two purposes simultaneously:

1. **Build-time**: The Nix build system reads it to determine dependencies, packages, external libraries, and CMake settings. These are under the `nix` key.
2. **Runtime**: Qt's `Q_PLUGIN_METADATA` macro embeds it into the compiled plugin binary. The Logos runtime reads it for module name, version, type, dependencies, and capabilities.

This means a module author maintains one file, and both the build system and the runtime derive what they need from it.

### Backend Abstraction

The builder does not compile plugins directly. Instead, it delegates to a **backend** selected by the module's `type` field:

| Module type | Backend | What it does |
|-------------|---------|-------------|
| `core` | `coreBackend` | Compiles a headless C++ plugin (logic-only, no UI) |
| `ui` | `uiBackend` | Compiles a C++ Qt widget plugin with UI components |
| `ui_qml` | (built-in) | No compilation — stages QML source files for runtime loading |

Currently both `coreBackend` and `uiBackend` point to the same implementation (`logos-plugin-qt`), but they are separate flake inputs so `coreBackend` can be swapped to a non-Qt backend without affecting UI modules.

A backend must implement three functions:
- `buildPlugin { pkgs, src, config, ... }` — compile the plugin shared library
- `buildHeaders { pkgs, src, config, pluginLib }` — generate SDK headers from the compiled plugin
- `devShellInputs pkgs` — provide dependencies for `nix develop`

### Module Dependencies

Modules declare dependencies on other modules by name in `metadata.json`:

```json
{
  "dependencies": ["capability_module", "accounts_module"]
}
```

The builder automatically:
1. Matches dependency names to flake input names
2. Resolves each to its `packages.<system>.default` output
3. Copies include files from each dependency into `generated_code/` so the module can use their SDK headers
4. For UI standalone apps: recursively collects all transitive dependencies and bundles them as LGX packages

### External Libraries

Modules that wrap third-party C/C++ libraries declare them in `metadata.json`:

```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "gowalletsdk",
        "build_command": "make static-library",
        "go_build": true,
        "output_pattern": "build/libgowalletsdk.*"
      }
    ]
  }
}
```

The builder:
1. Takes the library's source as a flake input (or vendor submodule)
2. Builds it in an isolated derivation with the appropriate toolchain (Go, Make, etc.)
3. Copies the resulting `.a`/`.so`/`.dylib` and headers into the module's build directory
4. The module's CMakeLists.txt links against the library using standard CMake

## Features & Requirements

### Module Compilation

- C++17 Qt 6 plugin compilation via CMake and Ninja
- Automatic Qt MOC (Meta-Object Compiler) processing
- Platform-specific shared library output (`.so` on Linux, `.dylib` on macOS)
- macOS install name and rpath fixups for plugin and all bundled libraries
- `dontStrip` to preserve Qt plugin metadata sections in ELF/Mach-O binaries

### SDK Header Generation

- Automatic generation of type-safe C++ wrapper classes from compiled plugins
- Uses `logos-cpp-generator` to introspect the plugin via `QPluginLoader` reflection
- Produces per-module `<name>_api.h/cpp` and umbrella `logos_sdk.h/cpp`
- Headers are installed to `$out/include/` for downstream consumers

### LGX Packaging

- Every module automatically gets `lgx` and `lgx-portable` package outputs
- Dev builds use platform-variant suffixes (e.g., `linux-amd64-dev`)
- Portable builds use standard suffixes (e.g., `linux-amd64`)
- Packages are created via `nix-bundle-lgx`

### Development Shells

- `nix develop` provides a complete build environment with Qt, CMake, Ninja, and all dependencies
- Environment variables set: `LOGOS_CPP_SDK_ROOT`, `LOGOS_MODULE_ROOT`, `LOGOS_MODULE_BUILDER_ROOT`
- Build-time and runtime packages from `metadata.json` are included automatically

### Standalone App Runner

- UI modules (type `ui` and `ui_qml`) automatically get `nix run` support
- Creates a self-contained directory with the plugin, its transitive dependencies, and a host application
- Dependencies are bundled as LGX packages, extracted at build time

### Template Scaffolding

Four templates for `nix flake init -t`:
- **Minimal module** — core logic plugin with basic structure
- **External library module** — core plugin wrapping a third-party C/C++ library
- **UI module** — C++ Qt widget plugin with `createWidget()`/`destroyWidget()`
- **QML module** — Pure QML UI module with `Main.qml`

### Configuration Schema

The `metadata.json` schema includes:

**Runtime fields** (embedded in plugin):
- `name`, `version`, `type`, `category`, `description`, `main`, `icon`
- `dependencies` — other module names
- `include` — additional files to bundle
- `capabilities` — capabilities this module provides

**Build fields** (under `nix` key):
- `packages.build` / `packages.runtime` — nix package names
- `external_libraries` — external C/C++ library definitions
- `cmake.find_packages`, `cmake.extra_sources`, `cmake.extra_include_dirs`, `cmake.extra_link_libraries`

## Supported Platforms

- macOS (aarch64-darwin, x86_64-darwin)
- Linux (aarch64-linux, x86_64-linux)

## Future Work

- **Non-Qt core backend** — Allow core modules to compile without Qt dependency using a CBOR-based standalone backend
- **LIDL-based header generation** — Generate SDK headers from `.lidl` interface definitions instead of requiring plugin introspection, removing the header generation dependency on the compiled plugin
- **Cross-compilation** — Support building modules for platforms other than the host
