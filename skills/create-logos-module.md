# Create Logos Module Skill

Use this skill when the user wants to create a new Logos module. This skill guides you through creating a complete module using logos-module-builder.

## When to Use

- User asks to "create a new Logos module"
- User wants to "build a module for Logos"
- User needs to "add a new plugin to Logos"
- User wants to "wrap a library for Logos"

## Prerequisites

The module will use `logos-module-builder` from `github:logos-co/logos-module-builder`.

## Step 1: Gather Requirements

Ask the user for:

1. **Module name** (required): Should be snake_case, e.g., `my_module`, `wallet_module`
2. **Description**: What the module does
3. **Category**: e.g., `network`, `chat`, `wallet`, `storage`, `general`
4. **Dependencies**: Other Logos modules this depends on (e.g., `waku_module`)
5. **External libraries**: Any C/C++ libraries to wrap
6. **API methods**: What methods should the module expose

## Step 2: Create Directory Structure

Create the module directory with this structure:

```
logos-{name}-module/
├── flake.nix
├── metadata.json
├── CMakeLists.txt
├── src/                    # Source files
│   ├── {name}_interface.h
│   ├── {name}_plugin.h
│   └── {name}_plugin.cpp
└── (optional) lib/         # For external libraries
```

## Step 3: Create metadata.json

```json
{
  "name": "{module_name}",
  "version": "1.0.0",
  "type": "core",
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

## Step 4: Create flake.nix

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

```cmake
cmake_minimum_required(VERSION 3.14)
project({ModuleName}Plugin LANGUAGES CXX)

# Include the Logos Module CMake helper
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Define the module
logos_module(
    NAME {module_name}
    SOURCES
        src/{module_name}_interface.h
        src/{module_name}_plugin.h
        src/{module_name}_plugin.cpp
    # Uncomment and modify as needed:
    # EXTERNAL_LIBS
    #     mylib
    # FIND_PACKAGES
    #     Protobuf
    # PROTO_FILES
    #     src/message.proto
)
```

## Step 6: Create Interface Header

Create `src/{module_name}_interface.h`:

```cpp
#ifndef {MODULE_NAME}_INTERFACE_H
#define {MODULE_NAME}_INTERFACE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include "interface.h"

/**
 * @brief Interface for the {ModuleName} module
 * 
 * {Description of what this module does}
 */
class {ModuleName}Interface : public PluginInterface
{
public:
    virtual ~{ModuleName}Interface() = default;

    // Define your module's public API here
    // Each method should be Q_INVOKABLE to be callable via RPC
    
    /**
     * @brief {Method description}
     * @param {param} {Param description}
     * @return {Return description}
     */
    Q_INVOKABLE virtual QString exampleMethod(const QString& input) = 0;
    
    // Add more methods as needed...
};

#define {ModuleName}Interface_iid "org.logos.{ModuleName}Interface"
Q_DECLARE_INTERFACE({ModuleName}Interface, {ModuleName}Interface_iid)

#endif // {MODULE_NAME}_INTERFACE_H
```

## Step 7: Create Plugin Header

Create `src/{module_name}_plugin.h`:

```cpp
#ifndef {MODULE_NAME}_PLUGIN_H
#define {MODULE_NAME}_PLUGIN_H

#include <QObject>
#include <QString>
#include "{module_name}_interface.h"

// If wrapping an external library:
// #include "lib/libmylib.h"

class LogosAPI;

/**
 * @brief {ModuleName} module plugin implementation
 * 
 * {Description}
 */
class {ModuleName}Plugin : public QObject, public {ModuleName}Interface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID {ModuleName}Interface_iid FILE "metadata.json")
    Q_INTERFACES({ModuleName}Interface PluginInterface)

public:
    explicit {ModuleName}Plugin(QObject* parent = nullptr);
    ~{ModuleName}Plugin() override;

    // PluginInterface implementation
    QString name() const override { return "{module_name}"; }
    QString version() const override { return "1.0.0"; }
    void initLogos(LogosAPI* api) override;

    // {ModuleName}Interface implementation
    Q_INVOKABLE QString exampleMethod(const QString& input) override;
    
    // Add more method implementations...

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
    // Add private members as needed
};

#endif // {MODULE_NAME}_PLUGIN_H
```

## Step 8: Create Plugin Implementation

Create `src/{module_name}_plugin.cpp`:

```cpp
#include "{module_name}_plugin.h"
#include "logos_api.h"
#include <QDebug>

{ModuleName}Plugin::{ModuleName}Plugin(QObject* parent)
    : QObject(parent)
{
    qDebug() << "{ModuleName}Plugin: Constructor called";
}

{ModuleName}Plugin::~{ModuleName}Plugin()
{
    qDebug() << "{ModuleName}Plugin: Destructor called";
}

void {ModuleName}Plugin::initLogos(LogosAPI* api)
{
    qDebug() << "{ModuleName}Plugin: initLogos called";
    m_logosAPI = api;
    
    // Perform any initialization here
    
    // Emit initialization event
    emit eventResponse("initialized", QVariantList() << "{module_name}" << "1.0.0");
}

QString {ModuleName}Plugin::exampleMethod(const QString& input)
{
    qDebug() << "{ModuleName}Plugin: exampleMethod called with:" << input;
    
    // Implement your method logic here
    QString result = QString("Processed: %1").arg(input);
    
    // Optionally emit an event
    emit eventResponse("example_completed", QVariantList() << input << result);
    
    return result;
}

// Add more method implementations...
```

## Step 9: Build and Test

```bash
# Track all files (Nix only sees git-tracked files)
git init && git add -A

# Build the module
nix build

# Check outputs
ls -la result/lib/
ls -la result/include/

# Enter development shell
nix develop
```

## Naming Conventions

When replacing placeholders:

| Placeholder | Example |
|-------------|---------|
| `{module_name}` | `wallet_module` |
| `{ModuleName}` | `WalletModule` |
| `{MODULE_NAME}` | `WALLET_MODULE` |
| `{category}` | `wallet` |
| `{description}` | `Wallet integration module` |

## Adding External Library Support

### Option 1: Pre-built Library in Source (simplest)

Use when you have a pre-built library binary to include in your repo.

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
    SOURCES ...
    EXTERNAL_LIBS
        mylib
)
```

4. Include in plugin:
```cpp
#include "lib/libmylib.h"
```

### Option 2: Build from Source (flake_input + externalLibInputs)

See "With External Library" in Step 4 above.

**Decision guide:**
| Approach | When to Use |
|----------|-------------|
| `vendor_path` | Pre-built binaries already in repo |
| `externalLibInputs` | Build from source, pin via flake input |

## Calling Other Modules

```cpp
void {ModuleName}Plugin::initLogos(LogosAPI* api)
{
    m_logosAPI = api;

    // Get client for another module
    auto* wakuClient = m_logosAPI->getClient("waku_module");

    // Call a method
    QVariant result = wakuClient->invokeRemoteMethod("waku_module", "initWaku", "{}");
}
```

Or using generated wrappers (if available):
```cpp
#include "logos_sdk.h"

void {ModuleName}Plugin::someMethod()
{
    // Using generated wrapper
    logos.waku_module.initWaku("{}");
}
```

## Emitting Events

To emit events that other modules can listen to:

```cpp
// Emit a simple event
emit eventResponse("my_event", QVariantList() << "data1" << "data2");

// Emit with complex data
QVariantMap data;
data["key1"] = "value1";
data["key2"] = 42;
emit eventResponse("complex_event", QVariantList() << QVariant(data));
```

## Final Checklist

- [ ] `metadata.json` has correct name, type, and dependencies
- [ ] `flake.nix` imports logos-module-builder correctly with `flakeInputs = inputs`
- [ ] `CMakeLists.txt` lists all source files
- [ ] Interface header defines all public methods with `Q_INVOKABLE`
- [ ] Plugin header has correct `Q_PLUGIN_METADATA` pointing to `"metadata.json"`
- [ ] Plugin implementation includes all method implementations
- [ ] External libraries (if any) are in `lib/` and git-tracked
- [ ] Build succeeds with `nix build`
