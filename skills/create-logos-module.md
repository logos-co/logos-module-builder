# Create Logos Module Skill

Use this skill when the user wants to create a new Logos module. This skill guides you through creating a complete **core** module using logos-module-builder's **universal authoring model**.

## When to Use

- User asks to "create a new Logos module"
- User wants to "build a module for Logos"
- User needs to "add a new plugin to Logos"
- User wants to "wrap a library for Logos"

## The Universal Authoring Model

In the universal model you write **only an implementation class** — `src/{module_name}_impl.{h,cpp}`. Its public methods *are* the module's API: callable by other modules and from the CLI (`logoscore -c`). Everything else is **generated** from your impl header by logos-module-builder:

- the `{module_name}_interface.h` interface class
- the `{module_name}_plugin.{h,cpp}` plugin class
- `Q_PLUGIN_METADATA`, `Q_OBJECT`, `Q_INVOKABLE`, `initLogos`, and all the Qt glue

Key rules:

1. `metadata.json` sets `"interface": "universal"`. Keep `type: "core"`, `main: "{module_name}_plugin"`, `dependencies`, and the `nix` block.
2. Your impl class derives `LogosModuleContext` (include `"logos_module_context.h"`). **No** `Q_OBJECT`, **no** `Q_INVOKABLE`, **no** interface class, **no** plugin class — those are generated.
3. **Module code is Qt-free**: use `std::string` and friends, never `QString`.
4. Declare events in a `logos_events:` section as plain methods; calling the method emits the event.
5. Call dependencies through `modules()` (typed callers from `metadata.json#dependencies`); override `onContextReady()` for one-time setup.

## Prerequisites

The module will use `logos-module-builder` from `github:logos-co/logos-module-builder`. The fastest start is the template:

```bash
mkdir logos-{name}-module && cd logos-{name}-module
nix flake init -t github:logos-co/logos-module-builder
# For modules wrapping an external C/C++ library, use the external-lib template:
# nix flake init -t github:logos-co/logos-module-builder#with-external-lib
```

This skill documents the same files the template produces, in case you are creating them by hand.

## Step 1: Gather Requirements

Ask the user for:

1. **Module name** (required): Should be snake_case, e.g., `my_module`, `wallet_module`
2. **Description**: What the module does
3. **Category**: e.g., `network`, `chat`, `wallet`, `storage`, `general`
4. **Dependencies**: Other Logos modules this depends on (e.g., `waku_module`)
5. **External libraries**: Any C/C++ libraries to wrap
6. **API methods**: What public methods the impl class should expose

## Step 2: Create Directory Structure

Create the module directory with this structure:

```
logos-{name}-module/
├── flake.nix
├── metadata.json
├── CMakeLists.txt
├── src/                    # Source files — ONLY the impl class
│   ├── {name}_impl.h
│   └── {name}_impl.cpp
└── (optional) lib/         # For external libraries
```

The interface and plugin classes are generated at build time — do **not** create them.

## Step 3: Create metadata.json

```json
{
  "name": "{module_name}",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
  "category": "{category}",
  "description": "{description}",
  "main": "{module_name}_plugin",
  "dependencies": [],

  "nix": {
    "packages": {
      "build": [],
      "runtime": []
    },
    "external_libraries": [],
    "cmake": {
      "find_packages": [],
      "extra_sources": [],
      "extra_include_dirs": [],
      "extra_link_libraries": []
    }
  }
}
```

`"interface": "universal"` is what tells the builder to generate the plugin glue from your impl class.

## Step 4: Create flake.nix

flake.nix is unchanged from the classic model — it still just calls `mkLogosModule`.

### Basic Module (no dependencies)

```nix
{
  description = "{Module description}";

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

### With Module Dependencies

Add dependencies as flake inputs — they are resolved automatically from `dependencies` in `metadata.json`:

```nix
{
  description = "{Module description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    waku_module.url = "github:logos-co/logos-waku-module";  # input name must match dependency name in metadata.json
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;  # waku_module resolved automatically from dependencies[]
    };
}
```

### With External Library (build from source)

Use when the library needs to be built from source code:

```nix
{
  description = "{Module description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    mylib-src = {
      url = "github:org/mylib";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        mylib = inputs.mylib-src;
      };
    };
}
```

## Step 5: Create CMakeLists.txt

No more `module_config.h` boilerplate. Just point `logos_module()` at your impl sources — the generated glue is compiled automatically.

```cmake
cmake_minimum_required(VERSION 3.14)
project({ModuleName}Plugin LANGUAGES CXX)

# Include the Logos Module CMake helper.
# For nix builds, this is provided via LOGOS_MODULE_BUILDER_ROOT.
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Define the module. The generated glue is compiled automatically.
logos_module(
    NAME {module_name}
    SOURCES
        src/{module_name}_impl.h
        src/{module_name}_impl.cpp
    # Uncomment and modify as needed:
    # EXTERNAL_LIBS
    #     mylib
    # FIND_PACKAGES
    #     Protobuf
    # PROTO_FILES
    #     src/message.proto
)
```

## Step 6: Create the Impl Header

Create `src/{module_name}_impl.h`. This is the heart of the module — its public methods are the API. The class derives `LogosModuleContext` and stays Qt-free.

```cpp
#pragma once

#include <string>
#include "logos_module_context.h"

/**
 * @brief {Description of what this module does}.
 *
 * Universal authoring model: you write only this impl class. Its public
 * methods ARE the module's API — callable by other modules and from the CLI
 * (`logoscore -c`). The Qt plugin glue (the *Plugin / *Interface classes,
 * Q_PLUGIN_METADATA, initLogos wiring) is generated from this header by
 * logos-module-builder.
 *
 * Deriving LogosModuleContext gives you:
 *   - modules()        — typed callers for anything in metadata.json#dependencies
 *   - typed event subscriptions (modules().<dep>.on<Event>(...))
 *   - onContextReady() — override to run once the module is wired
 *
 * Module code is Qt-free: use std::string and friends, not QString.
 */
class {ModuleName}Impl : public LogosModuleContext
{
public:
    /// {Method description}.
    std::string exampleMethod(const std::string& input);

    /// {Method description}.
    std::string getStatus();

logos_events:
    /// Emitted by exampleMethod(). Other modules subscribe with
    /// modules().{module_name}.onExampleDone(...).
    void exampleDone(const std::string& result);

protected:
    // Override to run one-time setup once the context (instancePersistencePath()
    // etc.) and dependency wiring are ready. Optional — omit if unneeded.
    void onContextReady() override;
};
```

Notes:
- Public methods become the module's RPC API automatically — no annotations needed.
- Use `std::string` for string params (`const std::string&`) and return values; primitives pass by value (`int64_t`, `bool`, `double`).
- `LogosModuleContext` also provides `modulePath()`, `instanceId()`, and `instancePersistencePath()` (a per-instance, host-owned writable data dir; empty when run outside a host, so null-check before use).

## Step 7: Create the Impl Implementation

Create `src/{module_name}_impl.cpp`. Include `"logos_sdk.h"` here (not in the header) whenever you call `modules()` — it is generated at build time and pulls in codegen types you want to keep out of the parsed header.

```cpp
#include "{module_name}_impl.h"

// Generated at build time by logos-cpp-generator. Defines `LogosModules`
// with one std-typed accessor per metadata.json dependency. Include it only
// in the .cpp so the impl header the generator parses stays Qt/codegen-free.
// (Only needed when you call modules() — omit otherwise.)
#include "logos_sdk.h"

void {ModuleName}Impl::onContextReady()
{
    // instancePersistencePath() / instanceId() / modulePath() are populated now.
    // Arm event subscriptions and do one-time per-instance setup here.
}

std::string {ModuleName}Impl::exampleMethod(const std::string& input)
{
    std::string result = "Processed: " + input;

    // Calling the event method emits it to every subscriber.
    exampleDone(result);

    return result;
}

std::string {ModuleName}Impl::getStatus()
{
    return "{module_name} is running.";
}
```

## Step 8: Build and Test

```bash
# Track all files (Nix only sees git-tracked files)
git init && git add -A

# Build the module
nix build

# Check outputs
ls -la result/lib/
ls -la result/include/

# Inspect the generated plugin (metadata + the methods from your impl class)
lm ./result/lib/{module_name}_plugin.so
lm methods ./result/lib/{module_name}_plugin.so --json

# Run it and call a method
logoscore -m ./result/lib -l {module_name} -c "{module_name}.exampleMethod(hi)"

# Enter development shell
nix develop
```

## Naming Conventions

When replacing placeholders:

| Placeholder | Example |
|-------------|---------|
| `{module_name}` | `wallet_module` |
| `{ModuleName}Impl` | `WalletModuleImpl` |
| `{ModuleName}` | `WalletModule` |
| `{MODULE_NAME}` | `WALLET_MODULE` |
| `{category}` | `wallet` |
| `{description}` | `Wallet integration module` |

## Adding External Library Support

### Option 1: Pre-built / Vendored Library in Source (simplest)

Use when you have a pre-built library binary (or vendored sources) to include in your repo.

1. Place library files in `lib/` and git-track them:
```bash
git add lib/libmylib.dylib lib/libmylib.h
```

2. Add to `metadata.json`:
```json
"nix": {
  "external_libraries": [{ "name": "mylib", "vendor_path": "lib" }],
  "cmake": { "extra_include_dirs": ["lib"] }
}
```

3. Add to `CMakeLists.txt`:
```cmake
logos_module(
    NAME {module_name}
    SOURCES
        src/{module_name}_impl.h
        src/{module_name}_impl.cpp
    EXTERNAL_LIBS
        mylib
)
```

4. Include and call the library from the impl (`.h` for the header, `.cpp` for the calls):
```cpp
// in src/{module_name}_impl.h
#include "lib/libmylib.h"

// in src/{module_name}_impl.cpp — wrap the C API behind std-typed methods
std::string {ModuleName}Impl::processData(const std::string& input)
{
    const char* out = mylib_process(m_handle, input.c_str());
    std::string result(out);
    mylib_free_string(out);   // don't forget to free!
    return result;
}
```

Keep the external library's C API confined to the impl; expose only `std::string`/primitive methods to the rest of Logos.

### Option 2: Build from Source (flake_input + externalLibInputs)

See "With External Library" in Step 4 above.

**Decision guide:**
| Approach | When to Use |
|----------|-------------|
| `vendor_path` | Pre-built binaries / vendored sources already in repo |
| `externalLibInputs` | Build from source, pin via flake input |

## Calling Other Modules

Deriving `LogosModuleContext` gives you `modules()` — typed callers, one per entry in `metadata.json#dependencies`. Include `"logos_sdk.h"` in the `.cpp` to make the type complete.

```cpp
#include "logos_sdk.h"

std::string {ModuleName}Impl::doWork(int64_t a, int64_t b)
{
    // Synchronous typed call — no raw LogosAPI, no QVariant.
    auto& waku = modules().waku_module;
    waku.initWaku("{}");

    // Compose several calls. Return types match the dependency's methods.
    int64_t sum = modules().calc_module.add(a, b);
    return std::to_string(sum);
}
```

Async calls use the generated `<method>Async(args..., callback)` overload — it returns immediately and delivers the reply to your callback on this module's event loop:

```cpp
std::string {ModuleName}Impl::startAsync(int64_t n)
{
    modules().calc_module.fibonacciAsync(n, [this](int64_t value) {
        m_lastResult = value;
    });
    return "queued";
}
```

> Legacy path (still available): you can drop to the raw client with
> `logosAPI->getClient("waku_module")->invokeRemoteMethod("waku_module", "initWaku", "{}")`,
> but prefer the typed `modules()` form above.

## Emitting Events

Declare typed events in a `logos_events:` section of the impl header — they are plain method signatures. String params take `const std::string&`; primitives pass by value.

```cpp
// in src/{module_name}_impl.h
logos_events:
    void greeted(const std::string& greeting);
    void ticked(int64_t count);
```

Emit an event by **calling the method** — the generated body routes the typed payload to every subscriber:

```cpp
// in src/{module_name}_impl.cpp
std::string {ModuleName}Impl::greet(const std::string& name)
{
    std::string greeting = "Hello, " + name + "!";
    greeted(greeting);     // emits the typed `greeted` event
    return greeting;
}
```

### Subscribing to a dependency's events

Other modules subscribe with `modules().<dep>.on<Event>(...)` — the accessor is `on` + the capitalized event name, and the callback's argument types match the event. Arm subscriptions in `onContextReady()`:

```cpp
void {ModuleName}Impl::onContextReady()
{
    modules().{dep_module}.onGreeted([this](const std::string& greeting) {
        m_lastGreeting = greeting;
    });
}
```

## Final Checklist

- [ ] `metadata.json` has `"interface": "universal"`, correct name, `type: "core"`, and dependencies
- [ ] `flake.nix` imports logos-module-builder correctly with `flakeInputs = inputs`
- [ ] `CMakeLists.txt` lists `src/{module_name}_impl.h` and `src/{module_name}_impl.cpp` (no interface/plugin files)
- [ ] Impl class derives `LogosModuleContext` and includes `"logos_module_context.h"`
- [ ] No `Q_OBJECT` / `Q_INVOKABLE` / `QString` in the impl — module code is Qt-free
- [ ] Public impl methods cover the intended API; events declared under `logos_events:`
- [ ] Cross-module calls use `modules().<dep>...` with `"logos_sdk.h"` included in the `.cpp`
- [ ] External libraries (if any) are in `lib/` and git-tracked, wrapped behind std-typed impl methods
- [ ] Build succeeds with `nix build`; `lm` shows your methods and `logoscore -c` can call them
