# Create Logos UI Module Skill (C++ Backend + QML View)

Use this skill when the user wants to create a Logos UI module with a C++ backend
and QML frontend, using the **universal authoring model**. These modules are
**process-isolated**: the C++ plugin runs in a separate `ui-host` process, and the
QML view is loaded in the host application (`logos-basecamp` or
`logos-standalone-app`). Communication between the QML view and the C++ backend
happens via Qt Remote Objects (QtRO) over a private socket.

In the universal model you write exactly **two** things:

1. A `.rep` file — the QtRO view contract (SLOTs, PROPs, SIGNALs).
2. A `*Backend` class implementing it.

The `*Plugin` and `*Interface` classes — `Q_PLUGIN_METADATA`, `initLogos` wiring,
QtRO registration, `setBackend` — are **all generated**. You no longer hand-write
the interface + plugin pair (that was the classic model).

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
4. **View contract** — what SLOTs (callable methods), PROPs (auto-synced state),
   and SIGNALs the QML view needs from the backend

## Step 2: Scaffold

```bash
mkdir logos-{module_name}-module && cd logos-{module_name}-module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-backend
git init && git add -A
```

## Step 3: Directory Structure

```
logos-{module_name}-module/
├── flake.nix
├── metadata.json
├── CMakeLists.txt
└── src/
    ├── {module_name}.rep              # QtRO view contract (SLOTs/PROPs/SIGNALs)
    ├── {module_name}_backend.h        # your *Backend class (the only C++ you write)
    ├── {module_name}_backend.cpp
    └── qml/
        └── Main.qml
```

There is **no** `{module_name}_interface.h` and **no** `{module_name}_plugin.{h,cpp}`
— those classes are generated into `generated_code/` from your `.rep` + metadata.

## Step 4: metadata.json

`"type": "ui_qml"` + `"interface": "universal"` selects the typed backend path.
`"codegen": { "rep": "src/{module_name}.rep" }` names your view contract. The
`"view"` field points to the QML entry file relative to the module's output
directory (the build system copies `src/qml/` to the output alongside the `.so`).

```json
{
  "name": "{module_name}",
  "version": "1.0.0",
  "type": "ui_qml",
  "interface": "universal",
  "category": "{category}",
  "description": "{description}",
  "main": "{module_name}_plugin",
  "icon": null,
  "view": "qml/Main.qml",
  "dependencies": [],
  "codegen": { "rep": "src/{module_name}.rep" },

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

Keep `"main": "{module_name}_plugin"` even though you don't write the plugin —
it names the generated plugin. `backend_class` / `backend_header` are also
overridable under `codegen` but default to `{ModuleName}Backend` /
`{module_name}_backend.h`.

If the UI calls backend modules, list them in `"dependencies"`:
```json
"dependencies": ["calc_module"]
```

## Step 5: flake.nix

UI modules build with `mkLogosQmlModule` (not `mkLogosModule`). Dependencies are
flake inputs whose names match the `dependencies` in `metadata.json` — they are
auto-resolved and auto-bundled at build time.

```nix
{
  description = "{description}";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add core module dependencies as inputs (must match metadata.json "dependencies"), e.g.:
    # calc_module.url = "github:logos-co/logos-tutorial?dir=logos-calc-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

## Step 6: CMakeLists.txt

Pass your `.rep` via `REP_FILE` (runs repc) and list only your backend sources.
The generated `*Plugin` glue in `generated_code/` is compiled automatically.
There is no `module_config.h`.

```cmake
cmake_minimum_required(VERSION 3.14)
project({ModuleName}Plugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Universal UI module: you write the .rep + the *Backend class. REP_FILE runs
# repc; the generated *Plugin glue in generated_code/ is compiled automatically.
logos_module(
    NAME {module_name}
    REP_FILE src/{module_name}.rep
    SOURCES
        src/{module_name}_backend.h
        src/{module_name}_backend.cpp
    INCLUDE_DIRS
        src
)
```

No Qt Widgets dependency needed — the QML view runs in the host app, and the
plugin runs headlessly in `ui-host`.

## Step 7: The View Contract (`src/{module_name}.rep`)

The `.rep` is the QtRO contract between your backend and every QML replica.
Because you author it directly, the full QtRO surface is available:

- **SLOT** — a callable method (the QML side calls it; the return value comes
  back asynchronously via `logos.watch(...)`).
- **PROP** — auto-synced state. Feed it from the backend with the repc-generated
  setter (e.g. `setStatus(...)`); QtRO pushes every change to the QML replica.
- **SIGNAL** — a backend-emitted notification the QML side can connect to.

The `.rep` side uses **Qt types** (`QString`, `int`, `qlonglong`, ...) — that's
the QtRO wire contract.

```rep
class {RepClass}
{
    SLOT(int add(int a, int b))
    PROP(QString status="Ready" READONLY)
}
```

`{RepClass}` is the PascalCase of `{module_name}` (e.g. `wallet_ui` → `WalletUi`).

## Step 8: Backend Header (`src/{module_name}_backend.h`)

The backend is the only C++ class you write. It derives:

- `{RepClass}SimpleSource` — generated from your `.rep` by repc, pulled in via
  `"rep_{module_name}_source.h"`. Implement its SLOTs and feed its PROPs.
- `LogosUiPluginContext` — from `"logos_ui_plugin_context.h"` (logos-qt-sdk).
  Gives the backend `modules()` (Qt-typed callers for `dependencies`), typed
  event subscriptions (`modules().dep.on<Event>(...)`), and `onContextReady()`.
  A UI plugin is a view, not a module — it has no host identity
  (modulePath/instanceId/persistence) and emits no events of its own, so the
  context carries nothing else. The dep wrappers are **Qt-typed** (`QString`,
  `int`, ...), matching the `.rep` slots — no std<->Qt conversions in the view.

```cpp
#pragma once

#include "rep_{module_name}_source.h"
#include "logos_ui_plugin_context.h"

// The whole hand-written backend. The *Plugin and *Interface classes
// (Q_PLUGIN_METADATA, initLogos wiring, QtRO registration, setBackend) are
// generated around it.
//
// It derives:
//   - {RepClass}SimpleSource — generated from {module_name}.rep; implement its
//     SLOTs and feed its PROPs (e.g. setStatus(...)), which auto-sync to every
//     QML replica over QtRO.
//   - LogosUiPluginContext — supplies onContextReady() plus modules(), the
//     Qt-typed callers and event subscriptions for any "dependencies" you
//     declare. A UI plugin is a view, not a module, so that is all it carries.
class {ModuleName}Backend : public {RepClass}SimpleSource,
                            public LogosUiPluginContext
{
public:
    int add(int a, int b) override;
};
```

## Step 9: Backend Implementation (`src/{module_name}_backend.cpp`)

Implement the `.rep` SLOTs and feed PROPs via the repc-generated setters. Include
`"logos_sdk.h"` only when you actually use `modules()`.

```cpp
#include "{module_name}_backend.h"

// Generated umbrella: LogosModules (behind modules()) from
// metadata.json#dependencies — typed wrappers + typed event accessors.
// (No dependencies here, but include it once you add some.)
// #include "logos_sdk.h"

int {ModuleName}Backend::add(int a, int b)
{
    int result = a + b;
    // PROP from the .rep — QtRO pushes every setStatus to the QML replica.
    setStatus(QStringLiteral("%1 + %2 = %3").arg(a).arg(b).arg(result));
    return result;
}
```

## Step 10: QML View (`src/qml/Main.qml`)

`logos.module("{module_name}")` returns the **typed replica**:

- **SLOT return values** are delivered asynchronously — wrap the call in
  `logos.watch(...)` with success and error callbacks.
- **PROPs auto-sync** — just read `backend.<prop>` and bind to it; QtRO updates
  it for you.
- **Readiness** is signalled via `logos.isViewModuleReady(...)` plus the
  `onViewModuleReadyChanged` callback (a Q_INVOKABLE on `logos`, not a property —
  use the `Connections` + `Component.onCompleted` pattern below).

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Typed replica — auto-synced properties and callable slots.
    readonly property var backend: logos.module("{module_name}")
    property bool ready: false

    // "status" property from the .rep file, auto-updated via QtRO.
    readonly property string status: backend ? backend.status : ""

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "{module_name}")
                root.ready = isReady && root.backend !== null;
        }
    }
    Component.onCompleted: {
        root.ready = root.backend !== null && logos.isViewModuleReady("{module_name}");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Text {
            text: "{ModuleName} (C++ backend)"
            font.pixelSize: 20
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        // Connection status
        Text {
            text: root.ready ? "Connected" : "Connecting to backend..."
            color: root.ready ? "#56d364" : "#f0883e"
            font.pixelSize: 12
        }

        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            TextField {
                id: inputA
                placeholderText: "a"
                Layout.preferredWidth: 80
                validator: IntValidator {}
            }

            TextField {
                id: inputB
                placeholderText: "b"
                Layout.preferredWidth: 80
                validator: IntValidator {}
            }

            Button {
                text: "Add"
                enabled: root.ready
                onClicked: {
                    // logos.watch() delivers the pending reply via callbacks
                    logos.watch(backend.add(parseInt(inputA.text) || 0, parseInt(inputB.text) || 0), function (value) {
                        resultText.text = "Result: " + value;
                    }, function (error) {
                        resultText.text = "Error: " + error;
                    });
                }
            }
        }

        // Shows the return value from the slot call
        Text {
            id: resultText
            text: "Press Add to call the backend"
            color: "#56d364"
            font.pixelSize: 15
        }

        // Shows the auto-synced "status" property from the backend
        Text {
            text: "Backend status: " + root.status
            color: "#8b949e"
            font.pixelSize: 13
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
```

## Step 11: Add Tests (Optional)

Create `tests/ui-tests.mjs` to verify the UI renders. Auto-detected by `mkLogosQmlModule`.

```javascript
import { resolve } from "node:path";

// CI sets LOGOS_QT_MCP automatically; for interactive use: nix build .#test-framework -o result-mcp
const root = process.env.LOGOS_QT_MCP || new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(root, "test-framework/framework.mjs"));

test("{module_name}: loads UI", async (app) => {
  await app.waitFor(
    async () => { await app.expectTexts(["{ModuleName} (C++ backend)"]); },
    { timeout: 15000, interval: 500, description: "UI to load" }
  );
});

test("{module_name}: connects to backend", async (app) => {
  await app.waitFor(
    async () => { await app.expectTexts(["Connected"]); },
    { timeout: 15000, interval: 500, description: "backend to connect" }
  );
});

run();
```

## Step 12: Build and Run

```bash
git add -A
nix build        # runs repc, compiles the Qt plugin → result/lib/{module_name}_plugin.so
nix run .        # launches in logos-standalone-app with ui-host

# Run integration tests
nix build .#integration-test -L
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
  │          ├─ loads the GENERATED plugin .so via QPluginLoader
  │          ├─ generated initLogos() wires LogosAPI into your backend's context
  │          ├─ generated glue calls setBackend() and registers your *Backend
  │          │   class as the QtRO source for the .rep contract
  │          ├─ fires onContextReady() on your backend
  │          └─ prints READY
  │
  ├─ creates QQuickWidget with qml/Main.qml
  ├─ sets "logos" context property (bridge to the QtRO socket)
  └─ QML's logos.module("{module_name}") gets the typed replica:
       SLOT calls → QtRO → your backend; PROP setters → QtRO → the replica
```

The plugin runs in its own process. If it crashes, the host app stays alive.

## Calling Backend Modules (typed) + Event Subscriptions

The headline capability of the universal model: a typed module-event subscription
armed in `onContextReady()` can feed a `.rep` PROP, so the QML label updates with
**no polling and no manual relay**. This is demonstrated end to end in the
`ui-typed-backend` doc-test
(`repos/logos-module-builder/doctests/ui-typed-backend.test.yaml`): a UI module
(`ticker_panel`) whose backend calls a core module (`tick_module`) and subscribes
to its typed `ticked` event.

1. Add the dependency to `metadata.json`:
   ```json
   "dependencies": ["tick_module"]
   ```

2. Add the flake input (name must match the dependency):
   ```nix
   inputs = {
     logos-module-builder.url = "github:logos-co/logos-module-builder";
     tick_module.url = "github:logos-co/logos-tick-module";
   };
   ```

3. Declare the SLOT and the PROP in your `.rep`:
   ```rep
   class {RepClass}
   {
       SLOT(qlonglong bump())
       PROP(qlonglong lastTick=0 READONLY)
   }
   ```

4. In the backend header, override `onContextReady()` alongside your SLOTs:
   ```cpp
   #pragma once
   #include "rep_{module_name}_source.h"
   #include "logos_ui_plugin_context.h"

   class {ModuleName}Backend : public {RepClass}SimpleSource,
                               public LogosUiPluginContext
   {
   public:
       qlonglong bump() override;

       // Fires when ui-host hands the plugin its LogosAPI — the typed
       // dependency surface is live, so arm subscriptions here.
       void onContextReady() override;
   };
   ```

5. In the backend `.cpp`, make typed calls through `modules()` and arm the typed
   event subscription in `onContextReady()`, feeding the PROP via its setter:
   ```cpp
   #include "{module_name}_backend.h"

   // Generated umbrella: LogosModules (behind modules()) from
   // metadata.json#dependencies — typed wrappers + typed event accessors.
   #include "logos_sdk.h"

   qlonglong {ModuleName}Backend::bump()
   {
       return modules().tick_module.bump();
   }

   void {ModuleName}Backend::onContextReady()
   {
       // Typed module-event subscription feeding the .rep PROP: QtRO
       // pushes every setLastTick to the QML replica automatically. The
       // callback arg is Qt-typed (int), matching the rest of the view.
       modules().tick_module.onTicked([this](int count) {
           setLastTick(count);
       });
   }
   ```

6. In QML, call the SLOT with `logos.watch(...)` and read the auto-synced PROP
   directly:
   ```qml
   Button {
       text: "Bump"
       enabled: root.ready
       onClicked: logos.watch(root.backend.bump(),
           function (v) { root.count = String(v) }, function (e) {})
   }

   Text {
       // .rep PROP on the typed replica — auto-synced, no polling.
       text: "Last tick event: " + (root.ready && root.backend ? root.backend.lastTick : "-")
   }
   ```

Compared with the classic UI-backend pattern, the interface class, the plugin
class, `initLogos`, and the manual `LogosModules` construction are all gone — and
the typed **event subscription** feeding a PROP is surface a hand-wired backend
never had.

## Naming Conventions

| Placeholder | Example |
|-------------|---------|
| `{module_name}` | `wallet_ui` |
| `{ModuleName}Backend` | `WalletUiBackend` |
| `{RepClass}` | `WalletUi` |
| `{category}` | `wallet` |

## Final Checklist

- [ ] `metadata.json` has `"type": "ui_qml"`, `"interface": "universal"`, `"view": "qml/Main.qml"`
- [ ] `metadata.json` has `"codegen": { "rep": "src/{module_name}.rep" }`
- [ ] `metadata.json` keeps `"main": "{module_name}_plugin"` (names the generated plugin)
- [ ] `src/{module_name}.rep` declares the view contract (SLOTs / PROPs / SIGNALs, Qt types)
- [ ] `src/{module_name}_backend.{h,cpp}` derives `{RepClass}SimpleSource` + `LogosUiPluginContext` and implements the `.rep` SLOTs
- [ ] PROPs are fed via the repc-generated setters (e.g. `setStatus(...)`)
- [ ] NO hand-written `{module_name}_interface.h` or `{module_name}_plugin.{h,cpp}` — the *Plugin and *Interface classes are generated
- [ ] Backend `.cpp` includes `"logos_sdk.h"` only if it uses `modules()`
- [ ] Typed event subscriptions (if any) are armed in `onContextReady()`
- [ ] `CMakeLists.txt` uses `logos_module(NAME ... REP_FILE src/{module_name}.rep SOURCES ... INCLUDE_DIRS src)` (no `module_config.h`)
- [ ] `flake.nix` uses `mkLogosQmlModule` and lists each dependency as an input matching `metadata.json` `"dependencies"`
- [ ] `src/qml/Main.qml` uses `logos.module("{module_name}")`, `logos.watch(...)` for SLOT replies, reads PROPs directly, and gates on readiness via `isViewModuleReady` + `onViewModuleReadyChanged`
- [ ] `nix build` succeeds (runs repc + compiles)
- [ ] `nix run .` launches the view in logos-standalone-app
- [ ] `tests/ui-tests.mjs` exists with at least a basic load test
- [ ] `nix build .#integration-test -L` passes
