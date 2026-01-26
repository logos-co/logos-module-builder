# Module Configuration Reference

This document describes all available options in the `module.yaml` configuration file.

## Basic Structure

```yaml
name: my_module
version: 1.0.0
type: core
category: general
description: "My custom Logos module"

dependencies: []
nix_packages:
  build: []
  runtime: []
external_libraries: []
cmake:
  find_packages: []
  extra_sources: []
  proto_files: []
```

> **Note:** The `metadata.json` file is automatically generated from `module.yaml` during the build process. You do not need to create or maintain a separate `metadata.json` file.

## Required Fields

### `name`
**Type:** string  
**Required:** Yes

The module name. This is used for:
- Plugin filename: `{name}_plugin.so` / `{name}_plugin.dylib`
- Nix package name: `logos-{name}-module`
- Interface class naming convention

```yaml
name: my_module
```

## Optional Fields

### `version`
**Type:** string  
**Default:** `"1.0.0"`

The module version in semver format.

```yaml
version: 1.2.3
```

### `type`
**Type:** string  
**Default:** `"core"`

The module type. Currently only `"core"` is supported.

```yaml
type: core
```

### `category`
**Type:** string  
**Default:** `"general"`

The module category for organizational purposes.

Common categories:
- `general` - General purpose modules
- `network` - Network protocol modules (waku, etc.)
- `chat` - Chat/messaging modules
- `wallet` - Wallet/crypto modules
- `integration` - External library integrations

```yaml
category: network
```

### `description`
**Type:** string  
**Default:** `"A Logos module"`

Human-readable description of the module.

```yaml
description: "Waku network protocol module for decentralized messaging"
```

### `dependencies`
**Type:** list of strings  
**Default:** `[]`

List of other Logos modules this module depends on.

These dependencies are:
1. Used to copy generated headers at build time
2. Automatically included in the generated `metadata.json` for runtime loading

```yaml
dependencies:
  - waku_module
  - capability_module
```

### `nix_packages`
**Type:** object  
**Default:** `{ build: [], runtime: [] }`

Additional Nix packages required for building or running the module.

#### `nix_packages.build`
Packages needed only during build (dev dependencies).

#### `nix_packages.runtime`
Packages needed at runtime.

```yaml
nix_packages:
  build:
    - protobuf
    - abseil-cpp
  runtime:
    - zstd
    - krb5
```

Package names can be dotted for nested packages:

```yaml
nix_packages:
  build:
    - qt6.qtbase
    - python3Packages.numpy
```

### `external_libraries`
**Type:** list of objects  
**Default:** `[]`

External C/C++ libraries to wrap. Each library can be provided via:
1. A flake input (built during nix build)
2. A vendor submodule (built via script)
3. Pre-built in the `lib/` directory

#### Flake Input Method

```yaml
external_libraries:
  - name: go_wallet_sdk
    flake_input: "github:status-im/go-wallet-sdk/commit"
    build_command: "make shared-library"
    output_pattern: "build/libgowalletsdk.*"
    go_build: true  # Enable Go build environment
```

#### Vendor Submodule Method

```yaml
external_libraries:
  - name: libwaku
    vendor_path: "vendor/nwaku"
    build_script: "scripts/build-libwaku.sh"
```

#### Pre-built Library

For pre-built libraries, just specify the name and ensure the library is in `lib/`:

```yaml
external_libraries:
  - name: waku
    vendor_path: "lib"  # Library already present
```

#### Library Object Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Library name (required) |
| `flake_input` | string | GitHub URL for flake input |
| `vendor_path` | string | Path to vendor directory |
| `build_command` | string | Command to build the library (default: `make`) |
| `build_script` | string | Path to custom build script |
| `output_pattern` | string | Glob pattern for output files |
| `go_build` | boolean | Enable Go build environment |

### `cmake`
**Type:** object  
**Default:** `{ find_packages: [], extra_sources: [], proto_files: [] }`

Additional CMake configuration options.

#### `cmake.find_packages`
**Type:** list of strings

CMake packages to find via `find_package()`.

```yaml
cmake:
  find_packages:
    - Protobuf
    - Threads
    - ZLIB
```

#### `cmake.extra_sources`
**Type:** list of strings

Additional source files beyond the standard `*_interface.h`, `*_plugin.h`, `*_plugin.cpp`.

```yaml
cmake:
  extra_sources:
    - src/helper.cpp
    - src/utils.cpp
```

#### `cmake.proto_files`
**Type:** list of strings

Protocol Buffer `.proto` files to compile.

```yaml
cmake:
  proto_files:
    - src/protobuf/message.proto
    - src/protobuf/types.proto
```

#### `cmake.extra_include_dirs`
**Type:** list of strings

Additional include directories.

```yaml
cmake:
  extra_include_dirs:
    - lib
    - vendor/include
```

#### `cmake.extra_link_libraries`
**Type:** list of strings

Additional libraries to link.

```yaml
cmake:
  extra_link_libraries:
    - pthread
    - dl
```

## Complete Example

Here's a complete example for a chat module:

```yaml
name: chat
version: 1.0.0
type: core
category: messaging
description: "Chat module using Waku for decentralized messaging"

# Depends on the Waku module
dependencies:
  - waku_module

# Nix packages for protobuf support
nix_packages:
  build:
    - protobuf
    - abseil-cpp
  runtime:
    - zstd
    - krb5

# No external libraries (uses waku via module dependency)
external_libraries: []

# CMake configuration for protobuf
cmake:
  find_packages:
    - Protobuf
    - Threads
  extra_sources:
    - src/chat_api.cpp
    - src/chat_api.h
  proto_files:
    - src/protobuf/message.proto
```
