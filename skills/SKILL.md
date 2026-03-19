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

### 2. Create C++ UI Module
**File:** [create-ui-module.md](./create-ui-module.md)

Use when the user wants to:
- Create a native Qt widget UI module (`type: ui`)
- Build a C++ UI plugin that shows a `QWidget` in logos-basecamp
- Preview a UI module with `nix run` via logos-standalone-app

**Trigger phrases:**
- "create a UI module"
- "build a Qt widget plugin"
- "create a module with a UI"
- "create a C++ UI for Logos"

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

| Type | Uses `mkLogosModule` | Has CMake | Run command |
|------|---------------------|-----------|-------------|
| `core` | Yes | Yes | `logoscore` |
| `ui` (C++ widget) | Yes | Yes | `nix run .` |
| `ui_qml` | No | No | `nix run .` |

### Templates

```bash
# Core module
nix flake init -t github:logos-co/logos-module-builder

# C++ UI module
nix flake init -t github:logos-co/logos-module-builder#ui-module

# QML module
nix flake init -t github:logos-co/logos-module-builder#ui-qml-module

# Module with external library
nix flake init -t github:logos-co/logos-module-builder#with-external-lib
```

### Core / C++ UI module structure
```
logos-{name}-module/
├── flake.nix              # Nix configuration (15 lines)
├── module.yaml            # Module config (30 lines)
├── metadata.json          # Runtime metadata
├── CMakeLists.txt         # Build config (25 lines)
└── src/                   # Source files
    ├── {name}_interface.h
    ├── {name}_plugin.h
    └── {name}_plugin.cpp
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
  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";
  outputs = { self, logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
    };
}
```

### C++ UI flake.nix (with nix run)
```nix
outputs = { self, logos-module-builder, logos-standalone-app, nixpkgs }:
  let
    systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    moduleOutputs = logos-module-builder.lib.mkLogosModule { src = ./.; configFile = ./module.yaml; };
  in moduleOutputs // {
    apps = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        plugin = moduleOutputs.packages.${system}.default;
        # mkLogosModule puts .so in $out/lib/ and metadata.json in $out/share/.
        # logos-standalone needs both in the same directory.
        pluginDir = pkgs.runCommand "plugin-dir" {} ''
          mkdir -p $out
          cp ${plugin}/lib/*_plugin.*  $out/
          cp ${./metadata.json} $out/metadata.json
        '';
        run = pkgs.writeShellScript "run" ''
          exec ${logos-standalone-app.packages.${system}.default}/bin/logos-standalone-app \
            "${pluginDir}" "$@"
        '';
      in { default = { type = "app"; program = "${run}"; }; }
    );
  };
```

### QML flake.nix (with nix run)
```nix
# inputs: logos-cpp-sdk, nixpkgs follows logos-cpp-sdk/nixpkgs, logos-standalone-app
outputs = { self, nixpkgs, logos-cpp-sdk, logos-standalone-app }:
  let
    systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
      pkgs = import nixpkgs { inherit system; };
    });
  in {
    packages = forAllSystems ({ pkgs }: let
      plugin = pkgs.stdenv.mkDerivation {
        pname = "my-qml-plugin"; version = "1.0.0"; src = ./.;
        phases = [ "unpackPhase" "installPhase" ];
        installPhase = ''
          mkdir -p $out/lib
          cp $src/Main.qml $src/metadata.json $out/lib/
        '';
      };
    in { default = plugin; lib = plugin; });
    apps = forAllSystems ({ pkgs }: let
      standalone = logos-standalone-app.packages.${pkgs.system}.default;
      plugin = self.packages.${pkgs.system}.default;
      run = pkgs.writeShellScript "run" ''
        exec ${standalone}/bin/logos-standalone-app "${plugin}/lib" "$@"
      '';
    in { default = { type = "app"; program = "${run}"; }; });
  };
```

## Documentation Links

- [Getting Started](https://github.com/logos-co/logos-module-builder/blob/main/docs/getting-started.md)
- [Configuration Reference](https://github.com/logos-co/logos-module-builder/blob/main/docs/configuration.md)
- [Migration Guide](https://github.com/logos-co/logos-module-builder/blob/main/docs/migration.md)
- [CMake Reference](https://github.com/logos-co/logos-module-builder/blob/main/docs/cmake-reference.md)
- [Troubleshooting](https://github.com/logos-co/logos-module-builder/blob/main/docs/troubleshooting.md)

## Repository

https://github.com/logos-co/logos-module-builder
