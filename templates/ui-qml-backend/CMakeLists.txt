cmake_minimum_required(VERSION 3.14)
project(UiExamplePlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Universal UI module: you write the .rep + the *Backend class. REP_FILE runs
# repc; the generated *Plugin glue in generated_code/ is compiled automatically.
logos_module(
    NAME ui_example
    REP_FILE src/ui_example.rep
    SOURCES
        src/ui_example_backend.h
        src/ui_example_backend.cpp
    INCLUDE_DIRS
        src
)
