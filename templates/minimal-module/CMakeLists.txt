# Minimal Logos Module CMakeLists.txt
# This is a simple example showing how to use LogosModule.cmake

cmake_minimum_required(VERSION 3.14)
project(MinimalModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper
# For nix builds, this is provided via LOGOS_MODULE_BUILDER_ROOT
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Define the module
logos_module(
    NAME minimal
    SOURCES 
        src/minimal_interface.h
        src/minimal_plugin.h
        src/minimal_plugin.cpp
)
