# Update Logos Module Skill

Use this skill when the user wants to modify or update an existing Logos module. This covers adding methods, dependencies, external libraries, and migrating legacy modules.

## When to Use

- User asks to "add a method to a module"
- User wants to "add a dependency to a module"
- User needs to "wrap a new library in an existing module"
- User wants to "migrate a module to use logos-module-builder"
- User asks to "update module configuration"

## Understanding Module Structure

A module using logos-module-builder has this structure:

```
logos-{name}-module/
├── flake.nix              # Nix flake configuration
├── metadata.json          # Module configuration (Qt runtime + Nix build)
├── CMakeLists.txt         # CMake build file
├── src/                   # Source files
│   ├── {name}_interface.h
│   ├── {name}_plugin.h
│   └── {name}_plugin.cpp
└── lib/                   # External libraries (optional, git-tracked)
```

## Task 1: Add a New Method

### Step 1: Update Interface Header

In `src/{name}_interface.h`, add the method declaration:

```cpp
class {ModuleName}Interface : public PluginInterface
{
public:
    // Existing methods...

    Q_INVOKABLE virtual {ReturnType} newMethod({ParamType} param) = 0;
};
```

### Step 2: Update Plugin Header

In `src/{name}_plugin.h`, add the method declaration:

```cpp
class {ModuleName}Plugin : public QObject, public {ModuleName}Interface
{
    // ...existing code...

    Q_INVOKABLE {ReturnType} newMethod({ParamType} param) override;
};
```

### Step 3: Implement the Method

In `src/{name}_plugin.cpp`, add the implementation:

```cpp
{ReturnType} {ModuleName}Plugin::newMethod({ParamType} param)
{
    qDebug() << "{ModuleName}Plugin: newMethod called";

    // Implementation logic here

    emit eventResponse("new_method_completed", QVariantList() << param);

    return result;
}
```

### Step 4: Rebuild

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
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
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

```cpp
void {ModuleName}Plugin::someMethod()
{
    auto* client = m_logosAPI->getClient("new_module");
    QVariant result = client->invokeRemoteMethod("new_module", "someMethod", arg1, arg2);
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
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
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

In plugin:
```cpp
#include "lib/libnewlib.h"

class {ModuleName}Plugin {
private:
    newlib_handle* m_newlibHandle = nullptr;
};

// In implementation
void {ModuleName}Plugin::initNewLib()
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
#include "message.pb.h"

void {ModuleName}Plugin::processMessage(const QString& data)
{
    {module_name}::MyMessage msg;
    msg.ParseFromString(data.toStdString());

    qDebug() << "Message ID:" << QString::fromStdString(msg.id());
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
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
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
        src/{module_name}_interface.h
        src/{module_name}_plugin.h
        src/{module_name}_plugin.cpp
    EXTERNAL_LIBS
        libwaku
    FIND_PACKAGES
        Protobuf
)
```

### Step 5: Move Source Files (if needed)

If source files are in the root directory, move them to `src/`:
```bash
mkdir -p src
mv {module_name}_interface.h src/
mv {module_name}_plugin.h src/
mv {module_name}_plugin.cpp src/
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

### Step 2: Update Plugin Header

```cpp
QString version() const override { return "2.0.0"; }
```

## Task 7: Add Event Emission

```cpp
// Simple event
emit eventResponse("event_name", QVariantList() << "arg1" << "arg2");

// Event with complex data
QVariantMap data;
data["status"] = "success";
data["count"] = 42;
emit eventResponse("status_update", QVariantList() << QVariant(data));

// Event from callback (static method pattern)
static void callback(void* user_data, const char* msg) {
    auto* plugin = static_cast<{ModuleName}Plugin*>(user_data);
    emit plugin->eventResponse("callback_event",
        QVariantList() << QString::fromUtf8(msg));
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
// Interface
Q_INVOKABLE virtual void asyncOperation(const QString& input) = 0;

// Implementation
void {ModuleName}Plugin::asyncOperation(const QString& input)
{
    external_lib_async(input.toUtf8().constData(), asyncCallback, this);
}

static void asyncCallback(int result, const char* data, void* user_data)
{
    auto* plugin = static_cast<{ModuleName}Plugin*>(user_data);
    emit plugin->eventResponse("async_complete",
        QVariantList() << result << QString::fromUtf8(data));
}
```

### Method Calling Another Module

```cpp
QString {ModuleName}Plugin::methodUsingWaku(const QString& message)
{
    auto* waku = m_logosAPI->getClient("waku_module");
    QVariant result = waku->invokeRemoteMethod(
        "waku_module", "relayPublish",
        "/default/topic", message, "/content/topic"
    );
    return result.toString();
}
```

### Error Handling

```cpp
QString {ModuleName}Plugin::riskyMethod(const QString& input)
{
    char* error = nullptr;
    void* result = external_lib_call(input.toUtf8().constData(), &error);

    if (error) {
        QString errorMsg = QString::fromUtf8(error);
        external_lib_free_string(error);
        emit eventResponse("error", QVariantList() << errorMsg);
        return QString();
    }

    QString output = processResult(result);
    external_lib_free(result);
    return output;
}
```

## Verification Checklist

After any update:

- [ ] `metadata.json` is valid JSON with correct name, type, and dependencies
- [ ] `flake.nix` uses `flakeInputs = inputs` and deps are auto-resolved
- [ ] External library binaries are present in `lib/` and git-tracked
- [ ] All new methods in interface are `Q_INVOKABLE virtual`
- [ ] All interface methods are implemented in plugin
- [ ] Plugin header has matching declarations
- [ ] Build succeeds: `nix build`
- [ ] Verify external libraries are copied: `ls -R result/lib/`
- [ ] Plugin loads correctly in Logos Core
