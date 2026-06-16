# Module Configuration Reference

This document describes all available fields in `metadata.json` — the single configuration file for a Logos module. 

## Basic Structure

```json
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
  "category": "general",
  "description": "My custom Logos module",
  "main": "my_module_plugin",
  "view": null,
  "dependencies": [],

  "nix": {
    "packages": {
      "build": [],
      "runtime": []
    },
    "external_libraries": [],
    "cmake": {
      "find_packages": [],
      "extra_sources": []
    }
  }
}
```

The top-level fields are embedded into the Qt plugin at compile time via `Q_PLUGIN_METADATA`. The `"nix"` block is used by the build system for derivations and CMake generation — Qt ignores it.

## Required Fields

### `name`
**Type:** string
**Required:** Yes

The module name. Used for:
- Plugin filename: `{name}_plugin.so` / `{name}_plugin.dylib`
- Nix package name: `logos-{name}-module`
- Interface class naming convention

```json
"name": "my_module"
```

## Optional Top-Level Fields

### `version`
**Type:** string
**Default:** `"1.0.0"`

The module version in semver format.

```json
"version": "1.2.3"
```

### `type`
**Type:** string
**Default:** `"core"`

The module type. Supported values:
- `"core"` — backend/logic module, no UI (use `mkLogosModule`)
- `"ui"` — legacy C++ UI widget module (use `mkLogosModule`)
- `"ui_qml"` — QML view module with optional C++ backend (use `mkLogosQmlModule`)

```json
"type": "core"
```

### `interface`
**Type:** string
**Default:** none (classic authoring)

Selects the authoring model. When set to `"universal"`, you write only an impl
class in `src/<name>_impl.{h,cpp}` deriving `LogosModuleContext`; the builder
generates the `<name>_interface.h` + `<name>_plugin.{h,cpp}` glue
(`Q_PLUGIN_METADATA`, `initLogos` wiring) from your impl header. This is the
model used by all C++ templates.

- `"universal"` — generated glue, impl class is the API (recommended)
- `"provider"` — generate a provider interface from `src/<name>_impl.h` (uses
  `LOGOS_METHOD`-annotated declarations)
- omitted — classic hand-written `*_interface.h` + `*_plugin.{h,cpp}` (still
  supported for backward compatibility)

```json
"interface": "universal"
```

### `codegen`
**Type:** object
**Default:** `{}`

Overrides for the generator driven by `interface`. Rarely needed — by default
the impl header/class are derived from `name` (e.g. `my_module` →
`src/my_module_impl.h`, class `MyModuleImpl`).

| Field | Applies to | Description |
|-------|-----------|-------------|
| `impl_header` | `universal` | Path to the impl header (default `src/<name>_impl.h`) |
| `impl_class` | `universal` | Impl class name (default PascalCase of `<name>` + `Impl`) |
| `provider_header` | `provider` | Path to the provider header |
| `rep` | `ui_qml` + `universal` | Path to the `.rep` QtRO contract for a C++ UI backend |

```json
"interface": "universal",
"codegen": {
  "impl_header": "src/custom_impl.h",
  "impl_class": "CustomImpl"
}
```

For a universal C++ UI backend (`"type": "ui_qml"` + `"interface": "universal"`),
`codegen.rep` points at the `.rep` view contract:

```json
"type": "ui_qml",
"interface": "universal",
"codegen": { "rep": "src/my_ui.rep" }
```

### `category`
**Type:** string
**Default:** `"general"`

The module category for organizational purposes.

Common categories:
- `general` — General purpose modules
- `network` — Network protocol modules (waku, etc.)
- `chat` — Chat/messaging modules
- `wallet` — Wallet/crypto modules
- `integration` — External library integrations

```json
"category": "network"
```

### `description`
**Type:** string
**Default:** `"A Logos module"`

Human-readable description of the module.

```json
"description": "Waku network protocol module for decentralized messaging"
```

### `main`
**Type:** string
**Default:** null

The entry point for the module. For C++ modules this is the plugin name without extension (e.g. `"my_module_plugin"`). For `ui_qml` modules, when present, it is the optional backend plugin name rather than the QML entry point.

```json
"main": "my_module_plugin"
```

### `icon`
**Type:** string
**Default:** null

Relative path to the module icon (used by UI modules). The build system reads this to include the icon in the standalone app plugin directory.

```json
"icon": "icons/my_module.png"
```

### `view`
**Type:** string
**Default:** null

Relative path (from the module's `src/` directory) to the QML entry file. For `type == "ui_qml"`, this field is required and identifies the QML entry point. If `main` is also set, it points to the optional backend plugin while `view` still identifies the UI entry.

The build system copies the view directory (e.g. `qml/`) alongside the plugin `.so` in the output.

```json
"view": "qml/Main.qml"
```

### `dependencies`
**Type:** array of strings
**Default:** `[]`

List of other Logos modules this module depends on at runtime. The build system uses this to:
1. Copy generated headers from dependent modules at build time
2. Auto-resolve flake inputs from `flakeInputs` (keys matching dependency names are passed as `moduleDeps`)

```json
"dependencies": ["waku_module", "capability_module"]
```

## Nix/Build-Only Fields (`"nix"` block)

All fields under `"nix"` are ignored by the Qt runtime.

### `nix.packages`
**Type:** object
**Default:** `{ "build": [], "runtime": [] }`

Additional Nix packages required for building or running the module.

#### `nix.packages.build`
Packages needed only during build (dev dependencies).

#### `nix.packages.runtime`
Packages needed at runtime.

```json
"nix": {
  "packages": {
    "build": ["protobuf", "abseil-cpp"],
    "runtime": ["zstd", "krb5"]
  }
}
```

Package names can be dotted for nested packages:

```json
"nix": {
  "packages": {
    "build": ["qt6.qtbase", "python3Packages.numpy"]
  }
}
```

### `nix.rust`
**Type:** object
**Default:** `{ "packages": { "build": [], "runtime": [] }, "env": {} }`

External system build dependencies for a **Rust cdylib module's crate compile**
(`codegen.rust`). Unlike `nix.packages` — which feeds the C++ plugin link — these are
passed to the `buildRustPackage` that compiles your crate to a staticlib, so a crate
with a `*-sys` dependency (a C library located via `pkg-config`) builds inside the Nix
sandbox. Empty by default, so modules with no native deps build exactly as before.

| Field | `buildRustPackage` attr | Use for |
|-------|-------------------------|---------|
| `packages.build` | `nativeBuildInputs` | host build tools: `pkg-config`, `protoc`, `perl`, `rustPlatform.bindgenHook` |
| `packages.runtime` | `buildInputs` | libraries to link: `openssl`, `sqlite`, `zstd` |
| `env` | `env` | flag-style env vars some `*-sys` crates need |

Package names resolve like `nix.packages` (dotted nixpkgs paths). With `pkg-config` in
`build` and the library in `runtime`, Nix sets `PKG_CONFIG_PATH` automatically so the
crate's build script finds it.

Example — a crate using `reqwest` with `native-tls` (needs OpenSSL):

```json
"nix": {
  "rust": {
    "packages": { "build": ["pkg-config"], "runtime": ["openssl"] },
    "env": { "OPENSSL_NO_VENDOR": "1" }
  }
}
```

Example — a crate using `bindgen`. The `rustPlatform.bindgenHook` setup package sets
`LIBCLANG_PATH` / `BINDGEN_EXTRA_CLANG_ARGS` for you:

```json
"nix": {
  "rust": {
    "packages": { "build": ["rustPlatform.bindgenHook"] }
  }
}
```

> Tip: many crates expose a `vendored` feature (e.g. `reqwest/native-tls-vendored`,
> `rusqlite/bundled`) that compiles the C source in-tree with `cc` and needs no
> `nix.rust` at all. Prefer that when available; reach for `nix.rust` when you must link
> the system library.

For deps that can't be named by a nixpkgs attr path (an arbitrary derivation, or env that
must hold a store path), `mkLogosModule` in `flake.nix` also accepts
`rustExtraNativeBuildInputs`, `rustExtraBuildInputs`, and `rustEnv` — merged on top of
`nix.rust` (`rustEnv` wins on key conflict).

### `nix.external_libraries`
**Type:** array of objects
**Default:** `[]`

External C/C++ libraries to wrap. Each entry is an object with a `name` and one of:

#### Vendor/pre-built library (simplest)

Place the pre-built library in `lib/` and git-track it:

```json
"nix": {
  "external_libraries": [
    {
      "name": "waku",
      "vendor_path": "lib"
    }
  ]
}
```

#### Library fetched from a flake input

Pass the flake input via `externalLibInputs` in `flake.nix`:

```json
"nix": {
  "external_libraries": [
    {
      "name": "gowalletsdk",
      "build_command": "make shared-library",
      "go_build": true
    }
  ]
}
```

#### Library Object Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Library name (required, must match `EXTERNAL_LIBS` in CMakeLists.txt) |
| `vendor_path` | string | Path to directory containing pre-built library files |
| `build_command` | string | Command to build a flake-input library (default: `make`) |
| `build_script` | string | Path to custom build script |
| `output_pattern` | string | Glob pattern for output files |
| `go_build` | boolean | Enable Go build environment |

### `nix.cmake`
**Type:** object
**Default:** `{}`

Additional CMake configuration options.

#### `nix.cmake.find_packages`
**Type:** array of strings

CMake packages to find via `find_package()`.

```json
"nix": {
  "cmake": {
    "find_packages": ["Protobuf", "Threads", "ZLIB"]
  }
}
```

#### `nix.cmake.extra_sources`
**Type:** array of strings

Additional source files beyond the impl sources (`*_impl.h`, `*_impl.cpp`) you
list in `CMakeLists.txt`. The generated glue is compiled automatically and does
not need to be listed here.

```json
"nix": {
  "cmake": {
    "extra_sources": ["src/helper.cpp", "src/utils.cpp"]
  }
}
```

#### `nix.cmake.extra_include_dirs`
**Type:** array of strings

Additional include directories.

```json
"nix": {
  "cmake": {
    "extra_include_dirs": ["lib", "vendor/include"]
  }
}
```

#### `nix.cmake.extra_link_libraries`
**Type:** array of strings

Additional libraries to link.

```json
"nix": {
  "cmake": {
    "extra_link_libraries": ["pthread", "dl"]
  }
}
```

## Complete Example

A chat module that depends on waku, uses protobuf, and exposes its API to other modules:

```json
{
  "name": "chat",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
  "category": "messaging",
  "description": "Chat module using Waku for decentralized messaging",
  "main": "chat_plugin",
  "dependencies": ["waku_module"],

  "nix": {
    "packages": {
      "build": ["protobuf", "abseil-cpp"],
      "runtime": ["zstd", "krb5"]
    },
    "external_libraries": [],
    "cmake": {
      "find_packages": ["Protobuf", "Threads"],
      "extra_sources": ["src/chat_api.cpp", "src/chat_api.h"],
      "extra_include_dirs": [],
      "extra_link_libraries": []
    }
  }
}
```
