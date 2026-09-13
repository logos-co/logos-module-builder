cmake_minimum_required(VERSION 3.14)
project(OptionalConsumerPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LOGOS_MODULE_BUILDER_ROOT is not set.")
endif()

logos_module(
    NAME optional_consumer
    SOURCES
        src/optional_consumer_impl.h
        src/optional_consumer_impl.cpp
)
