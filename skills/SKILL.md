# Logos Module Builder Skills

These skills help you create and maintain Logos modules using the logos-module-builder framework.

## Available Skills

### 1. Create Core Module
**File:** [create-logos-module.md](./create-logos-module.md)

Use when the user wants to:
- Create a new backend/logic Logos module (`type: core`)
- Build a plugin for the Logos platform
- Wrap a C/C++ library as a Logos module

**Trigger phrases:**
- "create a new Logos module"
- "make a module for Logos"
- "build a Logos plugin"
- "wrap this library for Logos"

---

### 2. Create ui_qml Module with C++ Backend
**File:** [create-ui-module.md](./create-ui-module.md)

Use when the user wants to:
- Create a ui_qml module with C++ backend + QML view (`type: "ui_qml"` with `main` + `view`)
- Build a process-isolated UI plugin for logos-basecamp
- Preview a UI module with `nix run` via logos-standalone-app

**Trigger phrases:**
- "create a UI module"
- "build a C++ UI plugin"
- "create a module with a UI"
- "create a C++ UI for Logos"
- "create a view module"

---

### 3. Create QML Module
**File:** [create-qml-module.md](./create-qml-module.md)

Use when the user wants to:
- Create a QML UI module (`type: ui_qml`)
- Build a sandboxed QML interface for Logos
- Preview a QML module with `nix run`

**Trigger phrases:**
- "create a QML module"
- "build a QML UI for Logos"
- "create a ui_qml plugin"
- "make a sandboxed UI module"

---

### 4. Update Logos Module
**File:** [update-logos-module.md](./update-logos-module.md)

Use when the user wants to:
- Add methods to an existing module
- Add dependencies to a module
- Add external library support
- Migrate a legacy module to logos-module-builder
- Update module configuration

**Trigger phrases:**
- "add a method to the module"
- "add a dependency"
- "wrap a new library"
- "migrate this module"
- "update the module"

---

## Quick Reference

### Module type comparison

| Type | Builder | Has CMake | Has QML | Process-isolated | Run command |
|------|---------|-----------|---------|------------------|-------------|
| `core` | `mkLogosModule` | Yes | No | Yes (logos_host) | `logoscore` |
| `ui` (legacy widget) | `mkLogosModule` | Yes | No | No | `nix run .` |
| `ui_qml` (with backend) | `mkLogosQmlModule` | Yes | Yes (`view` + `main`) | Yes (ui-host) | `nix run .` |
| `ui_qml` (QML-only) | `mkLogosQmlModule` | No | Yes (`view` only) | No (in-process) | `nix run .` |

### Templates

```bash
# Core module
nix flake init -t github:logos-co/logos-module-builder

# C++ UI module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-backend

# QML module
nix flake init -t github:logos-co/logos-module-builder#ui-qml

# Module with external library
nix flake init -t github:logos-co/logos-module-builder#with-external-lib
```

### Core module structure
```
logos-{name}-module/
├── flake.nix              # Nix configuration (10 lines)
├── metadata.json          # Module config (30 lines)
├── CMakeLists.txt         # Build config (25 lines)
└── src/                   # Source files
    ├── {name}_interface.h
    ├── {name}_plugin.h
    └── {name}_plugin.cpp
```

### C++ UI (view module) structure
```
logos-{name}-module/
├── flake.nix              # Nix configuration (10 lines)
├── metadata.json          # Module config — includes "view" field
├── CMakeLists.txt         # Build config (15 lines)
└── src/
    ├── {name}_interface.h
    ├── {name}_plugin.h
    ├── {name}_plugin.cpp
    └── qml/
        └── Main.qml       # QML view — uses logos.callModuleAsync()
```

### QML module structure
```
logos-{name}-module/
├── flake.nix
├── metadata.json
└── Main.qml
```

### Minimal core flake.nix
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

### C++ UI (view module) flake.nix (with nix run)
```nix
{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Add backend dependencies as inputs:
    # calc_module.url = "github:logos-co/logos-tutorial?dir=logos-calc-module";
  };
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
```

### QML flake.nix (with nix run)
```nix
{
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

## Documentation Links

- [Getting Started](https://github.com/logos-co/logos-module-builder/blob/main/docs/getting-started.md)
- [Configuration Reference](https://github.com/logos-co/logos-module-builder/blob/main/docs/configuration.md)
- [Migration Guide](https://github.com/logos-co/logos-module-builder/blob/main/docs/migration.md)
- [CMake Reference](https://github.com/logos-co/logos-module-builder/blob/main/docs/cmake-reference.md)
- [Troubleshooting](https://github.com/logos-co/logos-module-builder/blob/main/docs/troubleshooting.md)

## Repository

https://github.com/logos-co/logos-module-builder
