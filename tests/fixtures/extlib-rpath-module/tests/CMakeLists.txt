cmake_minimum_required(VERSION 3.14)
project(ExtlibRpathModuleTests LANGUAGES CXX)

include(LogosTest)

# mkLogosModuleTests must pass one list entry per external lib dir. ELF output
# looks the same either way, so this is the check that fails on Linux.
list(LENGTH CMAKE_INSTALL_RPATH rpath_count)
if(NOT rpath_count EQUAL 2)
    message(FATAL_ERROR "CMAKE_INSTALL_RPATH has ${rpath_count} entries, want 2: ${CMAKE_INSTALL_RPATH}")
endif()

foreach(name rpatha rpathb)
    find_library(${name}_PATH NAMES ${name}
        PATHS ${CMAKE_CURRENT_SOURCE_DIR}/../lib NO_DEFAULT_PATH REQUIRED)
endforeach()

logos_test(
    NAME extlib_rpath_module_tests
    TEST_SOURCES
        main.cpp
        test_rpath.cpp
    EXTRA_INCLUDES
        ../lib
    EXTRA_LINK_LIBS
        ${rpatha_PATH}
        ${rpathb_PATH}
)
