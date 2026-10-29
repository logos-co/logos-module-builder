# Create Logos QML Module Skill

Use this skill when the user wants to create a QML-only Logos UI module (no C++
backend). These modules are packaged and loaded directly in-process by
`logos-basecamp`. They use `mkLogosQmlModule` from
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
| Process isolation | No (QML runs in-process) | Yes (C++ backend runs as a core module, `"backend": "module"`) |
| Backend calls | `logos.callModuleAsync()` to other core modules — **deprecated**: QML will lose core access in the next breaking release; put such calls in a backend | `logos.module()` for own backend replica |
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

Uses `mkLogosQmlModule` from `logos-module-builder`. `nix run .` launches the
module in Basecamp's standalone mode — no Basecamp input needed. Dependencies listed in
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

## Step 7: Add Tests (Optional)

Create `tests/ui-tests.mjs` to verify the UI renders correctly. `mkLogosQmlModule` turns any `.mjs` files in `tests/` into `nix run .#ui-tests`, which runs them headless in Basecamp.

```javascript
import { resolve } from "node:path";

// `nix run .#ui-tests` sets LOGOS_QT_MCP; for interactive use: nix build github:logos-co/logos-basecamp#logos-qt-mcp -o result-mcp
const root = process.env.LOGOS_QT_MCP || new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(root, "test-framework/framework.mjs"));

test("{name}: loads UI", async (app) => {
  await app.waitFor(
    async () => { await app.expectTexts(["Hello from {name}!"]); },
    { timeout: 15000, interval: 500, description: "UI to load" }
  );
});

test("{name}: button visible", async (app) => {
  await app.expectTexts(["Call Backend"]);
});

run();
```

```bash
# Headless run of every tests/*.mjs (also what CI runs)
nix run .#ui-tests

# Interactive: build test framework, then run against running app
nix build github:logos-co/logos-basecamp#logos-qt-mcp -o result-mcp
node tests/ui-tests.mjs
```

## Step 8: Run

No build step needed:

```bash
git add -A
nix run .
```

Modules listed in `dependencies` are loaded automatically. To add more (e.g. an
intent provider), pass a directory holding their install roots:

```bash
nix run . -- --modules-dir ./other-modules
```

### Iterating on the QML

`nix run .` rebuilds on every invocation, even for a one-character QML edit. When
working on the view, build the dev launcher once instead:

```bash
nix build .#ui-dev
./result/bin/run-logos-standalone-ui   # run from the repo root
```

Edit the QML and save — the view re-renders, no rebuild. Declared
dependencies are bundled and loaded exactly as with `nix run .`.

## Final Checklist

- [ ] `metadata.json` is at the module root with `"type": "ui_qml"`
- [ ] `"view"` in `metadata.json` matches the QML filename
- [ ] `"dependencies"` lists any backend modules the QML calls
- [ ] `flake.nix` does not reference `logos-module-builder`
- [ ] `nix run .` launches the QML in Basecamp
- [ ] Backend calls in QML use `logos.callModule(...)` syntax
- [ ] `tests/ui-tests.mjs` exists with at least a basic load test
- [ ] `nix run .#ui-tests` passes
