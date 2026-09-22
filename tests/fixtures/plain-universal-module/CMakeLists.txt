cmake_minimum_required(VERSION 3.14)
project(PlainTransportFixture LANGUAGES CXX)

include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)

logos_module(
    NAME ${MODULE_NAME}
    SOURCES
        src/plain_fixture_impl.h
        src/plain_fixture_impl.cpp
)
