# Create Logos QML Module Skill

Use this skill when the user wants to create a Logos QML UI module.  QML modules
have no compilation step — they are pure QML/JS files packaged and run directly
by `logos-standalone-app` or `logos-basecamp`.  They use `mkLogosQmlModule` from
`logos-module-builder` (not `mkLogosModule`).

For C++ Qt widget UI modules see `create-ui-module.md`.
For backend/logic modules see `create-logos-module.md`.

## When to Use

- User asks to "create a QML module"
- User wants to "build a QML UI for Logos"
- User wants to "create a ui_qml plugin"
- User wants to "make a sandboxed UI module"

## Key Differences from C++ UI Modules

| | QML module | C++ UI module |
|---|---|---|
| Compilation | None | CMake / Qt plugin |
| Uses `mkLogosModule` | No | Yes |
| Backend calls | Via `logos` QML bridge | Via `LogosAPI*` in C++ |
| Sandbox | Yes (no network/filesystem) | No |
| `nix build` needed | No | Yes |
| Live edits | Each `nix run` re-evaluates | Requires rebuild |

## Step 1: Gather Requirements

Ask for:
1. **Module name** — snake_case, e.g. `chat_ui`
2. **Description** — what the UI shows/does
3. **Backend dependencies** — core modules this QML calls via the `logos` bridge

## Step 2: Scaffold

```bash
mkdir logos-{name}-module && cd logos-{name}-module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-module
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
  "main": "Main.qml",
  "category": "{category}",
  "dependencies": []
}
```

- `"type": "ui_qml"` — required, tells the host this is a QML module
- `"main"` — the QML entry point filename
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
- [ ] `"main"` in `metadata.json` matches the QML filename
- [ ] `"dependencies"` lists any backend modules the QML calls
- [ ] `flake.nix` does not reference `logos-module-builder`
- [ ] `nix run .` launches the QML in logos-standalone-app
- [ ] Backend calls in QML use `logos.callModule(...)` syntax
