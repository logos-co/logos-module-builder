# Waku Module - Migrated Example

This is an example showing how the `logos-waku-module` would look after migration to use `logos-module-builder`.

## Comparison

### Before (Original)
```
logos-waku-module/
├── flake.nix                    (~75 lines)
├── CMakeLists.txt               (~290 lines)
├── nix/
│   ├── default.nix              (~40 lines)
│   ├── lib.nix                  (~55 lines)
│   └── include.nix              (~75 lines)
├── waku_module_interface.h
├── waku_module_plugin.h
├── waku_module_plugin.cpp
└── lib/libwaku.*

TOTAL BUILD CONFIG: ~535 lines
```

### After (Migrated)
```
logos-waku-module/
├── flake.nix                    (~15 lines)
├── module.yaml                  (~30 lines)
├── CMakeLists.txt               (~25 lines)
├── src/
│   ├── waku_module_interface.h
│   ├── waku_module_plugin.h
│   └── waku_module_plugin.cpp
└── lib/libwaku.*

TOTAL BUILD CONFIG: ~70 lines
```

**That's an 87% reduction in build configuration code!**

## Key Changes

1. **flake.nix**: Reduced from ~75 lines to ~15 lines
   - Now just imports `logos-module-builder` and calls `mkLogosModule`

2. **module.yaml**: New ~30 line config file
   - Replaces all the nix/* files
   - Declaratively specifies dependencies, external libs, etc.

3. **CMakeLists.txt**: Reduced from ~290 lines to ~25 lines
   - Uses `LogosModule.cmake` helper
   - Just specifies module name, sources, and external libs

4. **Removed**: Entire `nix/` directory
   - `default.nix`, `lib.nix`, `include.nix` no longer needed
   - All handled by `logos-module-builder`

## Building

```bash
# With nix
nix build

# Or with CMake directly
mkdir build && cd build
cmake .. -DLOGOS_CPP_SDK_ROOT=/path/to/sdk -DLOGOS_LIBLOGOS_ROOT=/path/to/liblogos
make
```
