# Rust External Library Module CMakeLists.txt
# The module lives in the Rust crate under rust-lib/; the builder compiles it to
# a staticlib and links it into the plugin, so there are no C++ SOURCES here.
#
# LINK_LIBRARIES is the half of the wiring that metadata.json cannot do: a Rust
# staticlib does not carry its native dependencies, so the C library the crate
# calls has to be named on the PLUGIN's link line too. `nix.packages.runtime`
# in metadata.json puts it on the search path; this names it.

cmake_minimum_required(VERSION 3.14)
project(RustExternalLibModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper.
# For nix builds, this is provided via LOGOS_MODULE_BUILDER_ROOT.
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Derive the module name from metadata.json — single source of truth.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)

logos_module(
    NAME ${MODULE_NAME}
    LINK_LIBRARIES
        z
)
