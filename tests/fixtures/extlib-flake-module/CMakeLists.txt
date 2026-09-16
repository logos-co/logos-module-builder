cmake_minimum_required(VERSION 3.14)
project(ExtlibFlakeModulePlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LOGOS_MODULE_BUILDER_ROOT is not set.")
endif()

logos_module(
    NAME extlib_flake
    SOURCES
        src/extlib_flake_impl.h
        src/extlib_flake_impl.cpp
        src/greeting.h
        src/greeting.cpp
    EXTERNAL_LIBS
        extfixture_c
        extfixture
)
