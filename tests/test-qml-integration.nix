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

  # QML-only default uses lib/ layout (Main.qml + metadata.json under lib/).
  defaultPkg = qmlResult.packages.${system}.default;

in pkgs.runCommand "qml-integration-tests" {
  nativeBuildInputs = [ pkgs.jq ];
} ''
  set -euo pipefail
  echo "=== QML Integration Tests ==="

  # Test 1: default package exists and is a directory
  test -d ${defaultPkg}
  echo "PASS: default package is a directory"

  # Test 2: QML-only default uses lib/ layout (for LGX/installDev compatibility)
  test -f ${defaultPkg}/lib/Main.qml
  echo "PASS: Main.qml in lib/ of default output"

  # Test 3: metadata.json in lib/
  test -f ${defaultPkg}/lib/metadata.json
  echo "PASS: metadata.json in lib/ of default output"

  # Test 4: metadata.json name is correct
  name=$(jq -r '.name' ${defaultPkg}/lib/metadata.json)
  test "$name" = "test_qml_module"
  echo "PASS: metadata.json name is 'test_qml_module'"

  # Test 5: metadata.json type is correct
  type=$(jq -r '.type' ${defaultPkg}/lib/metadata.json)
  test "$type" = "ui_qml"
  echo "PASS: metadata.json type is 'ui_qml'"

  # Test 6: metadata.json view is correct
  view=$(jq -r '.view' ${defaultPkg}/lib/metadata.json)
  test "$view" = "Main.qml"
  echo "PASS: metadata.json view is 'Main.qml'"

  # Test 8: config values are accessible
  test "${qmlResult.config.name}" = "test_qml_module"
  echo "PASS: config.name is correct"

  test "${qmlResult.config.type}" = "ui_qml"
  echo "PASS: config.type is correct"

  test "${qmlResult.config.view}" = "Main.qml"
  echo "PASS: config.view is correct"

  # Test 9: metadataJson round-trips correctly
  echo '${qmlResult.metadataJson}' | jq -e '.name == "test_qml_module"' > /dev/null
  echo "PASS: metadataJson round-trips correctly"

  # Test 10: no C++ lib output for QML-only module
  ${if qmlResult.packages.${system} ? lib then
    ''echo "FAIL: QML-only module should not have 'lib' output"; exit 1''
  else
    ''echo "PASS: no 'lib' output for QML-only module"''
  }

  echo ""
  echo "All QML integration tests passed."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
