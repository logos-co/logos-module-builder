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
├── module.yaml            # Module configuration
├── metadata.json          # Runtime metadata
├── CMakeLists.txt         # CMake build file
├── src/                   # Source files
│   ├── {name}_interface.h
│   ├── {name}_plugin.h
│   └── {name}_plugin.cpp
└── lib/                   # External libraries (optional)
```

## Task 1: Add a New Method

### Step 1: Update Interface Header

In `src/{name}_interface.h`, add the method declaration:

```cpp
class {ModuleName}Interface : public PluginInterface
{
public:
    // Existing methods...
    
    /**
     * @brief {Description of new method}
     * @param {param} {Parameter description}
     * @return {Return description}
     */
    Q_INVOKABLE virtual {ReturnType} newMethod({ParamType} param) = 0;
};
```

### Step 2: Update Plugin Header

In `src/{name}_plugin.h`, add the method declaration:

```cpp
class {ModuleName}Plugin : public QObject, public {ModuleName}Interface
{
    // ...existing code...

    // Add method declaration
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
    
    // Optionally emit an event
    emit eventResponse("new_method_completed", QVariantList() << param);
    
    return result;
}
```

### Step 4: Rebuild

```bash
nix build
```

## Task 2: Add a Module Dependency

### Step 1: Update module.yaml

```yaml
dependencies:
  - existing_module
  - new_module  # Add the new dependency
```

### Step 2: Update flake.nix

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
    # Add the new module input
    logos-new-module.url = "github:logos-co/logos-new-module";
  };

  outputs = { self, logos-module-builder, nixpkgs, logos-new-module }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      moduleInputs = {
        # Add to moduleInputs
        new_module = logos-new-module;
      };
    };
}
```

### Step 3: Update metadata.json

```json
{
  "name": "{module_name}",
  "version": "1.0.0",
  "type": "core",
  "category": "{category}",
  "main": "{module_name}_plugin",
  "dependencies": ["existing_module", "new_module"],
  "include": []
}
```

Note: The `include` field is automatically generated from `module.yaml` during build.

### Step 4: Use the Dependency in Code

```cpp
#include "logos_api.h"

void {ModuleName}Plugin::someMethod()
{
    // Get client for the new module
    auto* client = m_logosAPI->getClient("new_module");
    
    // Call a method on it
    QVariant result = client->invokeRemoteMethod("new_module", "someMethod", arg1, arg2);
}
```

## Task 3: Add an External Library

### Step 1: Obtain the Library

Either:
- Place pre-built library in `lib/` directory
- Add as flake input for building from source

### Step 2: Update module.yaml

For pre-built library:
```yaml
external_libraries:
  - name: newlib
    vendor_path: "lib"

# Specify which library files to bundle with the module
include:
  - libnewlib.so
  - libnewlib.dylib
  - libnewlib.dll
```

For building from source:
```yaml
external_libraries:
  - name: newlib
    flake_input: "github:org/newlib"
    build_command: "make shared"

# Specify which library files to bundle
include:
  - libnewlib.so
  - libnewlib.dylib
  - libnewlib.dll
```

### Step 3: Update flake.nix (if building from source)

```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add library source
    newlib-src = {
      url = "github:org/newlib";
      flake = false;
    };
  };

  outputs = { self, logos-module-builder, newlib-src, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      externalLibInputs = {
        newlib = newlib-src;
      };
    };
}
```

### Step 4: Update CMakeLists.txt

```cmake
logos_module(
    NAME {module_name}
    SOURCES ...
    EXTERNAL_LIBS
        existing_lib
        newlib  # Add the new library
)
```

### Step 5: Add Library Header and Use

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

### Step 2: Update module.yaml

```yaml
nix_packages:
  build:
    - protobuf
    - abseil-cpp

cmake:
  find_packages:
    - Protobuf
    - Threads
  proto_files:
    - src/protobuf/message.proto
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

For modules not yet using logos-module-builder:

### Step 1: Create module.yaml

Extract configuration from existing files:

```yaml
name: {module_name}  # From metadata.json
version: 1.0.0       # From metadata.json
type: core
category: {category}
description: "{from README or docs}"

# From flake.nix inputs (other logos modules)
dependencies:
  - waku_module

# From nix/default.nix buildInputs
nix_packages:
  build:
    - protobuf
  runtime:
    - zstd

# From lib/ directory contents
external_libraries:
  - name: libwaku
    vendor_path: "lib"

# List library files to bundle (from metadata.json "include" field)
include:
  - libwaku.so
  - libwaku.dylib
  - libwaku.dll

# From CMakeLists.txt
cmake:
  find_packages:
    - Protobuf
  extra_sources:
    - src/helper.cpp
  proto_files:
    - src/message.proto
```

### Step 2: Simplify flake.nix

Replace the entire file with:

```nix
{
  description = "{Module description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
    # Add module dependencies
  };

  outputs = { self, logos-module-builder, nixpkgs, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      # Add moduleInputs if needed
    };
}
```

### Step 3: Simplify CMakeLists.txt

Replace with:

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
        # Additional sources from module.yaml
    EXTERNAL_LIBS
        # From module.yaml
    FIND_PACKAGES
        # From module.yaml
    PROTO_FILES
        # From module.yaml
)
```

### Step 4: Delete nix/ Directory

Remove the entire `nix/` directory:
- `nix/default.nix`
- `nix/lib.nix`
- `nix/include.nix`

### Step 5: Test Build

```bash
nix build
```

## Task 6: Update Version

### Step 1: Update module.yaml

```yaml
version: 2.0.0  # Update version
```

### Step 2: Update metadata.json

```json
{
  "version": "2.0.0"
}
```

### Step 3: Update Plugin Header

```cpp
QString version() const override { return "2.0.0"; }
```

## Task 7: Add Event Emission

### In Plugin Implementation

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

### Step 1: Update module.yaml

```yaml
nix_packages:
  build:
    - existing_pkg
    - new_package  # Add here
  runtime:
    - runtime_pkg
```

### Step 2: Use in Code (if needed)

The package will be available during build. If it provides headers or libraries, you may need to update CMakeLists.txt:

```cmake
logos_module(
    NAME {module_name}
    SOURCES ...
    FIND_PACKAGES
        NewPackage  # If it's a CMake package
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
    // Start async operation
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
    // Get waku client
    auto* waku = m_logosAPI->getClient("waku_module");
    
    // Call waku method
    QVariant result = waku->invokeRemoteMethod(
        "waku_module", 
        "relayPublish", 
        "/default/topic", 
        message, 
        "/content/topic"
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
        qWarning() << "{ModuleName}Plugin: Error:" << errorMsg;
        
        return QString();
    }
    
    // Process result...
    QString output = processResult(result);
    external_lib_free(result);
    
    return output;
}
```

## Verification Checklist

After any update:

- [ ] `module.yaml` syntax is valid
- [ ] `flake.nix` inputs match moduleInputs/externalLibInputs keys
- [ ] `metadata.json` is consistent with module.yaml
- [ ] If using external libraries, `include` field lists all library files to bundle
- [ ] External library files are present in `lib/` directory
- [ ] All new methods in interface are `Q_INVOKABLE virtual`
- [ ] All interface methods are implemented in plugin
- [ ] Plugin header has matching declarations
- [ ] Build succeeds: `nix build`
- [ ] Verify external libraries are copied: `ls -R result/lib/`
- [ ] Plugin loads correctly in Logos Core
