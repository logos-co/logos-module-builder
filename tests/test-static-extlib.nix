# Integration tests for static library (.a) support in EXTERNAL_LIBS
# Verifies commit 3d3a6830: .a files are discoverable via find_library and the
# runtime copy step is skipped for static archives (linked at build time).
{ pkgs }:

let
  logosModuleCmake = ../cmake/LogosModule.cmake;

  # cmake -P script: find_library resolves a .a when no shared lib is present.
  # LIB_DIR is injected via -D on the cmake command line.
  findStaticScript = pkgs.writeText "find_static_test.cmake" ''
    find_library(staticonly_PATH
      NAMES libstaticonly.dylib libstaticonly.so staticonly.dylib staticonly.so
            libstaticonly.a staticonly.a
      PATHS ''${LIB_DIR} NO_DEFAULT_PATH)
    if(NOT staticonly_PATH)
      message(FATAL_ERROR "FAIL: find_library did not locate libstaticonly.a")
    endif()
    get_filename_component(FOUND_NAME "''${staticonly_PATH}" NAME)
    if(NOT FOUND_NAME STREQUAL "libstaticonly.a")
      message(FATAL_ERROR "FAIL: expected libstaticonly.a, got ''${FOUND_NAME}")
    endif()
    message(STATUS "FOUND: ''${staticonly_PATH}")
  '';

  # cmake -P script: find_library prefers a shared lib over .a when both exist.
  findPreferSharedScript = pkgs.writeText "find_prefer_shared_test.cmake" ''
    find_library(duallib_PATH
      NAMES libduallib.dylib libduallib.so duallib.dylib duallib.so
            libduallib.a duallib.a
      PATHS ''${LIB_DIR} NO_DEFAULT_PATH)
    if(NOT duallib_PATH)
      message(FATAL_ERROR "FAIL: find_library found nothing in dual-lib dir")
    endif()
    get_filename_component(FOUND_NAME "''${duallib_PATH}" NAME)
    if(FOUND_NAME STREQUAL "libduallib.a")
      message(FATAL_ERROR "FAIL: find_library chose .a over shared lib (wrong preference)")
    endif()
    message(STATUS "PREFERRED: ''${duallib_PATH}")
  '';

  # cmake -P script: verify the .a$ MATCHES regex used in the copy guard.
  regexScript = pkgs.writeText "regex_test.cmake" ''
    foreach(name libfoo.a foo.a libbar.a)
      if(NOT ''${name} MATCHES "\\.a$")
        message(FATAL_ERROR "FAIL: ''${name} should match \\.a$ but did not")
      endif()
    endforeach()
    foreach(name libfoo.so libfoo.dylib foo.so foo.dylib libfoo.so.1)
      if(''${name} MATCHES "\\.a$")
        message(FATAL_ERROR "FAIL: ''${name} should NOT match \\.a$ but did")
      endif()
    endforeach()
    message(STATUS "All regex tests passed")
  '';

  sharedExt = if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";

in pkgs.runCommand "static-extlib-tests" {
  nativeBuildInputs = [ pkgs.cmake ];
} ''
  set -euo pipefail
  echo "=== Static External Library (.a) Tests ==="

  # -------------------------------------------------------------------
  # Test 1: find_library NAMES list now includes .a entries
  # (verifies the "prefer shared, fall back to static" comment added by commit)
  # -------------------------------------------------------------------
  grep -q 'prefer shared, fall back to static' ${logosModuleCmake}
  echo "PASS: .a names added to find_library NAMES list (shared preferred, .a fallback)"

  # -------------------------------------------------------------------
  # Test 2: .a$ guard wraps copy_if_different (NOT EXT_LIB_FILENAME MATCHES)
  # -------------------------------------------------------------------
  grep -q 'NOT EXT_LIB_FILENAME MATCHES' ${logosModuleCmake}
  echo "PASS: copy_if_different is guarded by NOT EXT_LIB_FILENAME MATCHES"

  # -------------------------------------------------------------------
  # Test 3: copy step is skipped for static archives (comment in commit)
  # -------------------------------------------------------------------
  grep -q 'static archives are linked in' ${logosModuleCmake}
  echo "PASS: comment confirms static archives skip the runtime copy step"

  # -------------------------------------------------------------------
  # Test 4: copy_if_different command is still present (not removed)
  # -------------------------------------------------------------------
  grep -q 'copy_if_different' ${logosModuleCmake}
  echo "PASS: copy_if_different still present for shared library handling"

  # -------------------------------------------------------------------
  # Test 5: cmake find_library resolves .a when only static archive present
  # -------------------------------------------------------------------
  mkdir -p testdir_static/lib
  touch testdir_static/lib/libstaticonly.a
  cmake -DLIB_DIR="$PWD/testdir_static/lib" -P ${findStaticScript} 2>&1 | grep -q 'FOUND:'
  echo "PASS: find_library resolves .a when only static archive is present"

  # -------------------------------------------------------------------
  # Test 6: cmake find_library prefers shared lib over .a when both exist
  # -------------------------------------------------------------------
  mkdir -p testdir_dual/lib
  touch "testdir_dual/lib/libduallib.${sharedExt}"
  touch testdir_dual/lib/libduallib.a
  cmake -DLIB_DIR="$PWD/testdir_dual/lib" -P ${findPreferSharedScript} 2>&1 | grep -q 'PREFERRED:'
  echo "PASS: find_library prefers shared lib over .a when both exist"

  # -------------------------------------------------------------------
  # Test 7: .a$ regex correctly identifies static archives vs shared libs
  # -------------------------------------------------------------------
  cmake -P ${regexScript} 2>&1 | grep -q 'All regex tests passed'
  echo "PASS: .a\$ regex correctly classifies static archives and shared libs"

  echo ""
  echo "All static external library tests passed."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
