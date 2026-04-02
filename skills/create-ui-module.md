# Create Logos UI Module Skill (C++ Backend + QML View)

Use this skill when the user wants to create a Logos UI module with a C++ backend
and QML frontend. These modules are **process-isolated**: the C++ plugin runs in a
separate `ui-host` process, and the QML view is loaded in the host application
(`logos-basecamp` or `logos-standalone-app`). Communication between the QML view
and C++ backend happens via Qt Remote Objects over a private socket.

For QML-only modules (no C++ backend), see `create-qml-module.md`.
For backend/logic modules (no UI) see `create-logos-module.md`.

## When to Use

- User asks to "create a UI module"
- User wants to "build a C++ UI plugin"
- User wants to "create a module with a UI" (C++ backend + QML view)
- User wants to "preview a UI module with logos-standalone-app"

## Prerequisites

The module uses `logos-module-builder` for building. `logos-standalone-app` is
bundled inside `logos-module-builder` and used automatically for isolated visual testing.

## Step 1: Gather Requirements

Ask for:
1. **Module name** — snake_case, e.g. `wallet_ui`
2. **Description** — what the UI shows/does
3. **Backend dependencies** — core modules this UI calls (e.g. `calc_module`)
4. **Methods** — what Q_INVOKABLE methods the C++ backend should expose to the QML view

## Step 2: Scaffold

```bash
mkdir logos-{name}-module && cd logos-{name}-module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-backend
git init && git add -A
```

## Step 3: Directory Structure

```
logos-{name}-module/
├── flake.nix
├── metadata.json
├── CMakeLists.txt
└── src/
    ├── {name}_interface.h
    ├── {name}_plugin.h
    ├── {name}_plugin.cpp
    └── qml/
        └── Main.qml
```

## Step 4: metadata.json

The `"view"` field is what makes this a view module. It points to the QML entry file
relative to the module's output directory (the build system copies `src/qml/` to
the output alongside the `.so`).

```json
{
  "name": "{name}",
  "version": "1.0.0",
  "type": "ui_qml",
  "category": "{category}",
  "description": "{description}",
  "main": "{name}_plugin",
  "icon": null,
  "view": "qml/Main.qml",
  "dependencies": [],

  "nix": {
    "packages": { "build": [], "runtime": [] },
    "external_libraries": [],
    "cmake": { "find_packages": [], "extra_sources": [] }
  }
}
```

If the UI calls backend modules, list them in `"dependencies"`:
```json
"dependencies": ["calc_module"]
```

## Step 5: flake.nix

```nix
{
  description = "{description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

If the module depends on other Logos modules, add them as inputs — they are auto-resolved from `dependencies` in `metadata.json` and auto-bundled at build time:

```nix
inputs = {
  logos-module-builder.url = "github:logos-co/logos-module-builder";
  calc_module.url = "github:logos-co/logos-tutorial?dir=logos-calc-module";
};
```

## Step 6: CMakeLists.txt

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
        src/{name}_interface.h
        src/{name}_plugin.h
        src/{name}_plugin.cpp
)
```

No Qt Widgets dependency needed — the QML view runs in the host app, and the
plugin runs headlessly in `ui-host`.

## Step 7: Interface Header (`src/{name}_interface.h`)

```cpp
#ifndef {NAME}_INTERFACE_H
#define {NAME}_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

class {ModuleName}Interface : public PluginInterface
{
public:
    virtual ~{ModuleName}Interface() = default;
};

#define {ModuleName}Interface_iid "org.logos.{ModuleName}Interface"
Q_DECLARE_INTERFACE({ModuleName}Interface, {ModuleName}Interface_iid)

#endif // {NAME}_INTERFACE_H
```

## Step 8: Plugin Header (`src/{name}_plugin.h`)

```cpp
#ifndef {NAME}_PLUGIN_H
#define {NAME}_PLUGIN_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include "{name}_interface.h"

class LogosAPI;

class {ModuleName}Plugin : public QObject, public {ModuleName}Interface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID {ModuleName}Interface_iid FILE "metadata.json")
    Q_INTERFACES({ModuleName}Interface PluginInterface)

public:
    explicit {ModuleName}Plugin(QObject* parent = nullptr);
    ~{ModuleName}Plugin() override;

    QString name()    const override { return "{name}"; }
    QString version() const override { return "1.0.0"; }

    // Called by ui-host so the plugin can make outgoing calls to
    // backend modules via LogosAPI
    Q_INVOKABLE void initLogos(LogosAPI* api);

    // Add your methods here — each Q_INVOKABLE method is callable
    // from the QML view via logos.callModuleAsync()
    Q_INVOKABLE QString hello(const QString& name);

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
};

#endif // {NAME}_PLUGIN_H
```

## Step 9: Plugin Implementation (`src/{name}_plugin.cpp`)

```cpp
#include "{name}_plugin.h"
#include "logos_api.h"
#include <QDebug>

{ModuleName}Plugin::{ModuleName}Plugin(QObject* parent)
    : QObject(parent) {}

{ModuleName}Plugin::~{ModuleName}Plugin() {}

void {ModuleName}Plugin::initLogos(LogosAPI* api)
{
    m_logosAPI = api;
    qDebug() << "{ModuleName}Plugin: LogosAPI initialized";

    // To call other modules, create a LogosModules instance:
    // #include "logos_sdk.h"
    // m_logos = new LogosModules(api);
    // Then call: m_logos->calc_module.someMethod(...)
}

QString {ModuleName}Plugin::hello(const QString& name)
{
    return QStringLiteral("Hello, %1!").arg(name);
}
```

## Step 10: QML View (`src/qml/Main.qml`)

The QML view uses `logos.callModuleAsync()` to call methods on the C++ backend.
The first argument is the module name (from `metadata.json`), the second is the
method name, the third is the arguments array, and the fourth is a callback
function that receives the result.

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string result: ""

    function callBackend(method, args) {
        root.result = "..."
        logos.callModuleAsync("{name}", method, args, function(r) {
            root.result = r
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Text {
            text: "{ModuleName}"
            font.pixelSize: 20
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            TextField {
                id: nameInput
                placeholderText: "Enter a name"
                Layout.fillWidth: true
            }

            Button {
                text: "Say Hello"
                onClicked: root.callBackend("hello", [nameInput.text])
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "#1a2d1a"
            radius: 8

            Text {
                anchors.centerIn: parent
                text: root.result.length > 0 ? root.result
                        : "Press a button to call the backend"
                color: "#56d364"
                font.pixelSize: 15
            }
        }

        Item { Layout.fillHeight: true }
    }
}
```

## Step 11: Build and Run

```bash
git add -A
nix build        # compiles the Qt plugin → result/lib/{name}_plugin.so
nix run .        # launches in logos-standalone-app with ui-host
```

## Architecture

When `nix run .` or logos-basecamp loads a view module, this happens:

```
Host app (logos-standalone-app / logos-basecamp)
  │
  ├─ reads metadata.json, sees "view": "qml/Main.qml"
  ├─ spawns ui-host child process with the plugin .so
  │     │
  │     └─ ui-host process:
  │          ├─ loads plugin .so via QPluginLoader
  │          ├─ calls initLogos() so plugin can reach backend modules
  │          ├─ wraps plugin in ViewModuleProxy (type coercion + callMethod)
  │          ├─ exposes proxy on private QRO socket
  │          └─ prints READY
  │
  ├─ creates QQuickWidget with qml/Main.qml
  ├─ sets "logos" context property (bridge to the QRO socket)
  └─ QML calls logos.callModuleAsync() → QRO → ViewModuleProxy → plugin
```

The plugin runs in its own process. If it crashes, the host app stays alive.

## Calling Backend Modules

If your UI module needs to call other backend modules (e.g. `calc_module`):

1. Add the dependency to `metadata.json`:
   ```json
   "dependencies": ["calc_module"]
   ```

2. Add the flake input:
   ```nix
   inputs = {
     logos-module-builder.url = "github:logos-co/logos-module-builder";
     calc_module.url = "github:logos-co/logos-tutorial?dir=logos-calc-module";
   };
   ```

3. Use `LogosModules` in your plugin:
   ```cpp
   #include "logos_sdk.h"

   void MyPlugin::initLogos(LogosAPI* api) {
       m_logosAPI = api;
       m_logos = new LogosModules(api);
   }

   int MyPlugin::addNumbers(int a, int b) {
       return m_logos->calc_module.add(a, b);
   }
   ```

4. Call from QML:
   ```qml
   logos.callModuleAsync("my_module", "addNumbers", [1, 2], function(r) {
       console.log("Result:", r)
   })
   ```

## Naming Conventions

| Placeholder | Example |
|-------------|---------|
| `{name}` | `wallet_ui` |
| `{ModuleName}` | `WalletUi` |
| `{NAME}` | `WALLET_UI` |
| `{category}` | `wallet` |

## Final Checklist

- [ ] `metadata.json` has `"type": "ui_qml"` and `"view": "qml/Main.qml"`
- [ ] `CMakeLists.txt` lists all source files
- [ ] Plugin has `Q_INVOKABLE void initLogos(LogosAPI* api)`
- [ ] Plugin has `Q_INVOKABLE` methods for each action the QML view needs
- [ ] `src/qml/Main.qml` exists and uses `logos.callModuleAsync()`
- [ ] `Q_PLUGIN_METADATA` points to `"metadata.json"`
- [ ] Backend dependencies listed in `metadata.json` `"dependencies"` and `flake.nix` inputs
- [ ] `nix build` succeeds
- [ ] `nix run .` launches the view in logos-standalone-app
