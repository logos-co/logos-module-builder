# Getting Started

This guide walks you through creating a new Logos module using `logos-module-builder`.

## Prerequisites

- Nix with flakes enabled
- Basic familiarity with C++ and Qt
- Understanding of the Logos module architecture (see [specs](https://github.com/logos-co/logos-core-poc/blob/main/docs/specs.md))

## Creating a New Module

### 1. Create the Module Directory

```bash
mkdir logos-my-module
cd logos-my-module
```

### 2. Create `module.yaml`

This is the configuration file that defines your module:

```yaml
# module.yaml
name: my_module
version: 1.0.0
type: core
category: general
description: "My awesome Logos module"

# Dependencies on other Logos modules (empty for basic modules)
dependencies: []

# Additional nix packages (empty for basic modules)
nix_packages:
  build: []
  runtime: []

# External libraries to wrap (empty for basic modules)
external_libraries: []

# CMake configuration (empty for basic modules)
cmake:
  find_packages: []
  extra_sources: []
  proto_files: []
```

### 3. Create `flake.nix`

```nix
{
  description = "My Logos Module";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
  };

  outputs = { self, logos-module-builder, nixpkgs }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
    };
}
```

### 4. Create `metadata.json`

This is required by the Logos runtime:

```json
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "main": "my_module_plugin",
  "dependencies": []
}
```

### 5. Create the Interface Header

Create `src/my_module_interface.h`:

```cpp
#ifndef MY_MODULE_INTERFACE_H
#define MY_MODULE_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

class MyModuleInterface : public PluginInterface
{
public:
    virtual ~MyModuleInterface() = default;
    
    // Define your module's public API here
    Q_INVOKABLE virtual QString doSomething(const QString& input) = 0;
};

#define MyModuleInterface_iid "org.logos.MyModuleInterface"
Q_DECLARE_INTERFACE(MyModuleInterface, MyModuleInterface_iid)

#endif
```

### 6. Create the Plugin Header

Create `src/my_module_plugin.h`:

```cpp
#ifndef MY_MODULE_PLUGIN_H
#define MY_MODULE_PLUGIN_H

#include <QObject>
#include "my_module_interface.h"

class LogosAPI;

class MyModulePlugin : public QObject, public MyModuleInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID MyModuleInterface_iid FILE "metadata.json")
    Q_INTERFACES(MyModuleInterface PluginInterface)

public:
    explicit MyModulePlugin(QObject* parent = nullptr);
    ~MyModulePlugin() override;

    // PluginInterface
    QString name() const override { return "my_module"; }
    QString version() const override { return "1.0.0"; }
    void initLogos(LogosAPI* api) override;

    // MyModuleInterface
    Q_INVOKABLE QString doSomething(const QString& input) override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
};

#endif
```

### 7. Create the Plugin Implementation

Create `src/my_module_plugin.cpp`:

```cpp
#include "my_module_plugin.h"
#include "logos_api.h"
#include <QDebug>

MyModulePlugin::MyModulePlugin(QObject* parent) : QObject(parent)
{
    qDebug() << "MyModulePlugin: Created";
}

MyModulePlugin::~MyModulePlugin()
{
    qDebug() << "MyModulePlugin: Destroyed";
}

void MyModulePlugin::initLogos(LogosAPI* api)
{
    m_logosAPI = api;
    qDebug() << "MyModulePlugin: Initialized with LogosAPI";
    
    emit eventResponse("initialized", QVariantList() << "my_module");
}

QString MyModulePlugin::doSomething(const QString& input)
{
    qDebug() << "MyModulePlugin: doSomething called with:" << input;
    
    QString result = QString("Processed: %1").arg(input);
    
    emit eventResponse("processed", QVariantList() << input << result);
    
    return result;
}
```

### 8. Create `CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

logos_module(
    NAME my_module
    SOURCES 
        src/my_module_interface.h
        src/my_module_plugin.h
        src/my_module_plugin.cpp
)
```

### 9. Build the Module

```bash
# Build everything (lib + generated headers)
nix build

# Build just the library
nix build .#lib

# Build just the generated headers
nix build .#include
```

The output will be in `result/`:
- `result/lib/my_module_plugin.so` (or `.dylib` on macOS)
- `result/include/` - Generated headers for SDK

## Module Structure Summary

```
logos-my-module/
├── flake.nix              # Nix flake (15 lines)
├── module.yaml            # Module config (20 lines)
├── metadata.json          # Runtime metadata
├── CMakeLists.txt         # CMake config (15 lines)
└── src/                   # Source files
    ├── my_module_interface.h
    ├── my_module_plugin.h
    └── my_module_plugin.cpp
```

## Next Steps

- Add dependencies on other modules (see [configuration.md](./configuration.md))
- Wrap an external library (see [examples/external-lib-module](../examples/external-lib-module))
- Add protobuf support for messaging
- Migrate an existing module (see [migration.md](./migration.md))

## Using Your Module

Once built, the module can be loaded by Logos Core:

```cpp
// In an application using Logos Core
logos_core_load_plugin("my_module");

// Call methods via LogosAPI
auto* client = logosAPI->getClient("my_module");
QString result = client->invokeRemoteMethod("my_module", "doSomething", "test");
```

Or using the generated SDK wrappers:

```cpp
// Using code-generated wrappers
QString result = logos.my_module.doSomething("test");
```
