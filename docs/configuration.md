# Module Configuration Reference

This document describes all available fields in `metadata.json` — the single configuration file for a Logos module. 

## Basic Structure

```json
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
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

### `nix.external_libraries`
**Type:** array of objects
**Default:** `[]`

External C/C++ libraries the module wraps. Every entry takes one of **five well-formed shapes** depending on where the library's binary comes from. The shape is determined by which fields you set on the entry and whether a matching attribute exists in `externalLibInputs` (passed to `mkLogosModule` from `flake.nix`).

All five shapes feed the same downstream pipeline: `mkExternalLib.buildExternalLibs` resolves each entry into `{ <name> = derivation-or-null }`, and the buildPlugin staging step copies the result into the plugin's `lib/` directory where CMake's `find_library` (driven by `EXTERNAL_LIBS <name>` in `CMakeLists.txt`) picks it up.

#### Decision matrix

| # | Shape | `vendor_path` | `build_command` / `build_script` | `externalLibInputs.<name>` | `go_build` | Use when |
|---|-------|---------------|----------------------------------|----------------------------|------------|----------|
| A | Prebuilt vendor binary | ✅ | — | — | — | You ship a `lib<name>.{so,dylib,a}` committed to git inside the module |
| B | Vendor compiled from source | ✅ | ✅ | — | — | The library's source files (`.c`/`.cpp`/Makefile) live inside the module repo and you don't want to commit binaries |
| C | Flake-input derivation | — | — | derivation | — | You depend on another flake that already exposes a packaged `lib<name>.{so,dylib}` (e.g. another Logos module, a nixpkgs derivation) |
| D | Flake-input source build | — | ✅ | source path / non-flake input | — | You depend on an external C/C++ source tree (e.g. a `flake = false` GitHub repo) and need to compile it |
| E | Flake-input Go build | — | ✅ | source path | ✅ + `vendor_hash` | The dependency is a Go module exposing a C-compatible static library via `cgo` |

> Exactly one column from `vendor_path` / `externalLibInputs.<name>` must be filled. Setting both is undefined; setting neither raises `External library <name>: must provide flake input or vendor_path`.

#### Shape A — Prebuilt vendor binary

The simplest case: drop a pre-built `lib<name>.so` / `lib<name>.dylib` into `vendor_path` and commit it to git so nix can see it. No build step runs — the binary is staged as-is.

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

Files expected in `lib/` (git-tracked):
- `libwaku.so` (Linux) or `libwaku.dylib` (Darwin) — the binary
- `libwaku.h` (or similar) — public headers, made accessible to your plugin code via `nix.cmake.extra_include_dirs`

The buildPlugin staging in `logos-plugin-qt` reads `${src}/${vendor_path}/lib*` directly. `buildExternalLibs` returns `null` for this shape — there's no separate derivation, and any change to the source tree re-stages.

Use this for libraries you receive prebuilt from a vendor and have no source for, or for libraries with a build process too gnarly to wire into nix.

#### Shape B — Vendor compiled from source

When the library's source lives inside your repo, set `build_command` (or `build_script`) so the builder compiles it as its own nix derivation rooted at `${moduleSrc}/${vendor_path}`. No binary needs to be committed.

```json
"nix": {
  "external_libraries": [
    {
      "name": "calc",
      "vendor_path": "lib",
      "build_command": "$CC -shared -fPIC -O2 -o $LIB_BASENAME libcalc.c"
    }
  ]
}
```

Files in `lib/` (git-tracked): just the source — e.g. `libcalc.c`, `libcalc.h`, optionally a `Makefile` if you'd rather `build_command: "make"`.

The build runs from `vendor_path` as its working directory with three env vars exported:

| Env var | Value | Example |
|---------|-------|---------|
| `LIB_NAME` | `extLib.name` | `calc` |
| `LIB_EXT` | `dylib` on Darwin, `so` elsewhere | `dylib` |
| `LIB_BASENAME` | `lib<name>.<ext>` | `libcalc.dylib` |

Using `$LIB_BASENAME` in the command keeps it portable across darwin/linux without `uname` checks. The staged dylib gets its install_name set to `@rpath/lib<name>.dylib` automatically on Darwin.

For multi-line builds use `build_script` instead — point at a shell script relative to the project root or `vendor_path` and the builder runs it with `bash`:

```json
{
  "name": "calc",
  "vendor_path": "lib",
  "build_script": "build.sh"
}
```

#### Shape C — Flake-input derivation

When another flake already publishes the library as a nix package (typical for inter-module dependencies and packages from nixpkgs), pass that flake's output through `externalLibInputs` in `flake.nix` and reference the lib by name in `metadata.json`. `buildExternalLibs` detects the value is already a derivation (`lib.isDerivation`) and uses it directly — no rebuild.

`metadata.json`:
```json
"nix": {
  "external_libraries": [
    { "name": "chat" }
  ]
}
```

`flake.nix`:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-chat.url = "github:logos-messaging/logos-chat";   # exposes packages.<system>.default
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        chat = inputs.logos-chat;
      };
    };
}
```

For finer control over which package output to consume (e.g. `default` for local builds vs `portable` for distributable bundles), `externalLibInputs.<name>` can be a structured `{ input, packages }` attrset:

```nix
externalLibInputs = {
  chat = {
    input = inputs.logos-chat;
    packages = { default = "default"; portable = "portable"; };
  };
};
```

This unlocks the `lib-portable` / `lgx-portable` outputs on the consuming module — see [external-libraries.md → Per-variant packages](external-libraries.md#per-variant-packages) for the full mechanism.

#### Shape D — Flake-input source build

When the dependency is just a source tree (typically a `flake = false` GitHub repo or a path input), provide `build_command` so the builder compiles it. Same env-var contract as Shape B.

`metadata.json`:
```json
"nix": {
  "external_libraries": [
    {
      "name": "tinyalsa",
      "build_command": "make"
    }
  ]
}
```

`flake.nix`:
```nix
inputs = {
  logos-module-builder.url = "github:logos-co/logos-module-builder";
  tinyalsa-src = {
    url = "github:tinyalsa/tinyalsa";
    flake = false;
  };
};

outputs = inputs@{ logos-module-builder, ... }:
  logos-module-builder.lib.mkLogosModule {
    ...
    externalLibInputs = {
      tinyalsa = inputs.tinyalsa-src;
    };
  };
```

The builder additionally probes a fixed list of output paths (`build/lib<name>.{dylib,so,a}`, `lib<name>.{dylib,so,a}`) when staging the result — override that with `output_pattern: "path/to/lib<name>.*"` if your build emits binaries elsewhere.

#### Shape E — Flake-input Go build (cgo)

For Go libraries that expose a C ABI via `cgo`, `go_build: true` switches the builder from `pkgs.stdenv.mkDerivation` to `pkgs.buildGoModule`. The Go vendor directory is hashed into a fixed-output derivation, which is the only way to grant network access inside the nix sandbox.

`metadata.json`:
```json
"nix": {
  "external_libraries": [
    {
      "name": "gowalletsdk",
      "build_command": "make static-library",
      "go_build": true,
      "vendor_hash": "sha256-sfJ1QW4J7b/K0XU5mkMzdFcJLAKeuZdPD7Tq+KfWw7g=",
      "output_pattern": "build/libgowalletsdk.*"
    }
  ]
}
```

`flake.nix`:
```nix
inputs = {
  logos-module-builder.url = "github:logos-co/logos-module-builder";
  go-wallet-sdk = {
    url = "github:status-im/go-wallet-sdk";
    flake = false;
  };
};

outputs = inputs@{ logos-module-builder, ... }:
  logos-module-builder.lib.mkLogosModule {
    ...
    externalLibInputs = {
      gowalletsdk = inputs.go-wallet-sdk;
    };
  };
```

To discover the right `vendor_hash`, set it to an empty string (`"vendor_hash": ""`) and nix will fail with the expected value embedded in the error message — copy that into metadata.json. Use `mod_root: "./<path>"` if `go.mod` isn't at the root of the flake input.

#### Library Object Fields

| Field | Type | Description | Used by shape(s) |
|-------|------|-------------|------------------|
| `name` | string | Library name. Required. Must match the argument to `EXTERNAL_LIBS` in `CMakeLists.txt` and is referenced as `lib<name>.{so,dylib,a}` everywhere. | All |
| `vendor_path` | string | Directory inside the module repo holding the library's source (B) or prebuilt binary (A), relative to the module root. | A, B |
| `build_command` | string | Shell command compiling the library. Runs from `vendor_path` (B) or the unpacked flake input source (D, E) with `LIB_NAME`/`LIB_EXT`/`LIB_BASENAME` in the environment. For E, default is `make`. | B, D, E |
| `build_script` | string | Path to a shell script (resolved relative to project root or `vendor_path`) used instead of `build_command`. Same env-var contract. | B, D |
| `output_pattern` | string | Glob pointing at the build output, relative to the build's working directory. Defaults to `build/lib<name>.*` for D/E. | D, E |
| `go_build` | boolean | Switch the builder to `pkgs.buildGoModule`. Requires `vendor_hash`. | E |
| `vendor_hash` | string (sha256 SRI) | Fixed-output hash of the Go module's vendor directory. Required when `go_build: true`. | E |
| `mod_root` | string | Directory inside the flake input that contains `go.mod`. Default `"./"`. | E |

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

Additional source files beyond the standard `*_interface.h`, `*_plugin.h`, `*_plugin.cpp`.

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
