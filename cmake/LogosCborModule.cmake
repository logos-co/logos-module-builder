# LogosCborModule.cmake — CMake macro for building Qt-free CBOR modules
#
# Usage:
#   logos_cbor_module(
#     NAME <module_name>
#     MODE exe|plugin
#     SOURCES <source_files...>
#     [LINK_LIBRARIES <libs...>]
#     [INCLUDE_DIRS <dirs...>]
#   )
#
# This builds modules without any Qt dependency, linking only against
# logos_value and logos_cbor_server from the Qt-free SDK subset.

function(logos_cbor_module)
    cmake_parse_arguments(MOD
        ""
        "NAME;MODE"
        "SOURCES;LINK_LIBRARIES;INCLUDE_DIRS"
        ${ARGN}
    )

    if(NOT MOD_NAME)
        message(FATAL_ERROR "logos_cbor_module: NAME is required")
    endif()
    if(NOT MOD_MODE)
        message(FATAL_ERROR "logos_cbor_module: MODE is required (exe or plugin)")
    endif()
    if(NOT MOD_SOURCES)
        message(FATAL_ERROR "logos_cbor_module: SOURCES is required")
    endif()

    # Find logos-cpp-sdk-cbor (Qt-free subset)
    if(DEFINED ENV{LOGOS_CPP_SDK_CBOR_ROOT})
        set(_sdk_root "$ENV{LOGOS_CPP_SDK_CBOR_ROOT}")
    elseif(DEFINED LOGOS_CPP_SDK_CBOR_ROOT)
        set(_sdk_root "${LOGOS_CPP_SDK_CBOR_ROOT}")
    elseif(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
        set(_sdk_root "$ENV{LOGOS_CPP_SDK_ROOT}")
    elseif(DEFINED LOGOS_CPP_SDK_ROOT)
        set(_sdk_root "${LOGOS_CPP_SDK_ROOT}")
    else()
        message(FATAL_ERROR "logos_cbor_module: cannot find logos-cpp-sdk. Set LOGOS_CPP_SDK_ROOT or LOGOS_CPP_SDK_CBOR_ROOT")
    endif()

    # Find libraries
    find_library(LOGOS_VALUE_LIB NAMES logos_value PATHS "${_sdk_root}/lib" NO_DEFAULT_PATH)
    find_library(LOGOS_CBOR_SERVER_LIB NAMES logos_cbor_server PATHS "${_sdk_root}/lib" NO_DEFAULT_PATH)

    if(NOT LOGOS_VALUE_LIB)
        message(FATAL_ERROR "logos_cbor_module: logos_value library not found in ${_sdk_root}/lib")
    endif()
    if(NOT LOGOS_CBOR_SERVER_LIB)
        message(FATAL_ERROR "logos_cbor_module: logos_cbor_server library not found in ${_sdk_root}/lib")
    endif()

    set(_sdk_include "${_sdk_root}/include")

    if(MOD_MODE STREQUAL "exe")
        # Build as standalone executable
        add_executable(${MOD_NAME} ${MOD_SOURCES})

        set_target_properties(${MOD_NAME} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
        )

        install(TARGETS ${MOD_NAME} RUNTIME DESTINATION bin)

    elseif(MOD_MODE STREQUAL "plugin")
        # Build as shared library (cbor-plugin)
        add_library(${MOD_NAME}_plugin SHARED ${MOD_SOURCES})

        set_target_properties(${MOD_NAME}_plugin PROPERTIES
            PREFIX ""
            LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
        )

        # Platform-specific RPATH
        if(APPLE)
            set_target_properties(${MOD_NAME}_plugin PROPERTIES
                INSTALL_RPATH "@loader_path"
                BUILD_WITH_INSTALL_RPATH TRUE)
        else()
            set_target_properties(${MOD_NAME}_plugin PROPERTIES
                INSTALL_RPATH "$ORIGIN"
                BUILD_WITH_INSTALL_RPATH TRUE)
        endif()

        install(TARGETS ${MOD_NAME}_plugin
            LIBRARY DESTINATION lib/logos/modules)

    else()
        message(FATAL_ERROR "logos_cbor_module: MODE must be 'exe' or 'plugin', got '${MOD_MODE}'")
    endif()

    # Common configuration for both modes
    set(_target ${MOD_NAME})
    if(MOD_MODE STREQUAL "plugin")
        set(_target ${MOD_NAME}_plugin)
    endif()

    target_compile_features(${_target} PRIVATE cxx_std_17)

    target_include_directories(${_target} PRIVATE
        ${_sdk_include}
        ${_sdk_include}/implementations/cbor_socket
        ${MOD_INCLUDE_DIRS}
    )

    target_link_libraries(${_target} PRIVATE
        ${LOGOS_CBOR_SERVER_LIB}
        ${LOGOS_VALUE_LIB}
        pthread
        ${MOD_LINK_LIBRARIES}
    )

endfunction()
