cmake_minimum_required(VERSION 3.14)
project(ExtlibFlakeTests LANGUAGES CXX)

include(LogosTest)

# Reads the library from ../lib, where the builder stages it for the module build too.
logos_test(
    NAME extlib_flake_tests
    MODULE_SOURCES
        ../src/greeting.cpp
    TEST_SOURCES
        main.cpp
        test_greeting.cpp
    EXTRA_INCLUDES
        ../lib
    EXTRA_LINK_LIBS
        ${CMAKE_CURRENT_SOURCE_DIR}/../lib/libextfixture.a
        ${CMAKE_CURRENT_SOURCE_DIR}/../lib/libextfixture_c.a
)
