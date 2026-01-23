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

# Define the module with external library
logos_module(
    NAME external_lib
    SOURCES 
        external_lib_interface.h
        external_lib_plugin.h
        external_lib_plugin.cpp
    EXTERNAL_LIBS
        example_lib
)
