# External Library Module CMakeLists.txt
# Example showing how to wrap an external C library

cmake_minimum_required(VERSION 3.14)
project(ExternalLibModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Derive module identity from metadata.json
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)
string(JSON MODULE_VERSION GET ${METADATA_JSON} version)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/module_config.h"
    "#pragma once\n"
    "#define MODULE_NAME \"${MODULE_NAME}\"\n"
    "#define MODULE_VERSION \"${MODULE_VERSION}\"\n"
)
include_directories("${CMAKE_CURRENT_BINARY_DIR}")

# Define the module with external library
logos_module(
    NAME ${MODULE_NAME}
    SOURCES
        src/external_lib_interface.h
        src/external_lib_plugin.h
        src/external_lib_plugin.cpp
    EXTERNAL_LIBS
        example_lib
)
