# Installs the shape of logos-lidl: two static archives, headers under
# include/<pkg>/, and a CMake package under lib/cmake/<pkg>/.
cmake_minimum_required(VERSION 3.14)
project(extfixture VERSION 1.0.0 LANGUAGES CXX)

add_library(extfixture STATIC src/extfixture.cpp)
add_library(extfixture_c STATIC src/extfixture_c.cpp)
foreach(target extfixture extfixture_c)
    set_target_properties(${target} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_include_directories(${target} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>)
endforeach()

install(TARGETS extfixture extfixture_c EXPORT extfixtureTargets ARCHIVE DESTINATION lib)
install(DIRECTORY include/ DESTINATION include)
install(EXPORT extfixtureTargets NAMESPACE extfixture::
        DESTINATION lib/cmake/extfixture FILE extfixtureConfig.cmake)
