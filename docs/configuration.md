# Module Configuration Reference

This document describes all available fields in `metadata.json` — the single configuration file for a Logos module. 

## Basic Structure

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

### `display_name`
**Type:** string
**Default:** falls back to `name`

Human-readable label shown in UIs (Package Manager, App Manager, `lm metadata`,
`lgx manifest`). When unset, consumers fall back to `name`, so older modules
keep working unchanged.

```json
"display_name": "My Module"
```

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
**Default:** `"legacy"` (the value the parser fills in when the field is absent)

Selects the authoring model. When set to `"universal"`, you write only an impl
class in `src/<name>_impl.{h,cpp}` deriving `LogosModuleContext`; the builder
derives a LIDL contract from that header and generates
`<name>_cdylib_glue.{h,cpp}` (the Qt plugin, carrying `Q_PLUGIN_METADATA`) plus
`<name>_module_impl.cpp` / `<name>_types.h` (the Qt-free C ABI around your impl).
This is the model used by all C++ templates.

- `"universal"` — glue generated from your impl header, impl class is the API (recommended)
- `"cdylib"` — the module already exports the module-impl C ABI (a Rust crate, or
  C++ compiled to the same shape); only the uniform Qt glue is generated, from a
  contract you name in `codegen.lidl`
- `"legacy"` / omitted — no glue is generated at all. Correct for a `ui_qml` view
  plugin or a test-only fixture; **refused at evaluation** for a `core` module
  that declares `main`, because such a module would build green and then be
  un-callable from every consumer

> The hand-written `<name>_interface.h` + `<name>_plugin.{h,cpp}` pair that
> `"legacy"` used to imply is no longer a way to ship a core module — that is
> what the refusal above is for. Legacy `type: "ui"` widget modules are
> unaffected.

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
| `impl_class` | `universal` (and optionally `cdylib`) | Impl class name (default PascalCase of `<name>` + `Impl`). On `cdylib` it is what opts a C++ module into also generating the C-ABI export wrapper |
| `lidl` | `cdylib` | Path to the committed LIDL contract. **Required** for `interface: "cdylib"` unless `codegen.rust.trait` derives one |
| `rust` | `cdylib` | `{ "trait": "..." }` — derive the contract from a Rust trait instead of committing a `.lidl` |
| `rep` | `ui_qml` + `universal` | Path to the `.rep` QtRO contract for a C++ UI backend |
| `consumer_api_style` | `universal` / `cdylib` | Type surface of the generated `modules().<dep>` wrappers: `"lp"` (Qt-free, the default there) or `"qt"` |

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

#### `codegen.consumer_api_style`

Two independent axes meet in a module: the surface it PROVIDES (`interface`)
and the surface it CONSUMES its dependencies through. This key names the second
one, and only the second one — setting it changes nothing about the module's own
API or its contract.

The default is derived and matches what the build always did:

| Module shape | Default | Wrappers |
|--------------|---------|----------|
| `interface: "universal"` (`type` other than `ui_qml`) | `lp` | `std::string` / `int64_t`, calling the logos-protocol C ABI |
| `interface: "cdylib"` | `lp` | as above |
| `interface: "universal"` + `type: "ui_qml"` | `qt` | `QString` / `qlonglong`, bound through the backend's `LogosAPI` |
| omitted `interface` (hand-written Qt) | `qt` | as above |

Only ONE override is accepted, and it is the reason the key exists: a module
packaged as a cdylib provider may ask for `"qt"`.

```json
"interface": "universal",
"codegen": { "consumer_api_style": "qt" }
```

That module keeps its Qt-free PROVIDER surface — the std-typed impl header, the
derived LIDL contract, the generated `logos_module_impl.h` C ABI — while
`modules().<dep>` hands out Qt-typed wrappers. Those wrappers hold no
`LogosAPI`: the umbrella is default-constructible and bakes `metadata.json#name`
as the call origin, which each wrapper threads into
`logos::qt::LpBridge::forOrigin(origin, target)`.

The reverse — asking a Qt PLUGIN (a hand-written module, or a `ui_qml` backend)
for `"lp"` — is **refused at evaluation**, by name. Both LogosAPI-free wrapper
flavours rely on something else populating the `TokenManager` their lp client
reads. A cdylib image gets that over the C ABI (`logos_module_accept_token` →
`lp_token_save`); a Qt plugin image does not — the host writes tokens to the
`TokenManager` in its OWN image, and only `logos::qt::LpBridge::syncTokens`
(installed exclusively by the LogosAPI-taking `forTarget`) mirrors them across.
Without that mirror every outbound call presents an empty auth token and comes
back as a default value with no error raised.

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

Relative path to the module icon. **Must be a PNG, exactly 256x256.** The bundler stages it once at `assets/icon.png` inside the `.lgx` (variant-independent, so hosts can display it without unpacking a platform build) and the build system also copies it into the standalone app plugin directory. **Required for `type: ui_qml`** at manifest version 0.4.0+; optional for `core` modules, which render no tile. A non-conforming icon fails the build with the expected/actual dimensions named. Convention: `src/icons/<module_name>.png`.

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
    "runtime": ["zstd"]
  }
}
```

List only what the module actually links against or `dlopen`s. Every entry is
evaluated for the *target* platform, so an unused package can break a cross
build even though it is harmless natively — a package whose closure is not
available for the target makes the whole module fail to evaluate.

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

## Platform-Specific Fields (`"platforms"`)

Some fields differ per target. A module may declare an **ordered list** of
selector-keyed overlays, at the top level and inside the `"nix"` block:

```json
{
  "name": "my_module",
  "include": [],

  "platforms": [
    { "when": { "os": "linux" },   "include": ["libcore.so"] },
    { "when": { "os": "darwin" },  "include": ["libcore.dylib"] },
    { "when": { "os": "windows" }, "include": ["libcore.dll"] }
  ],

  "nix": {
    "packages": { "runtime": ["nlohmann_json"] },
    "platforms": [
      { "when": { "os": "linux" },
        "packages": { "runtime": ["krb5"] } }
    ]
  }
}
```

Note the **empty base** for `include`, and the Linux `.so` sitting in an overlay
alongside the other two. That is not stylistic. **Lists concatenate**, so
writing the `.so` in the base —

```json
"include": ["libcore.so"],
"platforms": [ { "when": { "os": "darwin" }, "include": ["libcore.dylib"] } ]
```

— resolves on darwin to `["libcore.so", "libcore.dylib"]`: a cross-platform
superset, which is the exact thing this feature exists to eliminate. `libcore.so`
is not a default that darwin happens to add to, it is the **Linux value**, so it
belongs in the Linux overlay. A value belongs in the base only when it is
genuinely correct on every target.

The base still carries everything that does not vary — `nix.packages.runtime`
above keeps `nlohmann_json` on all targets and gains `krb5` on Linux only.

### The selector (`when`)

| Key | Reachable values |
|---|---|
| `os` | `linux`, `darwin`, `windows` |
| `architecture` | `x86_64`, `aarch64` |
| `abi` | `gnu`, `unknown` |

Each key is **independently optional**: `os` alone selects every architecture on
that OS, `architecture` alone selects that architecture everywhere, and all
three together name one variant. An **empty `when` is an error** — an overlay
that matched everything would just be the base config.

Common aliases are accepted and canonicalised: `arm64` → `aarch64`, `macos` →
`darwin`, `win32` → `windows`. **An unrecognised or unreachable value is an
error, not a non-match** — a selector that could never fire is always a bug, and
finding it at eval time is the entire point of the feature.

Two things about `abi` are worth knowing before you use it:

* The Windows target is **mingw** (`x86_64-w64-mingw32`), so its `abi` is `gnu`,
  not `msvc`.
* Because of that, `abi` is **not** an OS discriminator: `{"abi": "gnu"}` alone
  matches x86_64-linux, aarch64-linux **and** the Windows cross. Say
  `{"os": "windows"}` if that is what you mean.

### How overlays merge

**Every** matching overlay applies, in **declaration order**:

| Shape | Rule |
|---|---|
| list | base ++ overlay₁ ++ overlay₂ … (**no dedup**) |
| scalar (string/number/bool) | last matching overlay wins |
| object | merged key by key; base-only keys survive |
| `null` in an overlay | **error** — there is no removal operator; restructure the base |
| type mismatch with the base | **error** |

Objects **recurse** rather than overwrite, and that is worth being explicit
about because "scalars and objects overwrite" is the simpler rule and it is the
wrong one. Every overlay-able key under `nix` *is* an object — `packages` is
`{build, runtime}`, `cmake` is four lists, `rust` is `{packages, env,
toolchain}` — so whole-object overwrite would make

```json
"packages": { "build": ["pkg-config"], "runtime": ["nlohmann_json"] },
"platforms": [ { "when": {"os":"linux"}, "packages": { "runtime": ["krb5"] } } ]
```

silently **drop** `packages.build` and the base `runtime` entry on Linux. It
would also make "lists concatenate" unreachable for the whole `nix` block: no
list is ever a direct child of `packages`/`cmake`/`rust`, so the merge would
never descend far enough to meet one. Recursion is what lets the two rules
compose — descend through the objects, apply the list/scalar rule at the leaf
where the author actually wrote a value.

Ordering is **declaration** order, never specificity. Write the general entry
first and the specific one last — reversing these two genuinely reverses the
answer, and nothing will warn you:

```json
"nix": {
  "platforms": [
    { "when": { "os": "windows" }, "rust": { "toolchain": "1.95.0" } },
    { "when": { "os": "windows", "architecture": "x86_64", "abi": "gnu" },
      "rust": { "toolchain": "1.96.0" } }
  ]
}
```

### What may vary by platform

| Level | Fields |
|---|---|
| top level | `include` |
| inside `nix` | `packages`, `external_libraries`, `cmake`, `rust` |

Anything else is refused, and the refusals are deliberate:

* `name`, `version`, `type`, `interface` are module **identity** and select the
  build backend — they are read before a target is even chosen.
* `codegen`, `interface_dependencies`, `dependency_overrides` decide the
  generated **contract**. A Linux consumer calling a Windows provider built from
  a different contract is an interface-hash mismatch at runtime.
* `host_services` is a **security** declaration checked against a hardcoded
  allowlist. A privilege set that varies by platform means auditing one build
  tells you nothing about the other.
* `concurrency` — the author owns thread safety for `"multi"`; correctness must
  not depend on which host produced the binary.
* `icon`, `view`, `category`, `description` are pure manifest fields resolved on
  the installing machine.

`main` and `dependencies` are refused for a **different** reason, and the
distinction matters if you were about to work around it: they are not refused on
principle — a per-target `main` is a coherent thing to want — but because
resolving them today would change the **build** and not the **shipped module**.

The metadata.json that ships is the **source file, copied verbatim**:
`mkLogosQmlModule` does `cp <configFile> $out/lib/metadata.json`, and the core
path embeds the same source file via `configure_file` + `Q_PLUGIN_METADATA`.
Nothing between the parse and the artifact ever writes the resolved tree back
out. So a platform-keyed `main` would build one plugin and ship a manifest naming
another; and a platform-keyed `dependencies` would be resolved for the flake
inputs while the `LogosModules` umbrella — generated at build time by
`logos-plugin-qt/lib/buildPlugin.nix` straight out of the raw `dependencies`
array in that file — carried the base list, so an overlay-added dependency would
be built and linked and then have no member on `modules()`.

Both become admissible once the build tree carries the resolved tree: the jq
stamp in `lib/modulePreConfigure.nix` (the one that already splices
`logos_protocol_version` in) also splicing the resolved values and doing
`del(.platforms)`, and `mkLogosQmlModule` copying that stamped file rather than
the source. Until then, put the value in the base — a plugin's file **extension**
is already handled centrally by `common.getPluginFilename`, which is the case a
per-target `main` would otherwise serve.

`nix.external_libraries` is a list of **objects folded by `name`**. Overlays
concatenate, so declaring the same `name` in both the base and a matching
overlay is refused — move the whole entry into the overlays that want it.

### Caveats

* A `platforms` key is read from **exactly two places**: the top level and
  `nix`. Writing one anywhere else — `nix.packages.platforms`,
  `nix.rust.platforms`, inside an `external_libraries` entry — is a **hard
  error** naming the path, rather than an overlay that is quietly skipped.
* `include` is safe to platform-key because it is purely a build-time staging
  list, read once by `mkLogosModule` and by nothing at runtime. The shipped
  manifest still contains the unresolved `include` and the `platforms` list
  itself; no runtime reader looks at either.
* `nix.cmake.*` is parsed and resolved but **not yet consumed by any build
  code**. A `cmake.extra_link_libraries` overlay configures nothing today.

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
      "runtime": ["zstd"]
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
