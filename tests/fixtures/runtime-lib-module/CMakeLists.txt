cmake_minimum_required(VERSION 3.14)
project(RuntimeLibProbePlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LOGOS_MODULE_BUILDER_ROOT is not set.")
endif()

logos_module(
    NAME runtime_lib_probe
    SOURCES
        src/runtime_lib_probe_impl.h
        src/runtime_lib_probe_impl.cpp
    LINK_LIBRARIES
        jansson
)
