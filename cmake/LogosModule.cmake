# LogosModule.cmake
# Reusable CMake module for building Logos plugins
# This handles all the boilerplate configuration for Logos modules
#
# THIS IS THE ONLY COPY. Do not fork it into a backend repo.
#
# logos-plugin-qt used to ship a second copy, and because
# buildCppPlugin.nix set LOGOS_MODULE_BUILDER_ROOT only when the MODULE's own
# repo carried a cmake/LogosModule.cmake (no module does), the two were
# selected by module type: every ui_qml plugin configured with the backend's
# copy while every core module configured with this one. Both compiled, so the
# divergence was invisible — it is how a stale generator, a stale host-runtime
# repoint, and a missing source file each shipped green. Both nix entry points
# (mkLogosModule and buildCppPlugin) now point LOGOS_MODULE_BUILDER_ROOT here
# unconditionally; `logos_module()` echoes the file it came from so a future
# fork shows up in any configure log.

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
  LOGOS_QT_HOST_ROOT - Path the Qt HOST RUNTIME is taken from
  LOGOS_QT_HOST_IS_SOURCE - TRUE if that root is a repo checkout
  LOGOS_QT_HOST_PACKAGE - CMake package name for the host runtime
  LOGOS_QT_HOST_TARGET - Imported target for the host runtime
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
    # logos_module_context.h (logos_api.h lives in logos-qt-host).
    if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_module_context.h")
        set(_cpp_sdk_found TRUE)
        set(LOGOS_CPP_SDK_IS_SOURCE TRUE PARENT_SCOPE)
    elseif(EXISTS "${LOGOS_CPP_SDK_ROOT}/include/cpp/logos_module_context.h")
        set(_cpp_sdk_found TRUE)
        set(LOGOS_CPP_SDK_IS_SOURCE FALSE PARENT_SCOPE)
    endif()

    # logos-qt-sdk — the Qt developer layer. Since the Qt host runtime moved to
    # logos-plugin-qt (see LOGOS_QT_HOST_ROOT below) what this root is still
    # REQUIRED for is the Qt-typed headers that were never part of the host
    # runtime: logos_qt_lp_bridge.h and logos_qt_wire.h (emitted by name into
    # every generated Qt consumer wrapper) and logos_ui_plugin_context.h.
    #
    # Probed by logos_qt_wire.h, deliberately. logos_api.h used to be the
    # discriminator here and is not there any more in EITHER layout: the host
    # split moved it out of cpp/, and the forwarder that kept it in
    # include/cpp/ went away when the consumers were repointed. Probing a name
    # this SDK does not own is how a correct root gets reported as "not found".
    if(NOT DEFINED LOGOS_QT_SDK_ROOT)
        set(_parent_qt_sdk "${CMAKE_SOURCE_DIR}/../logos-qt-sdk")
        if(DEFINED ENV{LOGOS_QT_SDK_ROOT})
            set(LOGOS_QT_SDK_ROOT "$ENV{LOGOS_QT_SDK_ROOT}" PARENT_SCOPE)
            set(LOGOS_QT_SDK_ROOT "$ENV{LOGOS_QT_SDK_ROOT}")
        elseif(EXISTS "${_parent_qt_sdk}/cpp/logos_qt_wire.h")
            set(LOGOS_QT_SDK_ROOT "${_parent_qt_sdk}" PARENT_SCOPE)
            set(LOGOS_QT_SDK_ROOT "${_parent_qt_sdk}")
        else()
            set(LOGOS_QT_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-qt-sdk" PARENT_SCOPE)
            set(LOGOS_QT_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-qt-sdk")
        endif()
    endif()
    set(_qt_sdk_found FALSE)
    if(EXISTS "${LOGOS_QT_SDK_ROOT}/cpp/logos_qt_wire.h")
        set(_qt_sdk_found TRUE)
        set(LOGOS_QT_SDK_IS_SOURCE TRUE PARENT_SCOPE)
        set(LOGOS_QT_SDK_IS_SOURCE TRUE)
    elseif(EXISTS "${LOGOS_QT_SDK_ROOT}/include/cpp/logos_qt_wire.h")
        set(_qt_sdk_found TRUE)
        set(LOGOS_QT_SDK_IS_SOURCE FALSE PARENT_SCOPE)
        set(LOGOS_QT_SDK_IS_SOURCE FALSE)
    endif()

    # logos-qt-host — the Qt HOST RUNTIME a plugin links: LogosAPI (the object
    # handed to initLogos), LogosAPIProvider, LogosProviderBase + the
    # LOGOS_PROVIDER/LOGOS_METHOD macros, the legacy QMetaObject adapter and
    # core/interface.h. It moved out of logos-qt-sdk into logos-plugin-qt and
    # ships as the `logos-qt-host` CMake package. LOGOS_QT_HOST_ROOT is the ONE
    # place it comes from; logos-qt-sdk forwarded the same headers during the
    # migration and no longer does, so there is no qt-sdk fallback to take.
    #
    # There is deliberately no silent branch: a build that cannot name a host
    # runtime stops with FATAL_ERROR rather than quietly producing a plugin
    # with no LogosAPI in it.
    if(NOT DEFINED LOGOS_QT_HOST_ROOT)
        set(_parent_qt_host "${CMAKE_SOURCE_DIR}/../logos-plugin-qt")
        if(DEFINED ENV{LOGOS_QT_HOST_ROOT})
            set(LOGOS_QT_HOST_ROOT "$ENV{LOGOS_QT_HOST_ROOT}")
        elseif(EXISTS "${_parent_qt_host}/cpp/logos_api.h")
            set(LOGOS_QT_HOST_ROOT "${_parent_qt_host}")
        endif()
    endif()
    set(_qt_host_found FALSE)
    if(DEFINED LOGOS_QT_HOST_ROOT)
        if(EXISTS "${LOGOS_QT_HOST_ROOT}/cpp/logos_api.h")
            set(_qt_host_found TRUE)
            set(_qt_host_is_source TRUE)
        elseif(EXISTS "${LOGOS_QT_HOST_ROOT}/include/cpp/logos_api.h")
            set(_qt_host_found TRUE)
            set(_qt_host_is_source FALSE)
        else()
            message(FATAL_ERROR
                "LOGOS_QT_HOST_ROOT is set to ${LOGOS_QT_HOST_ROOT} but no Qt host "
                "runtime is there (expected cpp/logos_api.h in a logos-plugin-qt "
                "checkout, or include/cpp/logos_api.h in an installed logos-qt-host "
                "prefix).")
        endif()
    endif()
    if(_qt_host_found)
        set(LOGOS_QT_HOST_ROOT "${LOGOS_QT_HOST_ROOT}" PARENT_SCOPE)
        set(LOGOS_QT_HOST_IS_SOURCE ${_qt_host_is_source} PARENT_SCOPE)
        set(LOGOS_QT_HOST_PACKAGE "logos-qt-host" PARENT_SCOPE)
        set(LOGOS_QT_HOST_TARGET "logos-qt-host::logos_qt_host" PARENT_SCOPE)
    endif()

    # logos-protocol — transports + lp_* C ABI (linked by the Qt host runtime;
    # needed directly for its headers and, in source layouts, its library).
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
    if(NOT _qt_host_found)
        message(FATAL_ERROR "No Qt host runtime found. Set LOGOS_QT_HOST_ROOT to an "
                            "installed logos-qt-host prefix (or a logos-plugin-qt "
                            "checkout) via environment or CMake variable. "
                            "LOGOS_QT_SDK_ROOT is not a substitute: logos-qt-sdk no "
                            "longer carries the host runtime's headers.")
    endif()
    if(NOT _protocol_found)
        message(FATAL_ERROR "logos-protocol not found at ${LOGOS_PROTOCOL_ROOT}. "
                            "Set LOGOS_PROTOCOL_ROOT environment variable or CMake variable.")
    endif()

    message(STATUS "Found logos-module at: ${LOGOS_MODULE_ROOT}")
    message(STATUS "Found logos-cpp-sdk at: ${LOGOS_CPP_SDK_ROOT}")
    message(STATUS "Found logos-qt-sdk at: ${LOGOS_QT_SDK_ROOT}")
    message(STATUS "Found logos-protocol at: ${LOGOS_PROTOCOL_ROOT}")
    message(STATUS "Qt host runtime: logos-qt-host::logos_qt_host at ${LOGOS_QT_HOST_ROOT}")
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
# NOTE: this MUST be a macro, not a function. Qt's mingw
# Qt6EntryPointMinGW32Target.cmake guards itself with a bare include_guard()
# (variable-scoped) while creating a DIRECTORY-scoped imported target. If the
# first find_package(Qt6) runs inside a function scope, the guard variable and
# every <pkg>_FOUND marker die at endfunction() while the EntryPointMinGW32
# target survives, so the next find_package(Qt6) (via logos-protocol's /
# logos-qt-sdk's find_dependency) re-enters and hits
# "add_library cannot create imported target EntryPointMinGW32".
macro(logos_find_qt)
    if(NOT DEFINED QT_VERSION_MAJOR)
        find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core RemoteObjects)
        if(Qt6_FOUND)
            set(QT_VERSION_MAJOR 6)
        else()
            set(QT_VERSION_MAJOR 5)
        endif()
    endif()
    find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core RemoteObjects)
endmacro()

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
    [REP_FILE <path_to_rep_file>]
    [QML_URI <uri>]
    [QML_TYPE_NAME <type_name>]
  )

Parameters:
  NAME            - (required) Module name
  SOURCES         - (required) Source files for the plugin
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
        "NAME;REP_FILE;QML_URI;QML_TYPE_NAME"
        "SOURCES;EXTERNAL_LIBS;FIND_PACKAGES;LINK_LIBRARIES;LINK_TARGETS;AUTOGEN_DEPENDS;INCLUDE_DIRS"
        ${ARGN}
    )

    if(NOT MODULE_NAME)
        message(FATAL_ERROR "logos_module: NAME is required")
    endif()

    # Which LogosModule.cmake configured this module. There is exactly one, and
    # this line is how that stays true: a second copy anywhere in the tree names
    # itself here instead of being silently selected.
    message(STATUS "LogosModule.cmake: ${CMAKE_CURRENT_FUNCTION_LIST_FILE}")

    # Find dependencies
    logos_find_dependencies()
    logos_find_qt()

    # Embed metadata next to plugin sources (AUTOMOC / Q_PLUGIN_METADATA)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json")
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
            "${CMAKE_CURRENT_BINARY_DIR}/metadata.json"
            COPYONLY
        )
    endif()

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

    # Add Qt HOST RUNTIME sources (only if that root is a repo checkout — an
    # installed prefix ships them as a static library, linked below). The
    # transport/consumer core (token_manager, module_proxy, api_client/consumer)
    # lives in the logos-protocol LIBRARY and is linked, never compiled in.
    # LOGOS_QT_HOST_ROOT is a logos-plugin-qt checkout since the host-runtime
    # split; it carries these files at exactly the paths logos-qt-sdk's did.
    if(LOGOS_QT_HOST_IS_SOURCE)
        list(APPEND PLUGIN_SOURCES
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_api.cpp
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_api.h
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_api_provider.cpp
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_api_provider.h
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_provider_object.cpp
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_provider_object.h
            ${LOGOS_QT_HOST_ROOT}/cpp/qt_provider_object.cpp
            ${LOGOS_QT_HOST_ROOT}/cpp/qt_provider_object.h
            # qt_provider_object.cpp's dispatch calls into this; omitting it is
            # an undefined symbol at link time, not a configure error.
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_qt_arg_decode.cpp
            ${LOGOS_QT_HOST_ROOT}/cpp/logos_qt_arg_decode.h
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
        
        # LOGOS_API_STYLE selects between Qt-typed and lp (Qt-free,
        # logos-protocol C ABI) wrapper signatures on the generated
        # `<Module>` client class. Defaults to "qt" — every existing
        # handcrafted module keeps its Qt-typed LogosModules. Core
        # universal modules (those declaring `interface: "universal"`
        # in metadata.json, minus `type: ui_qml` view backends) get this
        # set to "lp" automatically by mkLogosModule.nix.
        if(NOT DEFINED LOGOS_API_STYLE OR LOGOS_API_STYLE STREQUAL "")
            set(LOGOS_API_STYLE "qt")
        endif()
        add_custom_target(run_cpp_generator_${MODULE_NAME}
            COMMAND "${CPP_GENERATOR}" --metadata "${METADATA_FILE}"
                    --general-only --api-style "${LOGOS_API_STYLE}"
                    --output-dir "${PLUGINS_OUTPUT_DIR}"
            WORKING_DIRECTORY "${LOGOS_DEPS_ROOT}"
            COMMENT "Running logos-cpp-generator for ${MODULE_NAME} (api-style=${LOGOS_API_STYLE})"
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

    # Universal UI backends (type: ui_qml + interface: universal): the
    # generated glue plugin — derived from the impl class by
    # logos-qt-generator, carrying Q_PLUGIN_METADATA and the initLogos
    # wiring — must be compiled into the target (the .h rides along so
    # AUTOMOC picks up the plugin metadata).
    if(EXISTS "${PLUGINS_OUTPUT_DIR}/${MODULE_NAME}_ui_glue.cpp")
        list(APPEND PLUGIN_SOURCES
            ${PLUGINS_OUTPUT_DIR}/${MODULE_NAME}_ui_glue.cpp
            ${PLUGINS_OUTPUT_DIR}/${MODULE_NAME}_ui_glue.h)
    endif()


    # Create the plugin library
    add_library(${MODULE_NAME}_module_plugin SHARED ${PLUGIN_SOURCES})

    # Pre-generated sources from logos-cpp-generator (Nix preConfigure, universal/provider modules)
    set(_LOGOS_GEN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/generated_code")
    if(IS_DIRECTORY "${_LOGOS_GEN_DIR}")
        file(GLOB _LOGOS_GEN_CPPS CONFIGURE_DEPENDS "${_LOGOS_GEN_DIR}/*.cpp")
        file(GLOB _LOGOS_GEN_HS CONFIGURE_DEPENDS "${_LOGOS_GEN_DIR}/*.h")
        # Exclude files that are #include'd by logos_sdk.cpp (not compiled separately):
        # logos_sdk.cpp and per-dependency *_api.cpp files. core_manager
        # is no longer generated (universal modules expose only their
        # declared dependencies; apps that need to manage the core use
        # liblogos' C API directly).
        list(FILTER _LOGOS_GEN_CPPS EXCLUDE REGEX ".*/(logos_sdk|.*_api)\\.cpp$")
        if(_LOGOS_GEN_CPPS OR _LOGOS_GEN_HS)
            target_sources(${MODULE_NAME}_module_plugin PRIVATE ${_LOGOS_GEN_CPPS} ${_LOGOS_GEN_HS})
            target_include_directories(${MODULE_NAME}_module_plugin PRIVATE "${_LOGOS_GEN_DIR}")
        endif()
    endif()

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
            message(FATAL_ERROR
                "LINK_TARGETS target '${target}' was not defined before "
                "logos_module(). Define it (e.g. add_library(${target} ...)) or "
                "remove it from LINK_TARGETS. Refusing to silently drop a "
                "configured link target.")
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
    # Qt HOST RUNTIME headers (LogosAPI, provider glue, legacy PluginInterface
    # at core/interface.h). Both roots have the same two shapes — a repo
    # checkout (cpp/, core/) and an installed prefix (include/cpp,
    # include/core) — so only the root changes with the repoint.
    if(LOGOS_QT_HOST_IS_SOURCE)
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
            ${LOGOS_QT_HOST_ROOT}/cpp
            ${LOGOS_QT_HOST_ROOT}/core
        )
    else()
        target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
            ${LOGOS_QT_HOST_ROOT}/include
            ${LOGOS_QT_HOST_ROOT}/include/cpp
            ${LOGOS_QT_HOST_ROOT}/include/core
        )
    endif()
    # logos_ui_plugin_context.h, from logos-view-module — and FIRST, ahead of
    # the logos-qt-sdk root below.
    #
    # As of the qt-sdk pin above, logos-view-module is the ONLY repo that ships
    # this header, so ordering is no longer what decides which copy wins. It
    # stays BEFORE anyway: this repo pins the two independently, and an older
    # qt-sdk pin — a rollback, a branch, a consumer overriding the input — brings
    # the duplicate straight back. Belt-and-braces now, load-bearing again the
    # moment those pins disagree. This header and the view glue emitter are one MATCHED PAIR: the
    # emitted `<name>_ui_glue.cpp` calls
    # `_logos_codegen_::maybeUiPluginAboutToUnload(...)`, which only this header
    # declares. Both now ship from logos-view-module under ONE pin, so they
    # cannot disagree. logos-qt-sdk's copy is pinned SEPARATELY by this repo's
    # flake.lock and drifts independently — resolving to it is how a build gets
    # an emitter from one revision and a context header from another, and the
    # symptom is a compile error inside generated code, far from the pin that
    # caused it.
    #
    # Passed as a cache variable by every nix build (LOGOS_VIEW_INCLUDE_DIR) and
    # as an env var for a hand-run cmake in a dev shell, the same two channels
    # LOGOS_VIEW_TEMPLATE_DIR uses.
    if(NOT LOGOS_VIEW_INCLUDE_DIR AND DEFINED ENV{LOGOS_VIEW_INCLUDE_DIR})
        set(LOGOS_VIEW_INCLUDE_DIR "$ENV{LOGOS_VIEW_INCLUDE_DIR}")
    endif()
    if(LOGOS_VIEW_INCLUDE_DIR)
        # BEFORE, not the default append: a stale logos_ui_plugin_context.h on
        # the qt-sdk root must lose, not win by accident of ordering.
        target_include_directories(${MODULE_NAME}_module_plugin BEFORE PRIVATE
            ${LOGOS_VIEW_INCLUDE_DIR}/include
        )
    endif()
    # The Qt-typed headers logos-qt-sdk owns — logos_qt_lp_bridge.h /
    # logos_qt_wire.h (emitted by name into generated Qt consumer wrappers).
    # It no longer ships logos_ui_plugin_context.h; logos-view-module is its sole
    # owner, and the block above stays ordered ahead of this one so an older
    # qt-sdk pin that still carries a copy cannot win.
    if(NOT "${LOGOS_QT_SDK_ROOT}" STREQUAL "${LOGOS_QT_HOST_ROOT}")
        if(LOGOS_QT_SDK_IS_SOURCE)
            target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
                ${LOGOS_QT_SDK_ROOT}/cpp
            )
        else()
            target_include_directories(${MODULE_NAME}_module_plugin PRIVATE
                ${LOGOS_QT_SDK_ROOT}/include
                ${LOGOS_QT_SDK_ROOT}/include/cpp
            )
        endif()
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

    # Link the Qt HOST RUNTIME via its exported CMake target so the consumer
    # inherits the full transitive link interface (logos-protocol, and through
    # it OpenSSL, Boost::system, nlohmann_json). The protocol layer must come
    # from an exported target — a bare archive on the link line would leave
    # every Boost.Asio TLS symbol undefined.
    if(NOT LOGOS_QT_HOST_IS_SOURCE)
        find_package(logos-protocol REQUIRED CONFIG
            PATHS ${LOGOS_PROTOCOL_ROOT}/lib/cmake/logos-protocol
            NO_DEFAULT_PATH)
        find_package(${LOGOS_QT_HOST_PACKAGE} REQUIRED CONFIG
            PATHS ${LOGOS_QT_HOST_ROOT}/lib/cmake/${LOGOS_QT_HOST_PACKAGE}
            NO_DEFAULT_PATH)
        # find_package(... REQUIRED) already stops on a missing package, but a
        # package that resolves without defining its target would leave the
        # plugin with no host runtime and no diagnostic. Refuse that too.
        if(NOT TARGET ${LOGOS_QT_HOST_TARGET})
            message(FATAL_ERROR
                "${LOGOS_QT_HOST_PACKAGE} was found at ${LOGOS_QT_HOST_ROOT} but did not "
                "define ${LOGOS_QT_HOST_TARGET}. The Qt host runtime is not optional — "
                "refusing to link ${MODULE_NAME}_module_plugin without it.")
        endif()
        target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${LOGOS_QT_HOST_TARGET})
    else()
        # Source-layout host runtime: its sources are compiled into the plugin
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
        # Allow nix dev shell (or any caller) to point directly at a store path
        # by exporting LOGOS_EXT_ROOT_<NAME>=/nix/store/…, skipping the ./lib/ staging copy.
        # The expected format is a package root laid out as lib/+include/ (a Nix
        # derivation), unlike the ./lib/ fallback, which is one flat directory
        # holding both the library and its headers.
        string(TOUPPER "${ext_lib}" _ext_lib_upper)
        set(_ext_root_var "LOGOS_EXT_ROOT_${_ext_lib_upper}")
        if(DEFINED ENV{${_ext_root_var}})
            set(EXT_LIB_DIR "$ENV{${_ext_root_var}}/lib")
            set(EXT_INCLUDE_DIR "$ENV{${_ext_root_var}}/include")
        else()
            set(EXT_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
            set(EXT_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
        endif()

        # Find the library (prefer shared, fall back to static).
        # On Windows a shared library is TWO files: you LINK against the import
        # library (lib<x>.dll.a under mingw) and SHIP the .dll. Neither spelling
        # appeared in these lists, so every external-library module failed to
        # cross-compile with "was not found in .../lib".
        if(WIN32)
            set(EXT_LIB_NAMES lib${ext_lib}.dll.a ${ext_lib}.dll.a lib${ext_lib}.lib ${ext_lib}.lib lib${ext_lib}.dll ${ext_lib}.dll lib${ext_lib}.a ${ext_lib}.a)
        elseif(APPLE)
            set(EXT_LIB_NAMES lib${ext_lib}.dylib lib${ext_lib}.so ${ext_lib}.dylib ${ext_lib}.so lib${ext_lib}.a ${ext_lib}.a)
        else()
            set(EXT_LIB_NAMES lib${ext_lib}.so lib${ext_lib}.dylib ${ext_lib}.so ${ext_lib}.dylib lib${ext_lib}.a ${ext_lib}.a)
        endif()

        find_library(${ext_lib}_PATH NAMES ${EXT_LIB_NAMES} PATHS ${EXT_LIB_DIR} NO_DEFAULT_PATH)

        if(${ext_lib}_PATH)
            target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${${ext_lib}_PATH})
            target_include_directories(${MODULE_NAME}_module_plugin PRIVATE ${EXT_INCLUDE_DIR})

            # Copy shared libraries to output directory (static archives are
            # linked in, no runtime copy needed).
            #
            # Windows needs care: what we just linked is usually the IMPORT
            # library lib<x>.dll.a, whose name ends in ".a" and would therefore
            # be mistaken for a static archive and skipped -- shipping a plugin
            # with no runtime DLL beside it. Resolve the companion .dll and copy
            # THAT instead.
            get_filename_component(EXT_LIB_FILENAME "${${ext_lib}_PATH}" NAME)
            set(EXT_RUNTIME_LIB "")
            if(EXT_LIB_FILENAME MATCHES "\\.dll\\.a$" OR EXT_LIB_FILENAME MATCHES "\\.lib$")
                get_filename_component(_ext_dir "${${ext_lib}_PATH}" DIRECTORY)
                foreach(_dll_name lib${ext_lib}.dll ${ext_lib}.dll)
                    if(EXISTS "${_ext_dir}/${_dll_name}")
                        set(EXT_RUNTIME_LIB "${_ext_dir}/${_dll_name}")
                        set(EXT_LIB_FILENAME "${_dll_name}")
                        break()
                    endif()
                endforeach()
                if(NOT EXT_RUNTIME_LIB)
                    message(FATAL_ERROR
                        "External library '${ext_lib}': linked ${EXT_LIB_FILENAME} but found no "
                        "companion DLL in ${_ext_dir}. The plugin would build and then fail to "
                        "load at runtime, so refusing to continue.")
                endif()
            elseif(NOT EXT_LIB_FILENAME MATCHES "\\.a$")
                set(EXT_RUNTIME_LIB "${${ext_lib}_PATH}")
            endif()
            if(EXT_RUNTIME_LIB)
                add_custom_command(TARGET ${MODULE_NAME}_module_plugin PRE_LINK
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        ${EXT_RUNTIME_LIB}
                        ${CMAKE_BINARY_DIR}/modules/${EXT_LIB_FILENAME}
                    COMMENT "Copying ${EXT_LIB_FILENAME} to modules directory"
                )
            endif()
        else()
            message(FATAL_ERROR
                "External library '${ext_lib}' (declared in EXTERNAL_LIBS / "
                "metadata.json nix.external_libraries) was not found in "
                "${EXT_LIB_DIR}. A configured external library must be present at "
                "build time — check its vendor_path, externalLibInputs, or "
                "build_command/output_pattern. Refusing to build a plugin with a "
                "missing dependency.")
        endif()
    endforeach()

    # Go/cgo static archives (whole-archive link). Set by mkLogosModule when metadata lists go_build externals.
    if(DEFINED LOGOS_MODULE_GO_STATIC_LIBS AND NOT LOGOS_MODULE_GO_STATIC_LIBS STREQUAL "")
        set(EXT_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
        foreach(_golib IN LISTS LOGOS_MODULE_GO_STATIC_LIBS)
            if(_golib STREQUAL "")
                continue()
            endif()
            find_library(_LOGOS_GO_${_golib}
                NAMES lib${_golib}.a lib${_golib}.lib ${_golib}.a ${_golib}.lib
                PATHS ${EXT_LIB_DIR} NO_DEFAULT_PATH)
            if(_LOGOS_GO_${_golib})
                target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${_LOGOS_GO_${_golib}})
                if(APPLE)
                    target_link_options(${MODULE_NAME}_module_plugin PRIVATE -Wl,-force_load ${_LOGOS_GO_${_golib}})
                    target_link_libraries(${MODULE_NAME}_module_plugin PUBLIC "-framework CoreFoundation" "-framework Security")
                else()
                    target_link_options(${MODULE_NAME}_module_plugin PRIVATE
                        -Wl,--whole-archive ${_LOGOS_GO_${_golib}} -Wl,--no-whole-archive)
                endif()
            else()
                message(FATAL_ERROR
                    "Go static library '${_golib}' (a go_build external library) "
                    "was not found in ${EXT_LIB_DIR}. Check the external build "
                    "produced lib${_golib}.a. Refusing to build a plugin with a "
                    "missing dependency.")
            endif()
        endforeach()
    endif()

    # Rust static archives. Set by mkLogosModule when a cdylib module is authored
    # in Rust (metadata codegen.rust): the builder compiles the crate to a
    # staticlib and stages it in lib/. The archive provides the logos_module_*
    # exports the generated Qt glue calls; its own lp_* undefineds resolve against
    # the logos-protocol archive already linked above (via logos-qt-sdk). Plain
    # link (NOT whole-archive: the Rust install hook is pulled in lazily by a
    # symbol reference), with the protocol target re-mentioned AFTER the archive
    # so single-pass linkers (GNU ld) see it later on the line — one protocol
    # stack shared by the glue and the Rust code.
    if(DEFINED LOGOS_MODULE_RUST_STATIC_LIBS AND NOT LOGOS_MODULE_RUST_STATIC_LIBS STREQUAL "")
        set(_LOGOS_RUST_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
        foreach(_rustlib IN LISTS LOGOS_MODULE_RUST_STATIC_LIBS)
            if(_rustlib STREQUAL "")
                continue()
            endif()
            find_library(_LOGOS_RUST_${_rustlib}
                NAMES lib${_rustlib}.a ${_rustlib}
                PATHS ${_LOGOS_RUST_LIB_DIR} NO_DEFAULT_PATH)
            if(_LOGOS_RUST_${_rustlib})
                target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE ${_LOGOS_RUST_${_rustlib}})
                if(TARGET logos-protocol::logos_protocol)
                    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE logos-protocol::logos_protocol)
                elseif(TARGET logos_protocol)
                    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE logos_protocol)
                endif()
                # Native libraries Rust's `std` leaves undefined in a staticlib.
                # These are per-platform and NOT interchangeable: the old
                # two-way APPLE/else split silently meant "else == Linux" and
                # put `pthread dl` on the Windows link line, where `dl` does not
                # exist at all and `pthread` lives in a separate
                # mingw_w64-pthreads package that is not on the sysroot search
                # path -- so a Rust module could never link for Windows.
                if(APPLE)
                    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE
                        "-framework CoreFoundation" "-framework Security")
                elseif(WIN32)
                    # Derived from the archive's own undefined symbols, not
                    # guessed: BCryptGenRandom -> bcrypt; Nt*/Rtl* (file I/O and
                    # the unwinder) -> ntdll; GetUserProfileDirectoryW ->
                    # userenv; WaitOnAddress/WakeByAddress* -> synchronization
                    # (kernel32's mingw import lib does not carry them); the
                    # WSA*/socket set -> ws2_32. `ProcessPrng` needs nothing
                    # here -- std bundles its own bcryptprimitives import stubs
                    # inside the archive. Qt happens to drag several of these in
                    # already, but naming them keeps the Rust link independent
                    # of Qt's link interface.
                    # `pthread` is winpthreads, which mkLogosModule adds as a
                    # build input for a cross Rust module (see the note there).
                    # It is NOT part of the mingw sysroot -- nixpkgs builds mingw
                    # against mcfgthread -- but a crate's vendored C can still
                    # want it: aws-lc-sys compiles aws-lc's thread_pthread.c.
                    # ld pulls archive members on demand, so naming it costs
                    # nothing for a module that references no pthread symbol.
                    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE
                        ws2_32 bcrypt ntdll userenv synchronization advapi32 pthread)
                else()
                    target_link_libraries(${MODULE_NAME}_module_plugin PRIVATE pthread dl)
                endif()
            else()
                message(FATAL_ERROR
                    "Rust static library '${_rustlib}' (a codegen.rust module) was not "
                    "found in ${_LOGOS_RUST_LIB_DIR}. The builder stages the compiled "
                    "staticlib there before the plugin link; this usually means the "
                    "crate build or staging step did not run.")
            endif()
        endforeach()
    endif()

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

    # WHERE the LogosView*.in templates come from: logos-view-module's cmake/,
    # handed in as LOGOS_VIEW_TEMPLATE_DIR (a cmake flag and an env var, both
    # set by logos-module-builder — i.e. by THIS repo, the one shipping this
    # file: lib/mkLogosModule.nix and lib/buildCppPlugin.nix set them on every
    # plugin build and export the env var in every module dev shell).
    #
    # This used to be "sibling of this .cmake file", with a pathExists probe
    # falling through to CMAKE_CURRENT_LIST_DIR. The templates therefore lived
    # next to this file, in logos-module-builder — but a second consumer
    # instantiates them too (the rep-file-plugin fixture that proves a built
    # plugin still loads and casts), and it cannot depend on
    # logos-module-builder, so it kept its own byte-identical copy and nothing
    # compared the two. Ownership went first to logos-plugin-qt, and then on to
    # logos-view-module, which owns the whole ui_qml authoring flavour — the
    # fixture included — and is a LEAF, so every consumer can reach it. See
    # logos-view-module/cmake/README.md.
    #
    # There is no fallback. A sibling-directory fallback is what let a second
    # copy be picked silently, and the whole point of naming the directory is
    # that a wrong or absent answer is loud.
    if(NOT LOGOS_VIEW_TEMPLATE_DIR AND DEFINED ENV{LOGOS_VIEW_TEMPLATE_DIR})
        set(LOGOS_VIEW_TEMPLATE_DIR "$ENV{LOGOS_VIEW_TEMPLATE_DIR}")
    endif()
    if(NOT LOGOS_VIEW_TEMPLATE_DIR)
        message(FATAL_ERROR
            "logos_module(REP_FILE ...): LOGOS_VIEW_TEMPLATE_DIR is not set. "
            "The LogosView*.in templates are owned by logos-view-module "
            "(cmake/), and logos-module-builder — the repo shipping this "
            "LogosModule.cmake — passes this in for every plugin build and "
            "exports it in every module dev shell. Set it to that directory; "
            "there is no local copy to fall back to.")
    endif()
    set(_TEMPLATE_DIR "${LOGOS_VIEW_TEMPLATE_DIR}")
    foreach(_tpl LogosViewReplicaFactory.h.in LogosViewReplicaFactory.cpp.in
                 LogosViewPluginBase.h.in LogosViewPluginBase.cpp.in)
        if(NOT EXISTS "${_TEMPLATE_DIR}/${_tpl}")
            message(FATAL_ERROR
                "logos_module(REP_FILE ...): ${_tpl} is missing from "
                "LOGOS_VIEW_TEMPLATE_DIR (${_TEMPLATE_DIR}).")
        endif()
    endforeach()

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
