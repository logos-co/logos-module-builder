# External Library Module CMakeLists.txt
# A universal module wrapping an external C/C++ library: you write only the
# impl class; the Qt plugin glue is generated from src/external_lib_impl.h.

cmake_minimum_required(VERSION 3.14)
project(ExternalLibModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper.
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Define the module with its external library. The generated glue is compiled
# automatically; EXTERNAL_LIBS links the vendored/built library.
logos_module(
    NAME external_lib
    SOURCES
        src/external_lib_impl.h
        src/external_lib_impl.cpp
    EXTERNAL_LIBS
        example_lib
)
