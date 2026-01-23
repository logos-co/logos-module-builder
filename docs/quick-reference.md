# Quick Reference

Cheat sheet for common logos-module-builder tasks.

## Create a New Module

```bash
# 1. Create directory
mkdir logos-my-module && cd logos-my-module

# 2. Create module.yaml
cat > module.yaml << 'EOF'
name: my_module
version: 1.0.0
type: core
category: general
description: "My module"
dependencies: []
nix_packages:
  build: []
  runtime: []
external_libraries: []
cmake:
  find_packages: []
  extra_sources: []
  proto_files: []
EOF

# 3. Create flake.nix
cat > flake.nix << 'EOF'
{
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";
  outputs = { self, logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
    };
}
EOF

# 4. Create metadata.json
cat > metadata.json << 'EOF'
{
  "name": "my_module",
  "version": "1.0.0",
  "type": "core",
  "category": "general",
  "main": "my_module_plugin",
  "dependencies": []
}
EOF

# 5. Create CMakeLists.txt
cat > CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
logos_module(NAME my_module SOURCES my_module_interface.h my_module_plugin.h my_module_plugin.cpp)
EOF

# 6. Create source files (see templates)

# 7. Build
nix build
```

## module.yaml Quick Reference

```yaml
# Required
name: module_name

# Optional with defaults
version: "1.0.0"
type: "core"
category: "general"
description: "A Logos module"

# Module dependencies
dependencies:
  - waku_module
  - other_module

# Nix packages
nix_packages:
  build:
    - protobuf
    - abseil-cpp
  runtime:
    - zstd

# External libraries
external_libraries:
  # Flake input method
  - name: mylib
    flake_input: "github:org/repo"
    build_command: "make"
    
  # Vendor method
  - name: mylib
    vendor_path: "vendor/mylib"
    build_script: "build.sh"
    
  # Pre-built in lib/
  - name: mylib
    vendor_path: "lib"

# CMake options
cmake:
  find_packages:
    - Protobuf
    - Threads
  extra_sources:
    - src/helper.cpp
  proto_files:
    - src/message.proto
  extra_include_dirs:
    - include
  extra_link_libraries:
    - pthread
```

## CMakeLists.txt Quick Reference

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyModulePlugin LANGUAGES CXX)

include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

logos_module(
    NAME my_module
    SOURCES 
        my_module_interface.h
        my_module_plugin.h
        my_module_plugin.cpp
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
  
  outputs = { self, logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
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
  
  outputs = { self, logos-module-builder, logos-waku-module, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      moduleInputs = {
        waku_module = logos-waku-module;
      };
    };
}
```

### With External Library
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    mylib = { url = "github:org/mylib"; flake = false; };
  };
  
  outputs = { self, logos-module-builder, mylib, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      externalLibInputs = {
        mylib = mylib;
      };
    };
}
```

## Source File Templates

### Interface Header (`my_module_interface.h`)
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

### Plugin Header (`my_module_plugin.h`)
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

### Plugin Implementation (`my_module_plugin.cpp`)
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
# Build module
nix build

# Enter dev shell
nix develop

# Build specific output
nix build .#my_module-lib
nix build .#my_module-include

# Check flake
nix flake check

# Update flake inputs
nix flake update
```
