cmake_minimum_required(VERSION 3.14)
project(UiExamplePlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

logos_module(
    NAME ui_example
    SOURCES
        src/ui_example_interface.h
        src/ui_example_plugin.h
        src/ui_example_plugin.cpp
)

# Qt Widgets is required for QWidget-based UI modules but not included by
# logos_module() — find and link it explicitly.
find_package(Qt6 REQUIRED COMPONENTS Widgets)
target_link_libraries(ui_example_module_plugin PRIVATE Qt6::Widgets)
