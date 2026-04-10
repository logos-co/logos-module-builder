# Create Logos QML Module Skill

Use this skill when the user wants to create a QML-only Logos UI module (no C++
backend). These modules are packaged and loaded directly in-process by
`logos-standalone-app` or `logos-basecamp`. They use `mkLogosQmlModule` from
`logos-module-builder`.

For modules that also need a C++ backend (process-isolated), see `create-ui-module.md`.
For backend/logic modules (no UI), see `create-logos-module.md`.

## When to Use

- User asks to "create a QML module"
- User wants to "build a QML UI for Logos"
- User wants to "create a ui_qml plugin"
- User wants to "make a sandboxed UI module"
- User wants a **simple UI with no C++ backend** (all logic in QML/JS, calling existing backend modules)

## Key Differences: QML-only vs C++ Backend

Both use `mkLogosQmlModule` and `type: "ui_qml"`. The difference is whether `main` (backend plugin) is declared.

| | QML-only (`view` only) | With backend (`view` + `main`) |
|---|---|---|
| Compilation | None | CMake / Qt plugin |
| Process isolation | No (QML runs in-process) | Yes (C++ backend in `ui-host` process) |
| Backend calls | `logos.callModuleAsync()` to other core modules | `logos.module()` for own backend replica |
| Custom C++ logic | No | Yes (Q_INVOKABLE methods in `.rep` interface) |
| `nix build` needed | No | Yes |

## Step 1: Gather Requirements

Ask for:
1. **Module name** — snake_case, e.g. `chat_ui`
2. **Description** — what the UI shows/does
3. **Backend dependencies** — core modules this QML calls via the `logos` bridge

## Step 2: Scaffold

```bash
mkdir logos-{name}-module && cd logos-{name}-module
nix flake init -t github:logos-co/logos-module-builder#ui-qml
git init && git add -A
```

## Step 3: Directory Structure

```
logos-{name}-module/
├── flake.nix
├── metadata.json
└── Main.qml
```

## Step 4: metadata.json

This file is read at runtime by the host to identify the module type and entry point.

```json
{
  "name": "{name}",
  "version": "1.0.0",
  "type": "ui_qml",
  "view": "Main.qml",
  "category": "{category}",
  "dependencies": []
}
```

- `"type": "ui_qml"` — required, tells the host this is a QML module
- `"view"` — the required QML entry point filename
- `"dependencies"` — backend core modules to load before the UI is shown

## Step 5: Main.qml

```qml
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    width: 400
    height: 300

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Hello from {name}!"
            font.pixelSize: 18
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Call Backend"
            onClicked: {
                // The logos bridge is injected by the host.
                // var result = logos.callModule("my_module", "myMethod", ["arg"])
                console.log("Button clicked")
            }
        }
    }
}
```

### Calling backend modules from QML

The host injects a `logos` context property into the QML environment:

```qml
// Call a core module method
var result = logos.callModule("waku_module", "relayPublish", [topic, message])

// Result is a QVariant — use String(), Number(), etc. as needed
console.log("Result:", String(result))
```

QML modules are sandboxed: no network access, no filesystem access outside the
module directory.

## Step 6: flake.nix

Uses `mkLogosQmlModule` from `logos-module-builder`. The standalone app is bundled
inside `logos-module-builder` — no separate input needed. Dependencies listed in
`metadata.json` are automatically bundled at build time.

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

## Step 7: Run

No build step needed:

```bash
git add -A
nix run .
```

To load backend dependencies alongside the QML module:

```bash
nix run . -- --modules-dir ./modules --load waku_module
```

## Final Checklist

- [ ] `metadata.json` is at the module root with `"type": "ui_qml"`
- [ ] `"view"` in `metadata.json` matches the QML filename
- [ ] `"dependencies"` lists any backend modules the QML calls
- [ ] `flake.nix` does not reference `logos-module-builder`
- [ ] `nix run .` launches the QML in logos-standalone-app
- [ ] Backend calls in QML use `logos.callModule(...)` syntax
