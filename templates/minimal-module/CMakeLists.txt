# Minimal Logos Module CMakeLists.txt
# A universal module: you write only the impl class; the Qt plugin glue
# (interface + plugin classes) is generated from src/minimal_impl.h.

cmake_minimum_required(VERSION 3.14)
project(MinimalModulePlugin LANGUAGES CXX)

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

# Define the module. The generated glue is compiled automatically.
logos_module(
    NAME ${MODULE_NAME}
    SOURCES
        src/minimal_impl.h
        src/minimal_impl.cpp
)
