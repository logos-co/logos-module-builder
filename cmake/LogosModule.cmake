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

Find and configure Logos SDK and logos-module dependencies.
This function sets up include directories and library paths.

Usage:
  logos_find_dependencies()

Sets:
  LOGOS_MODULE_ROOT - Path to logos-module
  LOGOS_CPP_SDK_ROOT - Path to logos-cpp-sdk
  LOGOS_MODULE_IS_SOURCE - TRUE if using source layout
  LOGOS_CPP_SDK_IS_SOURCE - TRUE if using source layout
#]=======================================================================]
function(logos_find_dependencies)
    # Allow override from environment or command line
    if(NOT DEFINED LOGOS_MODULE_ROOT)
        set(_parent_module "${CMAKE_SOURCE_DIR}/../logos-module")
        if(DEFINED ENV{LOGOS_MODULE_ROOT})
            set(LOGOS_MODULE_ROOT "$ENV{LOGOS_MODULE_ROOT}" PARENT_SCOPE)
            set(LOGOS_MODULE_ROOT "$ENV{LOGOS_MODULE_ROOT}")
        elseif(EXISTS "${_parent_module}/src/interface.h")
            set(LOGOS_MODULE_ROOT "${_parent_module}" PARENT_SCOPE)
            set(LOGOS_MODULE_ROOT "${_parent_module}")
        else()
            set(LOGOS_MODULE_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-module" PARENT_SCOPE)
            set(LOGOS_MODULE_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-module")
        endif()
    endif()

    if(NOT DEFINED LOGOS_CPP_SDK_ROOT)
        set(_parent_cpp_sdk "${CMAKE_SOURCE_DIR}/../logos-cpp-sdk")
        if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
            set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}" PARENT_SCOPE)
            set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
        elseif(EXISTS "${_parent_cpp_sdk}/cpp/logos_module_context.h")
            set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}" PARENT_SCOPE)
            set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}")
        else()
            set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk" PARENT_SCOPE)
            set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk")
        endif()
    endif()

    # Check if dependencies are available (support both source and installed layouts)
    set(_module_found FALSE)
    if(EXISTS "${LOGOS_MODULE_ROOT}/src/interface.h")
        set(_module_found TRUE)
        set(LOGOS_MODULE_IS_SOURCE TRUE PARENT_SCOPE)
    elseif(EXISTS "${LOGOS_MODULE_ROOT}/include/module_lib/interface.h")
        set(_module_found TRUE)
        set(LOGOS_MODULE_IS_SOURCE FALSE PARENT_SCOPE)
    endif()

    set(_cpp_sdk_found FALSE)
    # The base SDK is Qt-free/header-only since the qt split — detect it by
    # logos_module_context.h (logos_api.h moved to logos-qt-sdk).
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_module_context.h")
        set(_cpp_sdk_found TRUE)
        set(LOGOS_CPP_SDK_IS_SOURCE TRUE PARENT_SCOPE)
    elseif(EXISTS "${LOGOS_CPP_SDK_ROOT}/include/cpp/logos_module_context.h")
        set(_cpp_sdk_found TRUE)
        set(LOGOS_CPP_SDK_IS_SOURCE FALSE PARENT_SCOPE)
    endif()

    # logos-qt-sdk — the Qt developer layer (LogosAPI, provider glue) every
    # Qt plugin links.
    if(NOT DEFINED LOGOS_QT_SDK_ROOT)
        set(_parent_qt_sdk "${CMAKE_SOURCE_DIR}/../logos-qt-sdk")
        if(DEFINED ENV{LOGOS_QT_SDK_ROOT})
            set(LOGOS_QT_SDK_ROOT "$ENV{LOGOS_QT_SDK_ROOT}" PARENT_SCOPE)
            set(LOGOS_QT_SDK_ROOT "$ENV{LOGOS_QT_SDK_ROOT}")
        elseif(EXISTS "${_parent_qt_sdk}/cpp/logos_api.h")
            set(LOGOS_QT_SDK_ROOT "${_parent_qt_sdk}" PARENT_SCOPE)
            set(LOGOS_QT_SDK_ROOT "${_parent_qt_sdk}")
        else()
            set(LOGOS_QT_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-qt-sdk" PARENT_SCOPE)
            set(LOGOS_QT_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-qt-sdk")
        endif()
    endif()
    set(_qt_sdk_found FALSE)
    if(EXISTS "${LOGOS_QT_SDK_ROOT}/cpp/logos_api.h")
        set(_qt_sdk_found TRUE)
        set(LOGOS_QT_SDK_IS_SOURCE TRUE PARENT_SCOPE)
        set(LOGOS_QT_SDK_IS_SOURCE TRUE)
    elseif(EXISTS "${LOGOS_QT_SDK_ROOT}/include/cpp/logos_api.h")
        set(_qt_sdk_found TRUE)
        set(LOGOS_QT_SDK_IS_SOURCE FALSE PARENT_SCOPE)
        set(LOGOS_QT_SDK_IS_SOURCE FALSE)
    endif()

    # logos-protocol — transports + lp_* C ABI (linked by logos-qt-sdk; also
    # needed directly for its headers and, in source layouts, its sources).
    if(NOT DEFINED LOGOS_PROTOCOL_ROOT)
        set(_parent_protocol "${CMAKE_SOURCE_DIR}/../logos-protocol")
        if(DEFINED ENV{LOGOS_PROTOCOL_ROOT})
            set(LOGOS_PROTOCOL_ROOT "$ENV{LOGOS_PROTOCOL_ROOT}" PARENT_SCOPE)
            set(LOGOS_PROTOCOL_ROOT "$ENV{LOGOS_PROTOCOL_ROOT}")
        elseif(EXISTS "${_parent_protocol}/cpp/logos_protocol.h")
            set(LOGOS_PROTOCOL_ROOT "${_parent_protocol}" PARENT_SCOPE)
            set(LOGOS_PROTOCOL_ROOT "${_parent_protocol}")
        else()
            set(LOGOS_PROTOCOL_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-protocol" PARENT_SCOPE)
            set(LOGOS_PROTOCOL_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-protocol")
        endif()
    endif()
    set(_protocol_found FALSE)
    if(EXISTS "${LOGOS_PROTOCOL_ROOT}/cpp/logos_protocol.h" OR EXISTS "${LOGOS_PROTOCOL_ROOT}/include/cpp/logos_protocol.h")
        set(_protocol_found TRUE)
    endif()

    if(NOT _module_found)
        message(FATAL_ERROR "logos-module not found at ${LOGOS_MODULE_ROOT}. "
                            "Set LOGOS_MODULE_ROOT environment variable or CMake variable.")
    endif()

    if(NOT _cpp_sdk_found)
        message(FATAL_ERROR "logos-cpp-sdk not found at ${LOGOS_CPP_SDK_ROOT}. "
                            "Set LOGOS_CPP_SDK_ROOT environment variable or CMake variable.")
    endif()
    if(NOT _qt_sdk_found)
        message(FATAL_ERROR "logos-qt-sdk not found at ${LOGOS_QT_SDK_ROOT}. "
                            "Set LOGOS_QT_SDK_ROOT environment variable or CMake variable.")
    endif()
    if(NOT _protocol_found)
        message(FATAL_ERROR "logos-protocol not found at ${LOGOS_PROTOCOL_ROOT}. "
                            "Set LOGOS_PROTOCOL_ROOT environment variable or CMake variable.")
    endif()

    message(STATUS "Found logos-module at: ${LOGOS_MODULE_ROOT}")
    message(STATUS "Found logos-cpp-sdk at: ${LOGOS_CPP_SDK_ROOT}")
    message(STATUS "Found logos-qt-sdk at: ${LOGOS_QT_SDK_ROOT}")
    message(STATUS "Found logos-protocol at: ${LOGOS_PROTOCOL_ROOT}")
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
    [LINK_TARGETS <target_names...>]
    [AUTOGEN_DEPENDS <target_names...>]
    [INCLUDE_DIRS <directories...>]
    [PROVIDER_HEADER <relative_path>]
    [REP_FILE <path_to_rep_file>]
    [QML_URI <uri>]
    [QML_TYPE_NAME <type_name>]
  )

Parameters:
  NAME            - (required) Module name
  SOURCES         - (required) Source files for the plugin
  PROVIDER_HEADER - Header file for LogosProviderBase dispatch code generation
  REP_FILE        - Qt .rep file; builds a typed ``<name>_replica_factory`` plugin
                    and adds repc source/replica targets automatically
  QML_URI         - QML import URI for the replica factory (default: Logos.<ClassName>)
  QML_TYPE_NAME   - QML type name for the replica (default: <ClassName> from .rep)

Example:
  logos_module(
    NAME my_module
    SOURCES
      my_module_plugin.cpp
      my_module_plugin.h
      my_module_interface.h
    EXTERNAL_LIBS
      libfoo
    LINK_TARGETS
      my_custom_lib
    AUTOGEN_DEPENDS
      my_custom_lib
    INCLUDE_DIRS
      ${CMAKE_CURRENT_BINARY_DIR}/generated
    REP_FILE
      my_module.rep
  )
#]=======================================================================]
function(logos_module)
    cmake_parse_arguments(
        MODULE
        ""
        "NAME;PROVIDER_HEADER;REP_FILE;QML_URI;QML_TYPE_NAME"
        "SOURCES;EXTERNAL_LIBS;FIND_PACKAGES;LINK_LIBRARIES;LINK_TARGETS;AUTOGEN_DEPENDS;INCLUDE_DIRS"
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

    # Locate metadata.json - check build directory first, then source
    set(METADATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json")
    if(NOT EXISTS "${METADATA_FILE}" AND EXISTS "${CMAKE_CURRENT_BINARY_DIR}/metadata.json")
        set(METADATA_FILE "${CMAKE_CURRENT_BINARY_DIR}/metadata.json")
    endif()

    # Find additional packages
    foreach(pkg ${MODULE_FIND_PACKAGES})
        find_package(${pkg} REQUIRED)
    endforeach()

    # Collect sources
    set(PLUGIN_SOURCES ${MODULE_SOURCES})

    # Add logos-module interface header
    if(LOGOS_MODULE_IS_SOURCE)
        list(APPEND PLUGIN_SOURCES ${LOGOS_MODULE_ROOT}/src/interface.h)
    else()
        list(APPEND PLUGIN_SOURCES ${LOGOS_MODULE_ROOT}/include/module_lib/interface.h)
    endif()

    # Add SDK sources (only if source layout). The Qt developer layer lives
    # in logos-qt-sdk; the transport/protocol layer is linked below (installed
    # find_package, or add_subdirectory for a protocol source checkout).
    if(LOGOS_QT_SDK_IS_SOURCE)
        list(APPEND PLUGIN_SOURCES
            ${LOGOS_QT_SDK_ROOT}/cpp/logos_api.cpp
            ${LOGOS_QT_SDK_ROOT}/cpp/logos_api.h
            ${LOGOS_QT_SDK_ROOT}/cpp/logos_api_provider.cpp
            ${LOGOS_QT_SDK_ROOT}/cpp/logos_api_provider.h
            ${LOGOS_QT_SDK_ROOT}/cpp/logos_provider_object.cpp
            ${LOGOS_QT_SDK_ROOT}/cpp/logos_provider_object.h
            ${LOGOS_QT_SDK_ROOT}/cpp/qt_provider_object.cpp
            ${LOGOS_QT_SDK_ROOT}/cpp/qt_provider_object.h
        )
    endif()
    if(LOGOS_CPP_SDK_IS_SOURCE)
        
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
            COMMAND "${CPP_GENERATOR}" --metadata "${METADATA_FILE}" 
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

    # Provider-header code generation (new LogosProviderBase API)
    if(MODULE_PROVIDER_HEADER)
        set(_PROVIDER_HEADER_ABS "${CMAKE_CURRENT_SOURCE_DIR}/${MODULE_PROVIDER_HEADER}")
        set(_PROVIDER_DISPATCH "${PLUGINS_OUTPUT_DIR}/logos_provider_dispatch.cpp")

        if(LOGOS_CPP_SDK_IS_SOURCE)
            add_custom_command(
                OUTPUT "${_PROVIDER_DISPATCH}"
                COMMAND "${CPP_GENERATOR}" --provider-header "${_PROVIDER_HEADER_ABS}"
                        --output-dir "${PLUGINS_OUTPUT_DIR}"
                DEPENDS "${_PROVIDER_HEADER_ABS}"
                WORKING_DIRECTORY "${LOGOS_DEPS_ROOT}"
                COMMENT "Generating provider dispatch for ${MODULE_NAME}"
                VERBATIM
            )
        endif()

        if(EXISTS "${_PROVIDER_DISPATCH}" OR LOGOS_CPP_SDK_IS_SOURCE)
            list(APPEND PLUGIN_SOURCES "${_PROVIDER_DISPATCH}")
            set_source_files_properties("${_PROVIDER_DISPATCH}" PROPERTIES GENERATED TRUE)
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

    # Link additional targets (e.g., protobuf libs defined by module)
    foreach(target ${MODULE_LINK_TARGETS})
        if(TARGET ${target})
            target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${target})
        else()
            message(WARNING "Target ${target} not found for linking")
        endif()
    endforeach()

    # Set AUTOGEN dependencies if specified (ensures AUTOMOC waits for these targets)
    if(MODULE_AUTOGEN_DEPENDS)
        set_target_properties(${MODULE_NAME}_module_plugin PROPERTIES
            AUTOGEN_TARGET_DEPENDS "${MODULE_AUTOGEN_DEPENDS}"
        )
    endif()

    # Include directories
    target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_BINARY_DIR}
        ${PLUGINS_OUTPUT_DIR}
    )

    # Add include directories based on layout type
    if(LOGOS_MODULE_IS_SOURCE)
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${LOGOS_MODULE_ROOT}/src)
    else()
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${LOGOS_MODULE_ROOT}/include/module_lib)
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
            ${PLUGINS_OUTPUT_DIR}/include
        )
    endif()
    # Qt developer layer (LogosAPI, provider glue, legacy PluginInterface)
    if(LOGOS_QT_SDK_IS_SOURCE)
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
            ${LOGOS_QT_SDK_ROOT}/cpp
            ${LOGOS_QT_SDK_ROOT}/core
        )
    else()
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
            ${LOGOS_QT_SDK_ROOT}/include
            ${LOGOS_QT_SDK_ROOT}/include/cpp
            ${LOGOS_QT_SDK_ROOT}/include/core
        )
    endif()
    # Protocol layer headers (transports, consumer core, lp_* C ABI)
    if(EXISTS "${LOGOS_PROTOCOL_ROOT}/cpp/logos_protocol.h")
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
            ${LOGOS_PROTOCOL_ROOT}/cpp
        )
    else()
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
            ${LOGOS_PROTOCOL_ROOT}/include
            ${LOGOS_PROTOCOL_ROOT}/include/cpp
        )
    endif()

    # Add custom include directories
    foreach(dir ${MODULE_INCLUDE_DIRS})
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${dir})
    endforeach()

    # Link Qt libraries
    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE 
        Qt${QT_VERSION_MAJOR}::Core 
        Qt${QT_VERSION_MAJOR}::RemoteObjects
    )

    # Link the Qt SDK via its exported CMake target so the consumer inherits
    # the full transitive link interface (logos-protocol, and through it
    # OpenSSL, Boost::system, nlohmann_json). The protocol layer must come
    # from an exported target — a bare archive on the link line would leave
    # every Boost.Asio TLS symbol undefined.
    if(NOT LOGOS_QT_SDK_IS_SOURCE)
        find_package(logos-protocol REQUIRED CONFIG
            PATHS ${LOGOS_PROTOCOL_ROOT}/lib/cmake/logos-protocol
            NO_DEFAULT_PATH)
        find_package(logos-qt-sdk REQUIRED CONFIG
            PATHS ${LOGOS_QT_SDK_ROOT}/lib/cmake/logos-qt-sdk
            NO_DEFAULT_PATH)
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE logos-qt-sdk::logos_qt_sdk)
    else()
        # Source-layout qt-sdk: its sources are compiled into the plugin
        # above; the protocol layer is linked installed-or-source here.
        if(EXISTS "${LOGOS_PROTOCOL_ROOT}/lib/cmake/logos-protocol")
            find_package(logos-protocol REQUIRED CONFIG
                PATHS ${LOGOS_PROTOCOL_ROOT}/lib/cmake/logos-protocol
                NO_DEFAULT_PATH)
            target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE logos-protocol::logos_protocol)
        elseif(EXISTS "${LOGOS_PROTOCOL_ROOT}/cpp/CMakeLists.txt")
            if(NOT TARGET logos_protocol)
                add_subdirectory("${LOGOS_PROTOCOL_ROOT}/cpp"
                                 "${CMAKE_BINARY_DIR}/logos-protocol-build")
            endif()
            target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE logos_protocol)
        else()
            message(FATAL_ERROR "logos-protocol not usable at ${LOGOS_PROTOCOL_ROOT} "
                                "(need an installed prefix or a source checkout).")
        endif()
    endif()

    # Qt-free base SDK headers (logos_module_context.h / logos_json.h /
    # logos_result.h → nlohmann_json include path).
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/lib/cmake/logos-cpp-sdk")
        find_package(logos-cpp-sdk REQUIRED CONFIG
            PATHS ${LOGOS_CPP_SDK_ROOT}/lib/cmake/logos-cpp-sdk
            NO_DEFAULT_PATH)
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE logos-cpp-sdk::logos_headers)
    else()
        find_package(nlohmann_json REQUIRED)
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE nlohmann_json::nlohmann_json)
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

    install(DIRECTORY "${PLUGINS_OUTPUT_DIR}/"
        DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-${MODULE_NAME}-module/generated
        OPTIONAL
    )

    # ── Optional: typed replica factory plugin from a .rep file ─────────────
    if(MODULE_REP_FILE)
        _logos_module_add_replica_factory(${MODULE_NAME} "${MODULE_REP_FILE}"
            "${MODULE_QML_URI}" "${MODULE_QML_TYPE_NAME}")
    endif()

    message(STATUS "Logos module ${MODULE_NAME} configured successfully")
endfunction()

# ── Internal: build a <name>_replica_factory Qt plugin from a .rep file ─────
function(_logos_module_add_replica_factory MODULE_NAME REP_FILE QML_URI QML_TYPE_NAME)
    # Need repc replica generation + Qml for qmlRegisterUncreatableMetaObject
    find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core RemoteObjects Qml)

    # Also attach the source-side repc to the plugin target so the backend has
    # the generated SimpleSource base class available.
    if(QT_VERSION_MAJOR EQUAL 6)
        qt6_add_repc_sources(${MODULE_NAME}_module_plugin ${REP_FILE})
    else()
        qt5_add_repc_sources(${MODULE_NAME}_module_plugin ${REP_FILE})
    endif()

    # Parse class name out of the .rep (first `class Foo` line).
    set(_REP_FILE_ABS "${REP_FILE}")
    if(NOT IS_ABSOLUTE "${_REP_FILE_ABS}")
        set(_REP_FILE_ABS "${CMAKE_CURRENT_SOURCE_DIR}/${REP_FILE}")
    endif()
    file(READ "${_REP_FILE_ABS}" _REP_CONTENTS)
    string(REGEX MATCH "class[ \t]+([A-Za-z_][A-Za-z0-9_]*)" _ "${_REP_CONTENTS}")
    set(LOGOS_REP_CLASS "${CMAKE_MATCH_1}")
    if(NOT LOGOS_REP_CLASS)
        message(FATAL_ERROR "logos_module: could not parse class name from ${REP_FILE}")
    endif()

    get_filename_component(LOGOS_REP_BASE "${REP_FILE}" NAME_WE)
    set(LOGOS_FACTORY_CLASS "${LOGOS_REP_CLASS}ReplicaFactoryPlugin")

    if(NOT QML_URI)
        set(QML_URI "Logos.${LOGOS_REP_CLASS}")
    endif()
    if(NOT QML_TYPE_NAME)
        set(QML_TYPE_NAME "${LOGOS_REP_CLASS}")
    endif()
    set(LOGOS_QML_URI "${QML_URI}")
    set(LOGOS_QML_TYPE_NAME "${QML_TYPE_NAME}")

    # Locate the factory h/cpp templates (sibling of this .cmake file).
    set(_TEMPLATE_DIR "${CMAKE_CURRENT_FUNCTION_LIST_DIR}")
    if(NOT EXISTS "${_TEMPLATE_DIR}/LogosViewReplicaFactory.h.in")
        set(_TEMPLATE_DIR "${CMAKE_CURRENT_LIST_DIR}")
    endif()

    set(_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/replica_factory_${MODULE_NAME}")
    file(MAKE_DIRECTORY "${_GEN_DIR}")
    configure_file("${_TEMPLATE_DIR}/LogosViewReplicaFactory.h.in"
                   "${_GEN_DIR}/LogosViewReplicaFactory.h" @ONLY)
    configure_file("${_TEMPLATE_DIR}/LogosViewReplicaFactory.cpp.in"
                   "${_GEN_DIR}/LogosViewReplicaFactory.cpp" @ONLY)

    # Generate the per-module LogosViewPlugin base that plugins inherit
    # from. It implements viewObject() + enableRemoting() so ui-host can
    # drive the plugin via a plain qobject_cast<LogosViewPlugin*> instead
    # of QMetaObject::invokeMethod reflection.
    set(_VIEW_PLUGIN_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/view_plugin_base_${MODULE_NAME}")
    file(MAKE_DIRECTORY "${_VIEW_PLUGIN_GEN_DIR}")
    configure_file("${_TEMPLATE_DIR}/LogosViewPluginBase.h.in"
                   "${_VIEW_PLUGIN_GEN_DIR}/LogosViewPluginBase.h" @ONLY)
    configure_file("${_TEMPLATE_DIR}/LogosViewPluginBase.cpp.in"
                   "${_VIEW_PLUGIN_GEN_DIR}/LogosViewPluginBase.cpp" @ONLY)
    target_sources(${MODULE_NAME}_module_plugin PRIVATE
        "${_VIEW_PLUGIN_GEN_DIR}/LogosViewPluginBase.h"
        "${_VIEW_PLUGIN_GEN_DIR}/LogosViewPluginBase.cpp"
    )
    target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
        "${_VIEW_PLUGIN_GEN_DIR}"
    )
    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE
        Qt${QT_VERSION_MAJOR}::RemoteObjects
    )

    set(_FACTORY_TARGET ${MODULE_NAME}_replica_factory)
    add_library(${_FACTORY_TARGET} SHARED
        "${_GEN_DIR}/LogosViewReplicaFactory.h"
        "${_GEN_DIR}/LogosViewReplicaFactory.cpp"
    )

    set_target_properties(${_FACTORY_TARGET} PROPERTIES
        AUTOMOC ON
        PREFIX ""
        OUTPUT_NAME "${MODULE_NAME}_replica_factory"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
        BUILD_WITH_INSTALL_RPATH TRUE
        SKIP_BUILD_RPATH FALSE
        INSTALL_NAME_DIR "@rpath"
    )
    if(APPLE)
        target_link_options(${_FACTORY_TARGET} PRIVATE "-Wl,-headerpad_max_install_names")
    endif()

    target_include_directories(${_FACTORY_TARGET} PRIVATE
        "${_GEN_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )
    if(QT_VERSION_MAJOR EQUAL 6)
        qt6_add_repc_replicas(${_FACTORY_TARGET} ${REP_FILE})
    else()
        qt5_add_repc_replicas(${_FACTORY_TARGET} ${REP_FILE})
    endif()

    target_link_libraries(${_FACTORY_TARGET} PRIVATE
        Qt${QT_VERSION_MAJOR}::Core
        Qt${QT_VERSION_MAJOR}::RemoteObjects
        Qt${QT_VERSION_MAJOR}::Qml
    )

    if(APPLE)
        set_target_properties(${_FACTORY_TARGET} PROPERTIES
            INSTALL_RPATH "@loader_path"
            INSTALL_NAME_DIR "@rpath"
            BUILD_WITH_INSTALL_NAME_DIR TRUE
        )
        add_custom_command(TARGET ${_FACTORY_TARGET} POST_BUILD
            COMMAND install_name_tool -id "@rpath/${MODULE_NAME}_replica_factory.dylib"
                    $<TARGET_FILE:${_FACTORY_TARGET}>
            COMMENT "Updating library paths for macOS"
        )
    else()
        set_target_properties(${_FACTORY_TARGET} PROPERTIES
            INSTALL_RPATH "$ORIGIN"
            INSTALL_RPATH_USE_LINK_PATH FALSE
        )
    endif()

    install(TARGETS ${_FACTORY_TARGET}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
        RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    )

    message(STATUS "Logos module ${MODULE_NAME}: replica factory plugin from ${REP_FILE} "
                   "(class ${LOGOS_REP_CLASS}, QML ${LOGOS_QML_URI}.${LOGOS_QML_TYPE_NAME})")
endfunction()
