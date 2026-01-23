# CMake Reference

Complete reference for `LogosModule.cmake` functions and options.

## Overview

`LogosModule.cmake` is a CMake module that handles all the boilerplate for building Logos plugins. It provides:

- Automatic SDK and liblogos detection
- Qt6/Qt5 finding and configuration
- Code generation setup
- External library handling
- Platform-specific RPATH configuration
- Install targets

## Including LogosModule.cmake

```cmake
# Method 1: Via environment variable (recommended for nix builds)
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

# Method 2: Local copy
include(cmake/LogosModule.cmake)

# Method 3: Vendor directory
include(vendor/logos-module-builder/cmake/LogosModule.cmake)
```

## logos_module()

The main function to define a Logos module.

### Syntax

```cmake
logos_module(
    NAME <module_name>
    SOURCES <source_files>...
    [EXTERNAL_LIBS <library_names>...]
    [FIND_PACKAGES <package_names>...]
    [LINK_LIBRARIES <library_names>...]
    [PROTO_FILES <proto_files>...]
)
```

### Parameters

#### NAME (required)
The module name. Used for:
- Output filename: `{NAME}_plugin.so` / `{NAME}_plugin.dylib`
- CMake target name: `{NAME}_module_plugin`

```cmake
logos_module(
    NAME my_module
    ...
)
```

#### SOURCES (required)
List of source files for the module. At minimum, include:
- `src/{name}_interface.h` - Interface definition
- `src/{name}_plugin.h` - Plugin header
- `src/{name}_plugin.cpp` - Plugin implementation

```cmake
logos_module(
    NAME my_module
    SOURCES 
        src/my_module_interface.h
        src/my_module_plugin.h
        src/my_module_plugin.cpp
        src/helper.cpp
        src/utils.cpp
)
```

#### EXTERNAL_LIBS (optional)
External libraries to link. Libraries are searched in `lib/` directory.

```cmake
logos_module(
    NAME my_module
    SOURCES ...
    EXTERNAL_LIBS
        libfoo
        libbar
)
```

The function will:
1. Search for `lib/libfoo.so` or `lib/libfoo.dylib`
2. Add `lib/` to include directories
3. Link the library
4. Copy the library to the output directory
5. Fix install names on macOS

#### FIND_PACKAGES (optional)
CMake packages to find via `find_package()`.

```cmake
logos_module(
    NAME my_module
    SOURCES ...
    FIND_PACKAGES
        Protobuf
        Threads
        ZLIB
)
```

#### LINK_LIBRARIES (optional)
Additional libraries to link (after find_package).

```cmake
logos_module(
    NAME my_module
    SOURCES ...
    FIND_PACKAGES Threads
    LINK_LIBRARIES
        Threads::Threads
        ${ZLIB_LIBRARIES}
)
```

#### PROTO_FILES (optional)
Protocol Buffer `.proto` files to compile.

```cmake
logos_module(
    NAME my_module
    SOURCES ...
    PROTO_FILES
        src/protobuf/message.proto
        src/protobuf/types.proto
)
```

This will:
1. Find Protobuf via `find_package(Protobuf REQUIRED)`
2. Compile each `.proto` file to `.pb.cc` and `.pb.h`
3. Add generated files to sources
4. Add Protobuf include directories
5. Link Protobuf libraries

## Helper Functions

### logos_find_dependencies()

Find and configure Logos SDK and liblogos.

```cmake
logos_find_dependencies()
```

Sets variables:
- `LOGOS_LIBLOGOS_ROOT` - Path to logos-liblogos
- `LOGOS_CPP_SDK_ROOT` - Path to logos-cpp-sdk
- `LOGOS_LIBLOGOS_IS_SOURCE` - TRUE if source layout
- `LOGOS_CPP_SDK_IS_SOURCE` - TRUE if source layout

### logos_find_qt()

Find Qt6 (or Qt5 fallback) with required components.

```cmake
logos_find_qt()
```

Sets:
- `QT_VERSION_MAJOR` - 5 or 6

## Environment Variables

### LOGOS_MODULE_BUILDER_ROOT
Path to logos-module-builder. Set automatically by nix builds.

```bash
export LOGOS_MODULE_BUILDER_ROOT=/path/to/logos-module-builder
```

### LOGOS_CPP_SDK_ROOT
Override path to logos-cpp-sdk.

```bash
export LOGOS_CPP_SDK_ROOT=/path/to/logos-cpp-sdk
```

### LOGOS_LIBLOGOS_ROOT
Override path to logos-liblogos.

```bash
export LOGOS_LIBLOGOS_ROOT=/path/to/logos-liblogos
```

## Generated Targets

For a module named `my_module`, the following are created:

| Target | Description |
|--------|-------------|
| `my_module_module_plugin` | Main library target |
| `run_cpp_generator_my_module` | Code generation target (source layout) |
| `my_module_generate_protos` | Protobuf generation target (if PROTO_FILES) |

## Output Files

```
build/
└── modules/
    ├── my_module_plugin.so      # or .dylib
    ├── libfoo.so                # external libs copied here
    └── ...
```

## Complete Example

```cmake
cmake_minimum_required(VERSION 3.14)
project(ChatModulePlugin LANGUAGES CXX)

# Include the helper
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

# Define the module
logos_module(
    NAME chat
    SOURCES 
        src/chat_interface.h
        src/chat_plugin.h
        src/chat_plugin.cpp
        src/chat_api.cpp
        src/chat_api.h
    FIND_PACKAGES
        Protobuf
        Threads
    PROTO_FILES
        src/protobuf/message.proto
    LINK_LIBRARIES
        absl::base
        absl::strings
)
```

## Customization

For advanced customization, you can use the helper functions directly:

```cmake
cmake_minimum_required(VERSION 3.14)
project(CustomModulePlugin LANGUAGES CXX)

# Include helpers
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

# Find dependencies manually
logos_find_dependencies()
logos_find_qt()

# Create library manually
add_library(my_plugin SHARED
    my_plugin.cpp
    # ... more sources
)

# Custom configuration
target_compile_definitions(my_plugin PRIVATE MY_CUSTOM_DEFINE)
target_include_directories(my_plugin PRIVATE ${CUSTOM_INCLUDE_DIR})

# Link Qt (required)
target_link_libraries(my_plugin PRIVATE 
    Qt${QT_VERSION_MAJOR}::Core 
    Qt${QT_VERSION_MAJOR}::RemoteObjects
)
```
