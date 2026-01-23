# Troubleshooting

Common issues and solutions when using logos-module-builder.

## Build Issues

### "LogosModule.cmake not found"

**Cause:** The CMake module path isn't set correctly.

**Solution:** Ensure `LOGOS_MODULE_BUILDER_ROOT` is set. For nix builds, this is automatic. For local builds:

```bash
export LOGOS_MODULE_BUILDER_ROOT=/path/to/logos-module-builder
```

Or in CMakeLists.txt:
```cmake
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()
```

### "logos-liblogos not found"

**Cause:** The SDK detection failed.

**Solutions:**

1. Set environment variable:
```bash
export LOGOS_LIBLOGOS_ROOT=/path/to/logos-liblogos
```

2. For nix builds, ensure the input is correct:
```nix
inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";
```

3. Check that logos-liblogos has the expected structure:
```bash
ls $LOGOS_LIBLOGOS_ROOT/interface.h  # source layout
# or
ls $LOGOS_LIBLOGOS_ROOT/include/interface.h  # installed layout
```

### "logos-cpp-sdk not found"

Same solutions as above, but for `LOGOS_CPP_SDK_ROOT`.

### "Qt6 not found"

**Cause:** Qt isn't installed or not in PATH.

**Solutions:**

1. For nix, Qt is provided automatically.

2. For local builds:
```bash
# macOS with Homebrew
brew install qt@6
export PATH="/opt/homebrew/opt/qt@6/bin:$PATH"

# Linux
sudo apt install qt6-base-dev qt6-remoteobjects-dev
```

### Code generation fails

**Cause:** `logos-cpp-generator` can't find or load the module.

**Solutions:**

1. Check metadata.json exists and is valid:
```bash
cat metadata.json | jq .
```

2. Ensure the module name matches:
```json
{
  "name": "my_module",  // Must match module.yaml
  "main": "my_module_plugin"  // Must match plugin filename
}
```

3. Check generator output:
```bash
logos-cpp-generator --metadata metadata.json --general-only --output-dir ./test
ls -la ./test/
```

## Runtime Issues

### "Plugin not found"

**Cause:** The plugin library isn't in the expected location.

**Solutions:**

1. Check the output exists:
```bash
ls -la result/lib/
# Should contain my_module_plugin.so or .dylib
```

2. Verify the filename matches metadata.json:
```json
{
  "main": "my_module_plugin"  // Plugin file: my_module_plugin.so
}
```

### "Symbol not found" at load time

**Cause:** Missing library dependency.

**Solutions:**

1. Check library dependencies:
```bash
# macOS
otool -L result/lib/my_module_plugin.dylib

# Linux
ldd result/lib/my_module_plugin.so
```

2. Ensure all external libraries are in the same directory:
```bash
ls -la result/lib/
# Should show plugin AND all external libs
```

3. Check RPATH:
```bash
# macOS
otool -l result/lib/my_module_plugin.dylib | grep -A2 LC_RPATH

# Linux
readelf -d result/lib/my_module_plugin.so | grep RPATH
```

### External library not loaded

**Cause:** Library path issues.

**Solutions:**

1. Verify the library exists:
```bash
ls -la lib/libmylib.*
```

2. Check CMake found it:
```bash
cd build
cmake .. 2>&1 | grep -i mylib
```

3. Verify it's copied to output:
```bash
ls -la build/modules/
```

## Nix-specific Issues

### "attribute 'packages' missing"

**Cause:** Flake structure issue.

**Solution:** Ensure mkLogosModule returns the correct structure:
```nix
outputs = { self, logos-module-builder, ... }:
  logos-module-builder.lib.mkLogosModule {
    src = ./.;
    configFile = ./module.yaml;
  };
# Returns: { packages, devShells, config, metadataJson }
```

### "infinite recursion"

**Cause:** Circular dependencies in nix expressions.

**Solution:** Check that `nixpkgs.follows` is set correctly:
```nix
inputs = {
  logos-module-builder.url = "github:logos-co/logos-module-builder";
  nixpkgs.follows = "logos-module-builder/nixpkgs";  # Important!
};
```

### Build takes forever

**Cause:** Dependencies being rebuilt.

**Solutions:**

1. Use binary cache:
```bash
nix build --option substituters "https://cache.nixos.org"
```

2. Check if inputs are pinned:
```bash
cat flake.lock | jq '.nodes | keys'
```

3. Update flake lock to use cached versions:
```bash
nix flake update
```

### "cannot build on this system"

**Cause:** System not in supported list.

**Solution:** Check that your system is supported:
```nix
# Supported systems
[ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
```

## module.yaml Issues

### "must specify 'name'"

**Cause:** Required field missing.

**Solution:** Add the name field:
```yaml
name: my_module  # Required!
version: 1.0.0
```

### YAML parse error

**Cause:** Invalid YAML syntax.

**Solutions:**

1. Validate YAML:
```bash
python -c "import yaml; yaml.safe_load(open('module.yaml'))"
```

2. Common issues:
```yaml
# Wrong - tabs instead of spaces
name:	my_module

# Wrong - missing quotes for special chars
description: My module: the best

# Correct
description: "My module: the best"
```

### Dependencies not resolved

**Cause:** Module inputs not passed correctly.

**Solution:** Ensure moduleInputs keys match dependency names:
```yaml
# module.yaml
dependencies:
  - waku_module  # This name...
```

```nix
# flake.nix
moduleInputs = {
  waku_module = logos-waku-module;  # ...must match this key
};
```

## Getting Help

1. Check the [examples](../examples/) for working configurations
2. Review the [configuration reference](./configuration.md)
3. Open an issue on [GitHub](https://github.com/logos-co/logos-module-builder/issues)

When reporting issues, include:
- Your `module.yaml`
- Your `flake.nix`
- The full error message
- Your system: `nix-info -m`
