# Logos Module Builder — Project Description

## Project Structure

```
logos-module-builder/
├── flake.nix                       # Flake entry point — wires backends, exports lib + templates
├── lib/
│   ├── default.nix                 # Library entry point — imports sub-builders, passes backends
│   ├── mkLogosModule.nix           # Builder for core + legacy UI widget modules
│   ├── mkLogosQmlModule.nix        # Builder for ui_qml modules (QML view + optional C++ backend)
│   ├── buildCppPlugin.nix          # Shared C++ plugin build pipeline
│   ├── mkExternalLib.nix           # Builds external C/C++ libraries from flake inputs or vendor paths
│   ├── mkStandaloneApp.nix         # Creates `nix run` app wrapper for UI modules
│   ├── parseMetadata.nix           # Parses metadata.json and applies defaults
│   └── common.nix                  # Shared utilities (systems list, name helpers, transitive dep collection)
├── cmake/                          # (empty — LogosModule.cmake lives in logos-plugin-qt)
├── templates/
│   ├── minimal-module/             # `nix flake init -t` — core module scaffold
│   ├── external-lib-module/        # Module wrapping an external C/C++ library
│   ├── ui-qml-backend/             # ui_qml with C++ backend + QML view
│   └── ui-qml/                    # ui_qml QML-only (no C++)
├── docs/                           # User-facing documentation
│   ├── index.md                    # Documentation home
│   ├── getting-started.md          # 10-minute quickstart
│   ├── quick-reference.md          # Cheat sheet
│   ├── configuration.md            # metadata.json reference
│   ├── cmake-reference.md          # LogosModule.cmake reference
│   ├── nix-api.md                  # mkLogosModule / mkLogosQmlModule reference
│   ├── external-libraries.md       # External library guide
│   ├── migration.md                # Migration from manual build to builder
│   └── troubleshooting.md          # Common issues
└── skills/                         # AI assistant skill definitions
```

## Stack, Frameworks & Dependencies

| Dependency | Role |
|------------|------|
| Nix (flakes) | Build orchestration, dependency resolution, reproducible builds |
| logos-plugin-qt | Qt plugin compilation backend (buildPlugin, buildHeaders, devShellInputs) |
| logos-plugin-core | Core module backend (currently same as logos-plugin-qt, swappable) |
| nix-bundle-lgx | LGX package creation |
| logos-standalone-app | Host application for `nix run` on UI modules |
| logos-nix | Shared nixpkgs pin |

The builder itself contains no C++ code or compilation logic — it is pure Nix. All compilation is delegated to backends.

## Core Modules

### parseMetadata (`lib/parseMetadata.nix`)

**Purpose**: Parses `metadata.json` and fills in defaults for omitted fields.

| Field | Default |
|-------|---------|
| `version` | `"1.0.0"` |
| `type` | `"core"` |
| `category` | `"general"` |
| `description` | `"A Logos module"` |
| `dependencies` | `[]` |
| `include` | `[]` |
| `nix.packages.build` | `[]` |
| `nix.packages.runtime` | `[]` |
| `nix.external_libraries` | `[]` |
| `nix.cmake.find_packages` | `[]` |
| `nix.cmake.extra_sources` | `[]` |
| `nix.cmake.extra_include_dirs` | `[]` |
| `nix.cmake.extra_link_libraries` | `[]` |

### buildCppPlugin (`lib/buildCppPlugin.nix`)

**Purpose**: Shared C++ plugin build pipeline. Encapsulates config parsing, dependency resolution, plugin compilation (via backend), header generation, dev shells, and LGX bundling. Used internally by `mkLogosModule` and `mkLogosQmlModule`.

**Parameters**: Same as mkLogosModule (minus `logosStandalone`).

**Returns**: `{ config; perSystem.${system} = { pkgs, moduleLib, moduleLibPortable, moduleInclude, hasVariants }; devShells; lgxPackages; }`

### mkLogosModule (`lib/mkLogosModule.nix`)

**Purpose**: Builder for core C++ modules and legacy UI widget modules. Uses `buildCppPlugin` internally.

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `src` | yes | Path to module source |
| `configFile` | yes | Path to metadata.json |
| `flakeInputs` | no | All flake inputs — dependencies are matched by name |
| `externalLibInputs` | no | Flake inputs for external libraries |
| `extraBuildInputs` | no | Additional nix build inputs |
| `extraNativeBuildInputs` | no | Additional nix native build inputs |
| `configOverrides` | no | Attribute set merged on top of parsed metadata |
| `preConfigure` | no | Shell script run before CMake configure |
| `postInstall` | no | Shell script run after install |
| `logosStandalone` | no | Override the standalone app flake input |

**Outputs** (per system):

| Output | Description |
|--------|-------------|
| `default` | Combined lib + include |
| `lib` / `<name>-lib` | Plugin shared library |
| `include` / `<name>-include` | Generated SDK headers |
| `lgx` | LGX dev package |
| `lgx-portable` | LGX portable package |
| `apps.default` | Standalone runner (legacy UI widget modules only) |
| `devShells.default` | Development shell |

### mkLogosQmlModule (`lib/mkLogosQmlModule.nix`)

**Purpose**: Builder for `ui_qml` modules — QML view with an optional C++ backend. When `main` is declared in metadata.json, uses `buildCppPlugin` to compile the backend and bundles it alongside the QML view. When `main` is absent, produces a QML-only output (no compilation). Validates `type == "ui_qml"` and `view != null`.

**Parameters**: Same as mkLogosModule.

**Outputs** (per system):

| Output | Description |
|--------|-------------|
| `default` | Combined plugin .so (if backend) + QML view directory |
| `lib` / `<name>-lib` | Plugin shared library (only when backend present) |
| `lgx` | LGX dev package |
| `lgx-portable` | LGX portable package |
| `install` | Installed plugin directory (dev variant) |
| `install-portable` | Installed plugin directory (portable variant) |
| `apps.default` | Standalone runner (always present) |
| `devShells.default` | Development shell |

### mkExternalLib (`lib/mkExternalLib.nix`)

**Purpose**: Builds external C/C++ libraries from flake inputs or vendor submodule paths.

**Functions**:
- `buildExternalLibs { pkgs, config, externalInputs }` — builds all external libraries defined in config, returns attrset of name → derivation
- `generateVendorBuildScript { config, extLib }` — generates shell script for building vendor submodule libraries

Each external library derivation:
- Runs the configured build command (default: `make`)
- Enables Go toolchain if `go_build: true`
- Copies output `.a`/`.so`/`.dylib` to `$out/lib/`
- Copies header files to `$out/include/`

### mkStandaloneApp (`lib/mkStandaloneApp.nix`)

**Purpose**: Creates a `nix run`-able wrapper for UI modules.

Creates a directory structure:
```
$out/
├── bin/run-<name>              # Shell wrapper script
├── plugin-dir/
│   ├── <name>_plugin.so        # The module plugin
│   └── metadata.json           # Module metadata
└── modules-dir/
    ├── built-in modules...     # From logos-standalone-app
    └── dependency modules...   # LGX-extracted transitive deps
```

### common (`lib/common.nix`)

**Purpose**: Backend-agnostic utilities shared across all builders.

**Functions**:
- `systems` — list of supported platforms
- `getPluginFilename pkgs name` — returns `name_plugin.so` or `.dylib`
- `getLibExtension pkgs` — returns `so` or `dylib`
- `collectAllModuleDeps system inputs deps` — recursively walks flake inputs collecting transitive module dependencies
- `recursiveMerge` — deep-merges attribute sets

## Build Artifacts

| Artifact | Location | Description |
|----------|----------|-------------|
| Plugin library | `result/lib/<name>_plugin.so` | Compiled Qt plugin |
| External libraries | `result/lib/lib<ext>.*` | Bundled third-party libraries |
| SDK headers | `result/include/<name>_api.h` | Generated type-safe wrappers |
| Umbrella header | `result/include/logos_sdk.h` | Includes all dependency wrappers |
| LGX package | `result-lgx/<name>.lgx` | Distributable package |

## Operational

### Building a module

From any module that uses the builder:

```bash
# Standard build
nix build

# Specific outputs
nix build .#lib              # plugin only
nix build .#include          # headers only
nix build .#lgx              # LGX package

# Run (UI modules only)
nix run
```

From the logos-workspace:

```bash
ws build <module-name>
ws build <module-name> --auto-local   # with local dep overrides
```

### Scaffolding a new module

```bash
# Core module
mkdir my-module && cd my-module
nix flake init -t github:logos-co/logos-module-builder

# Module with external library
nix flake init -t github:logos-co/logos-module-builder#with-external-lib

# C++ UI module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-backend

# QML UI module
nix flake init -t github:logos-co/logos-module-builder#ui-qml
```

### Development shell

```bash
nix develop
# Provides: Qt, CMake, Ninja, logos-cpp-generator, and all declared dependencies
```

## Examples

### Minimal module flake.nix

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

### Minimal metadata.json

```json
{
  "name": "my_module",
  "version": "1.0.0",
  "description": "My module",
  "type": "core",
  "dependencies": [],
  "nix": {}
}
```

### Module with external library and dependencies

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    capability-module.url = "github:logos-co/logos-capability-module";
    go-wallet-sdk = {
      url = "github:status-im/go-wallet-sdk/some-rev";
      flake = false;
    };
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

```json
{
  "name": "accounts_module",
  "version": "1.0.0",
  "type": "core",
  "dependencies": ["capability_module"],
  "nix": {
    "external_libraries": [
      {
        "name": "gowalletsdk",
        "build_command": "make static-library",
        "go_build": true
      }
    ],
    "packages": {
      "runtime": ["nlohmann_json"]
    },
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

### Module with custom preConfigure (universal interface)

```nix
{
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      preConfigure = ''
        logos-cpp-generator --from-header src/my_module_impl.h \
          --backend qt \
          --impl-class MyModuleImpl \
          --impl-header my_module_impl.h \
          --metadata metadata.json \
          --output-dir ./generated_code
      '';
    };
}
```

## Consumers

Modules built with the builder include:
- `logos-accounts-module` — accounts/wallet operations (universal interface)
- `logos-capability-module` — authorization token management
- `logos-chat-module` — chat messaging
- `logos-package-manager-module` — local package management
- `logos-waku-module` — Waku network communication
- `logos-test-modules` — test suite modules
- All UI modules (`logos-accounts-ui`, `logos-chat-ui`, etc.)

## Supported Platforms

- macOS (aarch64-darwin, x86_64-darwin)
- Linux (aarch64-linux, x86_64-linux)

## Known Limitations

- LogosModule.cmake lives in `logos-plugin-qt`, not in this repository — changing CMake behavior requires modifying the backend
- Header generation requires building the full plugin first (reflection via QPluginLoader) — this will be addressed by LIDL-based generation
- `ui_qml` modules do not produce `include` outputs (no C++ API to generate wrappers for)
- Transitive dependency collection (`collectAllModuleDeps`) requires all transitive deps to have `packages.lgx` or be bundleable via nix-bundle-lgx
- External library builds are always from-source — no binary cache support for external libs
