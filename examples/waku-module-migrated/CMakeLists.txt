# Logos Waku Module - Migrated CMakeLists.txt
# This is dramatically simpler than the original 290+ line CMakeLists.txt

cmake_minimum_required(VERSION 3.14)
project(WakuModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Define the module
logos_module(
    NAME waku_module
    SOURCES 
        waku_module_interface.h
        waku_module_plugin.h
        waku_module_plugin.cpp
    EXTERNAL_LIBS
        waku
)
