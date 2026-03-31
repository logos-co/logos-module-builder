# Integration tests for mkLogosQmlModule
# These tests actually BUILD a QML module from a fixture directory
# and verify the output derivation contents.
{ pkgs, mkLogosQmlModule, fixturesRoot }:

let
  # Build the fixture QML module
  qmlResult = mkLogosQmlModule {
    src = fixturesRoot + "/qml-module";
    configFile = fixturesRoot + "/qml-module/metadata.json";
  };

  system = pkgs.stdenv.hostPlatform.system;

  # The actual package derivations for this system
  defaultPkg = qmlResult.packages.${system}.default;
  libPkg = qmlResult.packages.${system}.lib;

in pkgs.runCommand "qml-integration-tests" {
  nativeBuildInputs = [ pkgs.jq ];
} ''
  set -euo pipefail
  echo "=== QML Integration Tests ==="

  # Test 1: default package exists and is a directory
  test -d ${defaultPkg}
  echo "PASS: default package is a directory"

  # Test 2: Main.qml is present in default output
  test -f ${defaultPkg}/Main.qml
  echo "PASS: Main.qml present in default output"

  # Test 3: metadata.json is present in default output
  test -f ${defaultPkg}/metadata.json
  echo "PASS: metadata.json present in default output"

  # Test 4: metadata.json name is correct
  name=$(jq -r '.name' ${defaultPkg}/metadata.json)
  test "$name" = "test_qml_module"
  echo "PASS: metadata.json name is 'test_qml_module'"

  # Test 5: metadata.json type is correct
  type=$(jq -r '.type' ${defaultPkg}/metadata.json)
  test "$type" = "ui_qml"
  echo "PASS: metadata.json type is 'ui_qml'"

  # Test 6: metadata.json main is correct
  main=$(jq -r '.main' ${defaultPkg}/metadata.json)
  test "$main" = "Main.qml"
  echo "PASS: metadata.json main is 'Main.qml'"

  # Test 7: lib package has lib/ subdirectory
  test -d ${libPkg}/lib
  echo "PASS: lib package has lib/ directory"

  # Test 8: lib package has Main.qml inside lib/
  test -f ${libPkg}/lib/Main.qml
  echo "PASS: lib package has Main.qml in lib/"

  # Test 9: lib package has metadata.json inside lib/
  test -f ${libPkg}/lib/metadata.json
  echo "PASS: lib package has metadata.json in lib/"

  # Test 10: config values are accessible (Nix-level via string interpolation)
  test "${qmlResult.config.name}" = "test_qml_module"
  echo "PASS: config.name is correct"

  test "${qmlResult.config.type}" = "ui_qml"
  echo "PASS: config.type is correct"

  test "${qmlResult.config.main}" = "Main.qml"
  echo "PASS: config.main is correct"

  # Test 11: metadataJson is accessible and contains expected content
  echo '${qmlResult.metadataJson}' | jq -e '.name == "test_qml_module"' > /dev/null
  echo "PASS: metadataJson round-trips correctly"

  echo ""
  echo "All QML integration tests passed."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
