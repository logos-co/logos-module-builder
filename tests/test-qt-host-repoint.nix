# Which Qt HOST RUNTIME logos_module() links, and how loudly it refuses when it
# cannot name one.
#
# The host runtime (LogosAPI, LogosAPIProvider, LogosProviderBase, the legacy
# PluginInterface) moved out of logos-qt-sdk into logos-plugin-qt, where it ships
# as the `logos-qt-host` CMake package. LogosModule.cmake now selects it via
# LOGOS_QT_HOST_ROOT and links logos-qt-host::logos_qt_host.
#
# The failure this test exists for is the one that costs days: when a target name
# stops resolving, CMake's natural idioms fail OPEN. An `if(TARGET ...)` guard
# just evaluates false and the build carries on producing an artifact with the
# runtime silently missing. So the selection is asserted on all four inputs —
# installed prefix, source checkout, NO host root at all, and a root with no
# runtime in it — and the last two must be hard errors, never a skip.
#
# There is no logos-qt-sdk fallback any more. logos-qt-sdk forwarded the host
# runtime's headers during the migration and stopped once every consumer named
# logos-qt-host directly, so a fallback onto it would configure and then fail in
# the compile. Test 3 pins its absence.
#
# Hermetic: the roots are empty scaffolds, so this needs no Qt and no store deps.
{ pkgs }:

let
  logosModuleCmake = ../cmake/LogosModule.cmake;

  # Drives logos_find_dependencies() and prints its verdict in one grep-able
  # line. Every root arrives via -D on the command line.
  probeScript = pkgs.writeText "qt_host_probe.cmake" ''
    include(${logosModuleCmake})
    logos_find_dependencies()
    message(STATUS "VERDICT pkg=''${LOGOS_QT_HOST_PACKAGE} target=''${LOGOS_QT_HOST_TARGET} "
                   "is_source=''${LOGOS_QT_HOST_IS_SOURCE} root=''${LOGOS_QT_HOST_ROOT}")
  '';

in pkgs.runCommand "qt-host-repoint-tests" {
  nativeBuildInputs = [ pkgs.cmake ];
} ''
  set -euo pipefail
  echo "=== Qt host runtime repoint tests ==="

  # Scaffold the roots logos_find_dependencies() probes for. Contents are never
  # read — only the presence of these files decides source vs installed layout.
  mkdir -p roots/module/src roots/cpp-sdk/cpp roots/protocol/cpp
  touch roots/module/src/interface.h
  touch roots/cpp-sdk/cpp/logos_module_context.h
  touch roots/protocol/cpp/logos_protocol.h

  # logos-qt-sdk, installed layout — still required for the Qt-typed headers it
  # alone ships (logos_qt_lp_bridge.h, logos_qt_wire.h, logos_ui_plugin_context.h).
  # Scaffolded with logos_qt_wire.h and NOT logos_api.h, matching the real
  # prefix: probing this root for logos_api.h would report a good root as
  # missing.
  mkdir -p roots/qt-sdk/include/cpp
  touch roots/qt-sdk/include/cpp/logos_qt_wire.h

  # logos-qt-host in both of its shapes.
  mkdir -p roots/qt-host-installed/include/cpp
  touch roots/qt-host-installed/include/cpp/logos_api.h
  mkdir -p roots/qt-host-source/cpp
  touch roots/qt-host-source/cpp/logos_api.h

  # A root that exists but holds no host runtime — the trap case.
  mkdir -p roots/empty

  # CMake REFLOWS message() text to its own width, so a phrase that reads as one
  # line in the source can arrive split across two. Every assertion below runs
  # against a newline-flattened, whitespace-squeezed copy of the log; grepping
  # the raw log is how these tests rot into false failures.
  flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

  common="-DLOGOS_MODULE_ROOT=$PWD/roots/module"
  common="$common -DLOGOS_CPP_SDK_ROOT=$PWD/roots/cpp-sdk"
  common="$common -DLOGOS_PROTOCOL_ROOT=$PWD/roots/protocol"
  common="$common -DLOGOS_QT_SDK_ROOT=$PWD/roots/qt-sdk"

  # -------------------------------------------------------------------
  # Test 1: an installed logos-qt-host prefix wins, as a linkable package.
  # -------------------------------------------------------------------
  cmake $common -DLOGOS_QT_HOST_ROOT="$PWD/roots/qt-host-installed" \
    -P ${probeScript} > t1.log 2>&1
  flatten t1.log | grep -q 'VERDICT pkg=logos-qt-host target=logos-qt-host::logos_qt_host is_source=FALSE'
  echo "PASS: installed logos-qt-host prefix -> logos-qt-host::logos_qt_host"

  # -------------------------------------------------------------------
  # Test 2: a logos-plugin-qt CHECKOUT is recognised as the source layout, so
  # the host runtime's .cpp files are compiled in rather than linked.
  # -------------------------------------------------------------------
  cmake $common -DLOGOS_QT_HOST_ROOT="$PWD/roots/qt-host-source" \
    -P ${probeScript} > t2.log 2>&1
  flatten t2.log | grep -q 'VERDICT pkg=logos-qt-host target=logos-qt-host::logos_qt_host is_source=TRUE'
  echo "PASS: logos-plugin-qt checkout -> source layout"

  # -------------------------------------------------------------------
  # Test 3: with no LOGOS_QT_HOST_ROOT there is nothing to fall back to. A
  # perfectly good logos-qt-sdk root is present and must NOT be accepted as the
  # host runtime — it has not carried those headers since the repoint, so
  # accepting it would turn a clear configure error into a compile error deep in
  # a consumer's build.
  # -------------------------------------------------------------------
  if cmake $common -P ${probeScript} > t3.log 2>&1; then
    echo "FAIL: a build with no LOGOS_QT_HOST_ROOT was accepted"
    cat t3.log
    exit 1
  fi
  flatten t3.log | grep -q 'CMake Error'
  flatten t3.log | grep -q 'No Qt host runtime found'
  flatten t3.log | grep -q 'LOGOS_QT_SDK_ROOT is not a substitute'
  if flatten t3.log | grep -q 'VERDICT'; then
    echo "FAIL: a missing host root silently fell through to a verdict"
    exit 1
  fi
  echo "PASS: no LOGOS_QT_HOST_ROOT aborts; logos-qt-sdk is not a fallback"

  # -------------------------------------------------------------------
  # Test 3b: and the logos-qt-sdk root itself is still FOUND — the probe was
  # moved off logos_api.h (which that prefix stopped shipping) onto
  # logos_qt_wire.h (which it owns). Test 3's error must be about the HOST
  # runtime, never "logos-qt-sdk not found".
  # -------------------------------------------------------------------
  if flatten t3.log | grep -q 'logos-qt-sdk not found'; then
    echo "FAIL: the logos-qt-sdk root was reported missing while looking straight at it"
    cat t3.log
    exit 1
  fi
  cmake $common -DLOGOS_QT_HOST_ROOT="$PWD/roots/qt-host-installed" \
    -P ${probeScript} > t3b.log 2>&1
  flatten t3b.log | grep -q "Found logos-qt-sdk at: $PWD/roots/qt-sdk"
  echo "PASS: a logos-qt-sdk prefix with no logos_api.h is still found"

  # -------------------------------------------------------------------
  # Test 4: a LOGOS_QT_HOST_ROOT with no host runtime under it is FATAL.
  # This is the whole point of the file: it must not fall through to the
  # logos-qt-sdk branch, and it must not succeed.
  # -------------------------------------------------------------------
  if cmake $common -DLOGOS_QT_HOST_ROOT="$PWD/roots/empty" \
       -P ${probeScript} > t4.log 2>&1; then
    echo "FAIL: a LOGOS_QT_HOST_ROOT with no host runtime was accepted"
    cat t4.log
    exit 1
  fi
  flatten t4.log | grep -q 'CMake Error'
  flatten t4.log | grep -q 'no Qt host runtime is there'
  if flatten t4.log | grep -q 'VERDICT'; then
    echo "FAIL: the bad root silently fell through to a verdict"
    exit 1
  fi
  echo "PASS: a host root with no runtime aborts, rather than skipping"

  # -------------------------------------------------------------------
  # Test 5: the link site names the selected target, and no plugin is linked
  # against logos-qt-sdk::logos_qt_sdk by hard-coded name any more.
  # -------------------------------------------------------------------
  grep -q 'target_link_libraries(''${MODULE_NAME}_module_plugin PRIVATE ''${LOGOS_QT_HOST_TARGET})' ${logosModuleCmake}
  if grep -q 'target_link_libraries(.*logos-qt-sdk::logos_qt_sdk' ${logosModuleCmake}; then
    echo "FAIL: a plugin is still linked against logos-qt-sdk::logos_qt_sdk by name"
    exit 1
  fi
  echo "PASS: the plugin links \''${LOGOS_QT_HOST_TARGET}, not a hard-coded qt-sdk target"

  # -------------------------------------------------------------------
  # Test 6: find_package(REQUIRED) is not trusted on its own — a package that
  # resolves without defining its target is refused too.
  # -------------------------------------------------------------------
  grep -q 'if(NOT TARGET ''${LOGOS_QT_HOST_TARGET})' ${logosModuleCmake}
  grep -q 'The Qt host runtime is not optional' ${logosModuleCmake}
  echo "PASS: a package that defines no target is a FATAL_ERROR"

  echo ""
  echo "All Qt host runtime repoint tests passed."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
