# Create Logos UI Module Skill (C++ Qt Widget)

Use this skill when the user wants to create a Logos UI module backed by a native
C++ Qt widget.  These modules implement `IComponent`, return a `QWidget*` from
`createWidget()`, and are displayed as tabs in `logos-basecamp` (or in
`logos-standalone-app` for isolated development).

For pure QML UI modules see `create-qml-module.md`.
For backend/logic modules see `create-logos-module.md`.

## When to Use

- User asks to "create a UI module"
- User wants to "build a Qt widget plugin"
- User wants to "create a module with a UI" (C++ / native)
- User wants to "preview a UI module with logos-standalone-app"

## Prerequisites

The module uses `logos-module-builder` for building and `logos-standalone-app`
for isolated visual testing.

## Step 1: Gather Requirements

Ask for:
1. **Module name** — snake_case, e.g. `wallet_ui`
2. **Description** — what the UI shows/does
3. **Backend dependencies** — core modules this UI calls (e.g. `waku_module`)

## Step 2: Scaffold

```bash
mkdir logos-{name}-module && cd logos-{name}-module
nix flake init -t github:logos-co/logos-module-builder#ui-module
git init && git add -A
```

## Step 3: Directory Structure

```
logos-{name}-module/
├── flake.nix
├── module.yaml
├── metadata.json
├── CMakeLists.txt
├── interfaces/
│   └── IComponent.h
└── src/
    ├── {name}_plugin.h
    └── {name}_plugin.cpp
```

## Step 4: module.yaml

```yaml
name: {name}
version: 1.0.0
type: ui
category: {category}
description: "{description}"

dependencies:
  # List backend core modules this UI depends on, e.g.:
  # - waku_module

nix_packages:
  build: []
  runtime: []

external_libraries: []

cmake:
  find_packages: []
  extra_sources: []
  proto_files: []
```

## Step 5: metadata.json

```json
{
  "name": "{name}",
  "version": "1.0.0",
  "type": "ui",
  "category": "{category}",
  "main": "{name}_plugin",
  "dependencies": []
}
```

## Step 6: flake.nix

`mkLogosModule` handles the build.  `apps` is added by the flake itself — no
changes to `mkLogosModule` needed.

```nix
{
  description = "{description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";

    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    logos-standalone-app.inputs.logos-liblogos.inputs.nixpkgs.follows =
      "logos-module-builder/nixpkgs";
  };

  outputs = { self, logos-module-builder, logos-standalone-app, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      moduleOutputs = logos-module-builder.lib.mkLogosModule {
        src = ./.;
        configFile = ./module.yaml;
      };
    in
      moduleOutputs // {
        apps = forAllSystems (system:
          let
            pkgs = import nixpkgs { inherit system; };
            standalone = logos-standalone-app.packages.${system}.default;
            plugin = moduleOutputs.packages.${system}.default;
            # logos-standalone expects .so + metadata.json in the same directory.
            # mkLogosModule splits them: lib/ for the .so, share/ for metadata.json.
            pluginDir = pkgs.runCommand "{name}-plugin-dir" {} ''
              mkdir -p $out
              cp ${plugin}/lib/*_plugin.*  $out/
              cp ${./metadata.json} $out/metadata.json
            '';
            run = pkgs.writeShellScript "run-{name}-standalone" ''
              exec ${standalone}/bin/logos-standalone-app "${pluginDir}" "$@"
            '';
          in { default = { type = "app"; program = "${run}"; }; }
        );
      };
}
```

If the module depends on other Logos modules, add them to `moduleInputs`:

```nix
moduleOutputs = logos-module-builder.lib.mkLogosModule {
  src = ./.;
  configFile = ./module.yaml;
  moduleInputs = {
    waku_module = logos-waku-module;
  };
};
```

## Step 7: CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.14)
project({ModuleName}Plugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

logos_module(
    NAME {name}
    SOURCES
        src/{name}_plugin.h
        src/{name}_plugin.cpp
    INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/interfaces
)

# Qt Widgets is required for QWidget-based UI modules but not included by
# logos_module() — find and link it explicitly.
find_package(Qt6 REQUIRED COMPONENTS Widgets)
target_link_libraries({name}_module_plugin PRIVATE Qt6::Widgets)
```

## Step 8: Interface Header (`interfaces/IComponent.h`)

Copy this verbatim — it is the stable contract between the plugin and the host:

```cpp
#pragma once

#include <QObject>
#include <QWidget>
#include <QtPlugin>

class LogosAPI;

class IComponent {
public:
    virtual ~IComponent() = default;
    virtual QWidget* createWidget(LogosAPI* logosAPI = nullptr) = 0;
    virtual void destroyWidget(QWidget* widget) = 0;
};

#define IComponent_iid "com.logos.component.IComponent"
Q_DECLARE_INTERFACE(IComponent, IComponent_iid)
```

## Step 9: Plugin Header (`src/{name}_plugin.h`)

```cpp
#ifndef {NAME}_PLUGIN_H
#define {NAME}_PLUGIN_H

#include <QObject>
#include <QWidget>
#include <IComponent.h>

class LogosAPI;

class {ModuleName}Plugin : public QObject, public IComponent
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID IComponent_iid FILE "metadata.json")
    Q_INTERFACES(IComponent)

public:
    explicit {ModuleName}Plugin(QObject* parent = nullptr);
    ~{ModuleName}Plugin() override;

    Q_INVOKABLE QWidget* createWidget(LogosAPI* logosAPI = nullptr) override;
    void destroyWidget(QWidget* widget) override;
};

#endif // {NAME}_PLUGIN_H
```

## Step 10: Plugin Implementation (`src/{name}_plugin.cpp`)

```cpp
#include "{name}_plugin.h"
#include <QDebug>
#include <QLabel>
#include <QVBoxLayout>

{ModuleName}Plugin::{ModuleName}Plugin(QObject* parent)
    : QObject(parent) {}

{ModuleName}Plugin::~{ModuleName}Plugin() {}

QWidget* {ModuleName}Plugin::createWidget(LogosAPI* logosAPI)
{
    Q_UNUSED(logosAPI)
    auto* widget = new QWidget();
    auto* layout = new QVBoxLayout(widget);
    auto* label = new QLabel("Hello from {name}!", widget);
    layout->addWidget(label);
    return widget;
}

void {ModuleName}Plugin::destroyWidget(QWidget* widget)
{
    delete widget;
}
```

## Step 11: Build and Run

```bash
git add -A
nix build        # compiles the Qt plugin → result/lib/{name}_plugin.so
nix run .        # launches in logos-standalone-app
```

To load backend dependencies in the standalone app:

```bash
nix run . -- --modules-dir ./modules --load waku_module
```

## Naming Conventions

| Placeholder | Example |
|-------------|---------|
| `{name}` | `wallet_ui` |
| `{ModuleName}` | `WalletUi` |
| `{NAME}` | `WALLET_UI` |
| `{category}` | `wallet` |

## Final Checklist

- [ ] `module.yaml` has `type: ui`
- [ ] `metadata.json` has `"type": "ui"` and is at the module root
- [ ] `flake.nix` merges `apps` on top of `mkLogosModule` output
- [ ] `CMakeLists.txt` lists all source files
- [ ] Plugin inherits `IComponent` and implements `createWidget()` and `destroyWidget()`
- [ ] `Q_PLUGIN_METADATA` uses `IComponent_iid` and points to `"metadata.json"`
- [ ] `nix build` succeeds
- [ ] `nix run .` launches the widget in logos-standalone-app
