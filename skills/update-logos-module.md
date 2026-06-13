# Update Logos Module Skill

Use this skill when the user wants to modify or update an existing Logos module. This covers adding methods, dependencies, external libraries, and migrating legacy modules.

## When to Use

- User asks to "add a method to a module"
- User wants to "add a dependency to a module"
- User needs to "wrap a new library in an existing module"
- User wants to "migrate a module to use logos-module-builder"
- User asks to "update module configuration"

## Understanding Module Structure

A **universal** core module (`metadata.json` has `"interface": "universal"`) using logos-module-builder has this structure:

```
logos-{name}-module/
├── flake.nix              # Nix flake configuration
├── metadata.json          # Module configuration (runtime + Nix build)
├── CMakeLists.txt         # CMake build file
├── src/                   # Source files
│   ├── {name}_impl.h      # the impl class — its public methods ARE the API
│   └── {name}_impl.cpp
└── lib/                   # External libraries (optional, git-tracked)
```

In the universal model you write **only** the implementation class `src/{name}_impl.{h,cpp}`,
a class deriving `LogosModuleContext` (Qt-free — use `std::string`, not `QString`). Its public
methods *are* the module's API: callable by other modules and from the CLI (`logoscore -c`).
There is **no** interface class and **no** plugin class — `{name}_interface.h`,
`{name}_plugin.{h,cpp}`, `Q_PLUGIN_METADATA`, and `initLogos` wiring are all **generated**
from your impl header by logos-module-builder.

> **Legacy modules** (no `"interface": "universal"`, using `initLogos`) instead have a
> hand-written `{name}_interface.h` + `{name}_plugin.{h,cpp}` with `Q_INVOKABLE` methods. If you
> are working on one of those, edit the plugin/interface classes. Everything below leads with the
> universal model.

## Task 1: Add a New Method

A universal module's API is simply the public methods of its impl class. Adding a method is a
two-file edit on `src/{module_name}_impl.{h,cpp}` — plain C++ with `std` types, **no**
`Q_INVOKABLE`, no interface, no plugin. The generated glue picks it up automatically.

### Step 1: Declare the Method in the Impl Header

In `src/{module_name}_impl.h`, add the declaration to the impl class:

```cpp
class {ModuleName}Impl : public LogosModuleContext
{
public:
    // Existing methods...

    /// Brief description of what the method does.
    {ReturnType} newMethod(const std::string& param);
};
```

Use `std` types (`std::string`, `int`, `bool`, `int64_t`, ...) — module code is Qt-free. Take
string parameters as `const std::string&`; pass primitives by value.

### Step 2: Implement the Method

In `src/{module_name}_impl.cpp`, add the implementation:

```cpp
{ReturnType} {ModuleName}Impl::newMethod(const std::string& param)
{
    // Implementation logic here
    return result;
}
```

If the method also announces a typed event, declare that event in a `logos_events:` section and
call it (see Task 7).

### Step 3: Rebuild

```bash
nix build
```

## Task 2: Add a Module Dependency

### Step 1: Update metadata.json

```json
{
  "dependencies": ["existing_module", "new_module"]
}
```

### Step 2: Update flake.nix

Add the new module as a flake input — it will be auto-resolved from `dependencies`:

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    new_module.url = "github:logos-co/logos-new-module";  # input name must match dependency name in metadata.json
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;  # new_module resolved automatically from dependencies[]
    };
}
```

### Step 3: Use the Dependency in Code

Deriving `LogosModuleContext` gives you `modules()` — typed callers, one per entry in
`metadata.json#dependencies`. Include the generated `"logos_sdk.h"` umbrella in the `.cpp` (not
the header) to make those types complete, then call methods directly:

```cpp
// in src/{module_name}_impl.cpp
#include "{module_name}_impl.h"
#include "logos_sdk.h"   // generated: defines LogosModules behind modules()

void {ModuleName}Impl::someMethod()
{
    auto result = modules().new_module.someMethod(arg1, arg2);
}
```

## Task 3: Add an External Library

### Approach A: Pre-built Library in Source (vendor_path)

Use when you have a pre-built library binary to include in your repo.

1. Place library files in `lib/` and git-track them:
```bash
cp /path/to/libnewlib.dylib lib/
git add lib/libnewlib.dylib lib/libnewlib.h
```

2. Update `metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      { "name": "newlib", "vendor_path": "lib" }
    ],
    "cmake": {
      "extra_include_dirs": ["lib"]
    }
  }
}
```

3. `flake.nix` needs no changes (no extra inputs for vendor libs).

### Approach B: Build Library from Source (flake_input)

Use when the library needs to be built from source code.

`metadata.json`:
```json
{
  "nix": {
    "external_libraries": [
      {
        "name": "newlib",
        "build_command": "make shared"
      }
    ]
  }
}
```

`flake.nix`:
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    newlib-src = {
      url = "github:org/newlib";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        newlib = inputs.newlib-src;
      };
    };
}
```

### Step: Update CMakeLists.txt

```cmake
logos_module(
    NAME {module_name}
    SOURCES ...
    EXTERNAL_LIBS
        existing_lib
        newlib
)
```

### Step: Add Library Header and Use

Place header in `lib/libnewlib.h` (if not already there).

In the impl class:
```cpp
// in src/{module_name}_impl.h
#include "lib/libnewlib.h"

class {ModuleName}Impl : public LogosModuleContext {
private:
    newlib_handle* m_newlibHandle = nullptr;
};

// in src/{module_name}_impl.cpp
void {ModuleName}Impl::initNewLib()
{
    m_newlibHandle = newlib_init();
}
```

## Task 4: Add Protobuf Support

### Step 1: Create Proto File

Create `src/protobuf/message.proto`:

```protobuf
syntax = "proto3";

package {module_name};

message MyMessage {
    string id = 1;
    string content = 2;
    int64 timestamp = 3;
}
```

### Step 2: Update metadata.json

```json
{
  "nix": {
    "packages": {
      "build": ["protobuf", "abseil-cpp"]
    },
    "cmake": {
      "find_packages": ["Protobuf", "Threads"],
      "extra_sources": []
    }
  }
}
```

### Step 3: Update CMakeLists.txt

```cmake
logos_module(
    NAME {module_name}
    SOURCES ...
    FIND_PACKAGES
        Protobuf
        Threads
    PROTO_FILES
        src/protobuf/message.proto
)
```

### Step 4: Use in Code

```cpp
// in src/{module_name}_impl.cpp
#include "message.pb.h"

void {ModuleName}Impl::processMessage(const std::string& data)
{
    {module_name}::MyMessage msg;
    msg.ParseFromString(data);

    // msg.id() is already a std::string
}
```

## Task 5: Migrate Legacy Module to logos-module-builder

### Step 1: Analyze External Libraries

Check how external libraries are obtained in the legacy flake.nix:

1. **Pre-built in lib/ directory** → Use `vendor_path: "lib"` (simplest, no extra flake inputs)
2. **Built from source flake input** → Use `externalLibInputs`

### Step 2: Create metadata.json

Extract configuration from existing files and merge into a single `metadata.json`:

```json
{
  "name": "{module_name}",
  "version": "1.0.0",
  "type": "core",
  "interface": "universal",
  "category": "{category}",
  "description": "{from README or docs}",
  "main": "{module_name}_plugin",
  "dependencies": ["waku_module"],

  "nix": {
    "packages": {
      "build": ["protobuf"],
      "runtime": ["zstd"]
    },
    "external_libraries": [
      { "name": "libwaku", "vendor_path": "lib" }
    ],
    "cmake": {
      "find_packages": ["Protobuf"],
      "extra_sources": ["src/helper.cpp"],
      "extra_include_dirs": ["lib"]
    }
  }
}
```

### Step 3: Simplify flake.nix

```nix
{
  description = "{Module description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add module dependencies as inputs
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

### Step 4: Simplify CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.14)
project({ModuleName}Plugin LANGUAGES CXX)

include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

logos_module(
    NAME {module_name}
    SOURCES
        src/{module_name}_impl.h
        src/{module_name}_impl.cpp
    EXTERNAL_LIBS
        libwaku
    FIND_PACKAGES
        Protobuf
)
```

### Step 5: Port Sources to the Impl Class

A migrated universal module keeps only `src/{module_name}_impl.{h,cpp}`. Fold the public API from
the old `{module_name}_interface.h` / `{module_name}_plugin.{h,cpp}` into a single impl class
deriving `LogosModuleContext`: drop `Q_OBJECT`/`Q_INVOKABLE`/`Q_PLUGIN_METADATA`/`initLogos`
(all generated), convert `QString` parameters and returns to `std::string`, and move any
`emit eventResponse(...)` calls to typed events under a `logos_events:` section (see Task 7).

```bash
mkdir -p src
# create src/{module_name}_impl.h and src/{module_name}_impl.cpp from the old plugin/interface
git rm -f {module_name}_interface.h {module_name}_plugin.h {module_name}_plugin.cpp 2>/dev/null || true
```

### Step 6: Delete nix/ Directory and old module.yaml

```bash
rm -rf nix/
rm -f module.yaml   # if it existed
```

### Step 7: Stage Files for Nix

**IMPORTANT:** Nix only sees git-tracked files. Stage new files before building:
```bash
git add metadata.json src/ flake.nix CMakeLists.txt
# Also track any pre-built libraries
git add lib/*.dylib lib/*.so 2>/dev/null || true
```

### Step 8: Test Build

```bash
nix build
ls -la result/lib/
```

## Task 6: Update Version

### Step 1: Update metadata.json

```json
{ "version": "2.0.0" }
```

For a universal module that is all you need — `metadata.json` is the single source of truth, and
the version is baked into the generated plugin glue at build time. (A legacy module would instead
update its hand-written `QString version() const override { return "2.0.0"; }`.)

## Task 7: Add a Typed Event

Universal modules use **typed events**: declare them as plain method signatures in a
`logos_events:` section of the impl header, then **call the method to emit**. The generated glue
turns the call into a typed dispatch to every subscriber. Use `std` types only.

### Step 1: Declare the Event

```cpp
// in src/{module_name}_impl.h
class {ModuleName}Impl : public LogosModuleContext
{
public:
    std::string greet(const std::string& name);

logos_events:
    /// Emitted by greet() with the greeting it produced. Subscribers use
    /// modules().{module_name}.onGreeted(...).
    void greeted(const std::string& greeting);
};
```

### Step 2: Emit by Calling the Method

```cpp
// in src/{module_name}_impl.cpp
std::string {ModuleName}Impl::greet(const std::string& name)
{
    std::string greeting = "Hello, " + name + "!";
    greeted(greeting);   // emits the typed event to all subscribers
    return greeting;
}
```

### Subscribing from Another Module

Other modules subscribe with `modules().<dep>.on<Event>(...)` — the accessor is `on` + the
capitalized event name, and the callback's argument types match the event. Arm subscriptions in
`onContextReady()`, the impl's one-time wired-up hook (declare `void onContextReady() override;`
in the header):

```cpp
// in the consuming module's src/{consumer}_impl.cpp
#include "logos_sdk.h"

void {ConsumerName}Impl::onContextReady()
{
    modules().{module_name}.onGreeted([this](const std::string& greeting) {
        // handle greeting
    });
}
```

## Task 8: Add Nix Package Dependency

### Update metadata.json

```json
{
  "nix": {
    "packages": {
      "build": ["existing_pkg", "new_package"],
      "runtime": ["runtime_pkg"]
    }
  }
}
```

If it's a CMake package, also update `CMakeLists.txt`:
```cmake
logos_module(
    NAME {module_name}
    SOURCES ...
    FIND_PACKAGES
        NewPackage
)
```

## Common Patterns

### Async Method with Callback

```cpp
// in src/{module_name}_impl.h
void asyncOperation(const std::string& input);

logos_events:
    void asyncComplete(int result, const std::string& data);

// in src/{module_name}_impl.cpp
void {ModuleName}Impl::asyncOperation(const std::string& input)
{
    external_lib_async(input.c_str(), asyncCallback, this);
}

static void asyncCallback(int result, const char* data, void* user_data)
{
    auto* impl = static_cast<{ModuleName}Impl*>(user_data);
    impl->asyncComplete(result, std::string(data));   // emits the typed event
}
```

### Method Calling Another Module

```cpp
// in src/{module_name}_impl.cpp
#include "logos_sdk.h"

std::string {ModuleName}Impl::methodUsingWaku(const std::string& message)
{
    auto result = modules().waku_module.relayPublish(
        "/default/topic", message, "/content/topic"
    );
    return result;
}
```

### Error Handling

```cpp
// in src/{module_name}_impl.cpp
std::string {ModuleName}Impl::riskyMethod(const std::string& input)
{
    char* error = nullptr;
    void* result = external_lib_call(input.c_str(), &error);

    if (error) {
        std::string errorMsg(error);
        external_lib_free_string(error);
        // surface failures via a typed event or LogosResult, not eventResponse
        return std::string();
    }

    std::string output = processResult(result);
    external_lib_free(result);
    return output;
}
```

## Verification Checklist

After any update:

- [ ] `metadata.json` is valid JSON with correct name, type, `"interface": "universal"`, and dependencies
- [ ] `flake.nix` uses `flakeInputs = inputs` and deps are auto-resolved
- [ ] External library binaries are present in `lib/` and git-tracked
- [ ] Impl class derives `LogosModuleContext` and includes `"logos_module_context.h"`
- [ ] New methods are plain C++ on the impl class (`std` types, no `Q_INVOKABLE`); no interface/plugin files
- [ ] Header declares public methods + any `logos_events:`; `.cpp` includes `"logos_sdk.h"` when it calls `modules()`
- [ ] `CMakeLists.txt` SOURCES lists only `src/{module_name}_impl.h` and `src/{module_name}_impl.cpp`
- [ ] Build succeeds: `nix build`
- [ ] Verify external libraries are copied: `ls -R result/lib/`
- [ ] Module loads and methods/events appear: `lm result/lib/{module_name}_plugin.so`
