# Quick Reference

Cheat sheet for common logos-module-builder tasks.

## Create a New Module

```bash
# 1. Create directory
mkdir logos-my-module && cd logos-my-module

# 2. Create metadata.json
cat > metadata.json << 'EOF'
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "description": "My module",
  "main": "my_module_plugin",
  "dependencies": [],
  "nix": {
    "packages": { "build": [], "runtime": [] },
    "external_libraries": [],
    "cmake": { "find_packages": [], "extra_sources": [] }
  }
}
EOF

# 3. Create flake.nix
cat > flake.nix << 'EOF'
{
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
EOF

# 4. Create CMakeLists.txt
cat > CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
logos_module(NAME my_module SOURCES src/my_module_interface.h src/my_module_plugin.h src/my_module_plugin.cpp)
EOF

# 5. Create source files in src/ directory
mkdir -p src
# (see templates for source file content)

# 6. Track files and build
git init && git add -A
nix build
```

## metadata.json Quick Reference

```json
{
  "name": "module_name",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "description": "A Logos module",
  "main": "module_name_plugin",
  "dependencies": ["waku_module", "other_module"],

  "nix": {
    "packages": {
      "build": ["protobuf", "abseil-cpp"],
      "runtime": ["zstd"]
    },
    "external_libraries": [
      { "name": "mylib", "vendor_path": "lib" }
    ],
    "cmake": {
      "find_packages": ["Protobuf", "Threads"],
      "extra_sources": ["src/helper.cpp"],
      "extra_include_dirs": ["include"],
      "extra_link_libraries": ["pthread"]
    }
  }
}
```

## CMakeLists.txt Quick Reference

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)

include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

logos_module(
    NAME my_module
    SOURCES
        src/my_module_interface.h
        src/my_module_plugin.h
        src/my_module_plugin.cpp
        src/helper.cpp
    EXTERNAL_LIBS
        mylib
    FIND_PACKAGES
        Protobuf
    PROTO_FILES
        src/message.proto
    LINK_LIBRARIES
        pthread
)
```

## flake.nix Quick Reference

### Basic Module
```nix
{
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

### With Module Dependencies
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-waku-module.url = "github:logos-co/logos-waku-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;  # waku_module resolved automatically from dependencies[]
    };
}
```

### With External Library (flake input, built from source)
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    mylib = { url = "github:org/mylib"; flake = false; };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      externalLibInputs = {
        mylib = inputs.mylib;
      };
    };
}
```

### UI Module (C++ Qt widget, with `nix run`)
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
```

### QML Module
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
```

## Source File Templates

### Interface Header (`src/my_module_interface.h`)
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
    Q_INVOKABLE virtual QString myMethod(const QString& input) = 0;
};

#define MyModuleInterface_iid "org.logos.MyModuleInterface"
Q_DECLARE_INTERFACE(MyModuleInterface, MyModuleInterface_iid)

#endif
```

### Plugin Header (`src/my_module_plugin.h`)
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

    QString name() const override { return "my_module"; }
    QString version() const override { return "1.0.0"; }
    void initLogos(LogosAPI* api) override;

    Q_INVOKABLE QString myMethod(const QString& input) override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
};

#endif
```

### Plugin Implementation (`src/my_module_plugin.cpp`)
```cpp
#include "my_module_plugin.h"
#include "logos_api.h"
#include <QDebug>

MyModulePlugin::MyModulePlugin(QObject* parent) : QObject(parent) {}
MyModulePlugin::~MyModulePlugin() {}

void MyModulePlugin::initLogos(LogosAPI* api) {
    m_logosAPI = api;
    emit eventResponse("initialized", QVariantList() << "my_module");
}

QString MyModulePlugin::myMethod(const QString& input) {
    return QString("Result: %1").arg(input);
}
```

## Common Commands

```bash
# Build module (combined lib + include)
nix build

# Build just the library
nix build .#lib

# Build just the generated headers
nix build .#include

# Run UI module in logos-standalone-app
nix run .

# Enter dev shell
nix develop

# Build specific output (alternative syntax)
nix build .#my_module-lib
nix build .#my_module-include

# Check flake
nix flake check

# Update flake inputs
nix flake update
```
