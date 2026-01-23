# LogosModule.cmake
# Reusable CMake module for building Logos plugins
# This handles all the boilerplate configuration for Logos modules

cmake_minimum_required(VERSION 3.14)

include(GNUInstallDirs)

# Enable CMake automoc for Qt
set(CMAKE_AUTOMOC ON)

#[=======================================================================[.rst:
logos_find_dependencies
-----------------------

Find and configure Logos SDK and liblogos dependencies.
This function sets up include directories and library paths.

Usage:
  logos_find_dependencies()

Sets:
  LOGOS_LIBLOGOS_ROOT - Path to logos-liblogos
  LOGOS_CPP_SDK_ROOT - Path to logos-cpp-sdk
  LOGOS_LIBLOGOS_IS_SOURCE - TRUE if using source layout
  LOGOS_CPP_SDK_IS_SOURCE - TRUE if using source layout
#]=======================================================================]
function(logos_find_dependencies)
    # Allow override from environment or command line
    if(NOT DEFINED LOGOS_LIBLOGOS_ROOT)
        set(_parent_liblogos "${CMAKE_SOURCE_DIR}/../logos-liblogos")
        if(DEFINED ENV{LOGOS_LIBLOGOS_ROOT})
            set(LOGOS_LIBLOGOS_ROOT "$ENV{LOGOS_LIBLOGOS_ROOT}" PARENT_SCOPE)
            set(LOGOS_LIBLOGOS_ROOT "$ENV{LOGOS_LIBLOGOS_ROOT}")
        elseif(EXISTS "${_parent_liblogos}/interface.h")
            set(LOGOS_LIBLOGOS_ROOT "${_parent_liblogos}" PARENT_SCOPE)
            set(LOGOS_LIBLOGOS_ROOT "${_parent_liblogos}")
        else()
            set(LOGOS_LIBLOGOS_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-liblogos" PARENT_SCOPE)
            set(LOGOS_LIBLOGOS_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-liblogos")
        endif()
    endif()

    if(NOT DEFINED LOGOS_CPP_SDK_ROOT)
        set(_parent_cpp_sdk "${CMAKE_SOURCE_DIR}/../logos-cpp-sdk")
        if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
            set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}" PARENT_SCOPE)
            set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
        elseif(EXISTS "${_parent_cpp_sdk}/cpp/logos_api.h")
            set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}" PARENT_SCOPE)
            set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}")
        else()
            set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk" PARENT_SCOPE)
            set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk")
        endif()
    endif()

    # Check if dependencies are available (support both source and installed layouts)
    set(_liblogos_found FALSE)
    if(EXISTS "${LOGOS_LIBLOGOS_ROOT}/interface.h")
        set(_liblogos_found TRUE)
        set(LOGOS_LIBLOGOS_IS_SOURCE TRUE PARENT_SCOPE)
    elseif(EXISTS "${LOGOS_LIBLOGOS_ROOT}/include/interface.h")
        set(_liblogos_found TRUE)
        set(LOGOS_LIBLOGOS_IS_SOURCE FALSE PARENT_SCOPE)
    endif()

    set(_cpp_sdk_found FALSE)
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h")
        set(_cpp_sdk_found TRUE)
        set(LOGOS_CPP_SDK_IS_SOURCE TRUE PARENT_SCOPE)
    elseif(EXISTS "${LOGOS_CPP_SDK_ROOT}/include/cpp/logos_api.h")
        set(_cpp_sdk_found TRUE)
        set(LOGOS_CPP_SDK_IS_SOURCE FALSE PARENT_SCOPE)
    endif()

    if(NOT _liblogos_found)
        message(FATAL_ERROR "logos-liblogos not found at ${LOGOS_LIBLOGOS_ROOT}. "
                            "Set LOGOS_LIBLOGOS_ROOT environment variable or CMake variable.")
    endif()

    if(NOT _cpp_sdk_found)
        message(FATAL_ERROR "logos-cpp-sdk not found at ${LOGOS_CPP_SDK_ROOT}. "
                            "Set LOGOS_CPP_SDK_ROOT environment variable or CMake variable.")
    endif()

    message(STATUS "Found logos-liblogos at: ${LOGOS_LIBLOGOS_ROOT}")
    message(STATUS "Found logos-cpp-sdk at: ${LOGOS_CPP_SDK_ROOT}")
endfunction()

#[=======================================================================[.rst:
logos_find_qt
-------------

Find Qt6 (or Qt5 as fallback) with required components.

Usage:
  logos_find_qt()

Sets:
  QT_VERSION_MAJOR - The major Qt version found (5 or 6)
#]=======================================================================]
function(logos_find_qt)
    if(NOT DEFINED QT_VERSION_MAJOR)
        find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core RemoteObjects)
        if(Qt6_FOUND)
            set(QT_VERSION_MAJOR 6 PARENT_SCOPE)
        else()
            set(QT_VERSION_MAJOR 5 PARENT_SCOPE)
        endif()
    endif()
    find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core RemoteObjects)
endfunction()

#[=======================================================================[.rst:
logos_module
------------

Main function to define a Logos module plugin.

Usage:
  logos_module(
    NAME <module_name>
    SOURCES <source_files...>
    [EXTERNAL_LIBS <lib_names...>]
    [FIND_PACKAGES <package_names...>]
    [LINK_LIBRARIES <library_names...>]
    [PROTO_FILES <proto_files...>]
  )

Example:
  logos_module(
    NAME my_module
    SOURCES 
      my_module_plugin.cpp
      my_module_plugin.h
      my_module_interface.h
    EXTERNAL_LIBS
      libfoo
    FIND_PACKAGES
      Protobuf
    PROTO_FILES
      src/message.proto
  )
#]=======================================================================]
function(logos_module)
    cmake_parse_arguments(
        MODULE
        ""
        "NAME"
        "SOURCES;EXTERNAL_LIBS;FIND_PACKAGES;LINK_LIBRARIES;PROTO_FILES"
        ${ARGN}
    )

    if(NOT MODULE_NAME)
        message(FATAL_ERROR "logos_module: NAME is required")
    endif()

    # Find dependencies
    logos_find_dependencies()
    logos_find_qt()

    # Root for dependencies
    get_filename_component(LOGOS_DEPS_ROOT "${LOGOS_CPP_SDK_ROOT}" DIRECTORY)

    # Set up generated code directory
    if(LOGOS_CPP_SDK_IS_SOURCE)
        set(PLUGINS_OUTPUT_DIR "${CMAKE_BINARY_DIR}/generated_code")
    else()
        # For nix builds, generated files are in source tree
        set(PLUGINS_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/generated_code")
    endif()

    # Find additional packages
    foreach(pkg ${MODULE_FIND_PACKAGES})
        find_package(${pkg} REQUIRED)
    endforeach()

    # Handle protobuf files
    if(MODULE_PROTO_FILES)
        find_package(Protobuf REQUIRED)
        set(PROTO_SRCS "")
        set(PROTO_HDRS "")
        foreach(proto_file ${MODULE_PROTO_FILES})
            get_filename_component(proto_name "${proto_file}" NAME_WE)
            set(proto_src "${CMAKE_CURRENT_BINARY_DIR}/${proto_name}.pb.cc")
            set(proto_hdr "${CMAKE_CURRENT_BINARY_DIR}/${proto_name}.pb.h")
            add_custom_command(
                OUTPUT ${proto_src} ${proto_hdr}
                COMMAND ${Protobuf_PROTOC_EXECUTABLE}
                ARGS --cpp_out=${CMAKE_CURRENT_BINARY_DIR} 
                     -I${CMAKE_CURRENT_SOURCE_DIR} 
                     ${CMAKE_CURRENT_SOURCE_DIR}/${proto_file}
                DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${proto_file}
                COMMENT "Running protoc on ${proto_file}"
                VERBATIM
            )
            list(APPEND PROTO_SRCS ${proto_src})
            list(APPEND PROTO_HDRS ${proto_hdr})
        endforeach()
        add_custom_target(${MODULE_NAME}_generate_protos DEPENDS ${PROTO_SRCS} ${PROTO_HDRS})
    endif()

    # Collect sources
    set(PLUGIN_SOURCES ${MODULE_SOURCES})

    # Add protobuf sources if any
    if(PROTO_SRCS)
        list(APPEND PLUGIN_SOURCES ${PROTO_SRCS} ${PROTO_HDRS})
    endif()

    # Add liblogos interface header
    if(LOGOS_LIBLOGOS_IS_SOURCE)
        list(APPEND PLUGIN_SOURCES ${LOGOS_LIBLOGOS_ROOT}/interface.h)
    else()
        list(APPEND PLUGIN_SOURCES ${LOGOS_LIBLOGOS_ROOT}/include/interface.h)
    endif()

    # Add SDK sources (only if source layout)
    if(LOGOS_CPP_SDK_IS_SOURCE)
        list(APPEND PLUGIN_SOURCES
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_client.cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_client.h
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_consumer.cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_consumer.h
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_provider.cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_provider.h
            ${LOGOS_CPP_SDK_ROOT}/cpp/token_manager.cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/token_manager.h
            ${LOGOS_CPP_SDK_ROOT}/cpp/module_proxy.cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/module_proxy.h
        )
        
        # Add generated logos_sdk.cpp
        list(APPEND PLUGIN_SOURCES ${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp)
        set_source_files_properties(
            ${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp
            PROPERTIES GENERATED TRUE
        )
        
        # Set up code generator
        set(CPP_GENERATOR_BUILD_DIR "${LOGOS_DEPS_ROOT}/build/cpp-generator")
        set(CPP_GENERATOR "${CPP_GENERATOR_BUILD_DIR}/bin/logos-cpp-generator")
        
        if(NOT TARGET cpp_generator_build)
            add_custom_target(cpp_generator_build
                COMMAND bash "${LOGOS_CPP_SDK_ROOT}/cpp-generator/compile.sh"
                WORKING_DIRECTORY "${LOGOS_DEPS_ROOT}"
                COMMENT "Building logos-cpp-generator"
                VERBATIM
            )
        endif()
        
        add_custom_target(run_cpp_generator_${MODULE_NAME}
            COMMAND "${CPP_GENERATOR}" --metadata "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" 
                    --general-only --output-dir "${PLUGINS_OUTPUT_DIR}"
            WORKING_DIRECTORY "${LOGOS_DEPS_ROOT}"
            COMMENT "Running logos-cpp-generator for ${MODULE_NAME}"
            VERBATIM
        )
        add_dependencies(run_cpp_generator_${MODULE_NAME} cpp_generator_build)
    else()
        # For nix builds, logos_sdk.cpp is already generated
        if(EXISTS "${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp")
            list(APPEND PLUGIN_SOURCES ${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp)
        elseif(EXISTS "${PLUGINS_OUTPUT_DIR}/include/logos_sdk.cpp")
            list(APPEND PLUGIN_SOURCES ${PLUGINS_OUTPUT_DIR}/include/logos_sdk.cpp)
        endif()
    endif()

    # Create the plugin library
    add_library(${MODULE_NAME}_module_plugin SHARED ${PLUGIN_SOURCES})

    # Set output name without lib prefix
    set_target_properties(${MODULE_NAME}_module_plugin PROPERTIES
        PREFIX ""
        OUTPUT_NAME "${MODULE_NAME}_plugin"
    )

    # Add dependency on code generator for source layout
    if(LOGOS_CPP_SDK_IS_SOURCE)
        add_dependencies(${MODULE_NAME}_module_plugin run_cpp_generator_${MODULE_NAME})
    endif()

    # Add dependency on protobuf generation
    if(TARGET ${MODULE_NAME}_generate_protos)
        add_dependencies(${MODULE_NAME}_module_plugin ${MODULE_NAME}_generate_protos)
    endif()

    # Include directories
    target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_BINARY_DIR}
        ${PLUGINS_OUTPUT_DIR}
    )

    # Add include directories based on layout type
    if(LOGOS_LIBLOGOS_IS_SOURCE)
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${LOGOS_LIBLOGOS_ROOT})
    else()
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${LOGOS_LIBLOGOS_ROOT}/include)
    endif()

    if(LOGOS_CPP_SDK_IS_SOURCE)
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE 
            ${LOGOS_CPP_SDK_ROOT}/cpp
            ${LOGOS_CPP_SDK_ROOT}/cpp/generated
        )
    else()
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE 
            ${LOGOS_CPP_SDK_ROOT}/include
            ${LOGOS_CPP_SDK_ROOT}/include/cpp
            ${LOGOS_CPP_SDK_ROOT}/include/core
            ${PLUGINS_OUTPUT_DIR}/include
        )
    endif()

    # Link Qt libraries
    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE 
        Qt${QT_VERSION_MAJOR}::Core 
        Qt${QT_VERSION_MAJOR}::RemoteObjects
    )

    # Link SDK library if using installed layout
    if(NOT LOGOS_CPP_SDK_IS_SOURCE)
        find_library(LOGOS_SDK_LIB logos_sdk PATHS ${LOGOS_CPP_SDK_ROOT}/lib NO_DEFAULT_PATH REQUIRED)
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${LOGOS_SDK_LIB})
    endif()

    # Handle external libraries
    foreach(ext_lib ${MODULE_EXTERNAL_LIBS})
        set(EXT_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
        
        # Find the library
        if(APPLE)
            set(EXT_LIB_NAMES lib${ext_lib}.dylib lib${ext_lib}.so ${ext_lib}.dylib ${ext_lib}.so)
        else()
            set(EXT_LIB_NAMES lib${ext_lib}.so lib${ext_lib}.dylib ${ext_lib}.so ${ext_lib}.dylib)
        endif()
        
        find_library(${ext_lib}_PATH NAMES ${EXT_LIB_NAMES} PATHS ${EXT_LIB_DIR} NO_DEFAULT_PATH)
        
        if(${ext_lib}_PATH)
            target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${${ext_lib}_PATH})
            target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${EXT_LIB_DIR})
            
            # Copy to output directory
            get_filename_component(EXT_LIB_FILENAME "${${ext_lib}_PATH}" NAME)
            add_custom_command(TARGET ${MODULE_NAME}_module_plugin PRE_LINK
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    ${${ext_lib}_PATH}
                    ${CMAKE_BINARY_DIR}/modules/${EXT_LIB_FILENAME}
                COMMENT "Copying ${EXT_LIB_FILENAME} to modules directory"
            )
        else()
            message(WARNING "External library ${ext_lib} not found in ${EXT_LIB_DIR}")
        endif()
    endforeach()

    # Link additional libraries
    foreach(lib ${MODULE_LINK_LIBRARIES})
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${lib})
    endforeach()

    # Link protobuf if used
    if(MODULE_PROTO_FILES)
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${Protobuf_INCLUDE_DIRS})
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${Protobuf_LIBRARIES})
    endif()

    # Output directory and RPATH settings
    set_target_properties(${MODULE_NAME}_module_plugin PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
        BUILD_WITH_INSTALL_RPATH TRUE
        SKIP_BUILD_RPATH FALSE
    )

    if(APPLE)
        # Allow unresolved symbols at link time for external libs
        target_link_options(${MODULE_NAME}_module_plugin PRIVATE -undefined dynamic_lookup)
        
        set_target_properties(${MODULE_NAME}_module_plugin PROPERTIES
            INSTALL_RPATH "@loader_path"
            INSTALL_NAME_DIR "@rpath"
            BUILD_WITH_INSTALL_NAME_DIR TRUE
        )

        add_custom_command(TARGET ${MODULE_NAME}_module_plugin POST_BUILD
            COMMAND install_name_tool -id "@rpath/${MODULE_NAME}_plugin.dylib" 
                    $<TARGET_FILE:${MODULE_NAME}_module_plugin>
            COMMENT "Updating library paths for macOS"
        )
    else()
        set_target_properties(${MODULE_NAME}_module_plugin PROPERTIES
            INSTALL_RPATH "$ORIGIN"
            INSTALL_RPATH_USE_LINK_PATH FALSE
        )
    endif()

    # Install targets
    install(TARGETS ${MODULE_NAME}_module_plugin
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
        RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    )

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
            DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-${MODULE_NAME}-module
        )
    endif()

    install(DIRECTORY "${PLUGINS_OUTPUT_DIR}/"
        DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-${MODULE_NAME}-module/generated
        OPTIONAL
    )

    message(STATUS "Logos module ${MODULE_NAME} configured successfully")
endfunction()
