cmake_minimum_required(VERSION 3.14)
project(TestFrameworkModuleTests LANGUAGES CXX)

include(LogosTest)

logos_test(
    NAME test_framework_module_tests
    MODULE_SOURCES ../src/calculator.cpp
    TEST_SOURCES
        main.cpp
        test_calculator.cpp
    EXTRA_INCLUDES
        ../src
)
