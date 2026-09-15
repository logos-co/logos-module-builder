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

  requiredLidl = pkgs.writeTextDir "required_dep.lidl" ''
    ; This comment and compact layout must disappear after normalization.
    module required_dep{depends[] method ping()->tstr}
  '';
  optionalLidl = pkgs.writeTextDir "optional_dep.lidl" ''
    module optional_dep { depends [ ] method available( ) -> bool }
  '';
  dependencyInput = lidl: { packages.${system}.lidl = lidl; };

  # QML plugins expose no callable interface of their own. They do, however,
  # carry the canonical contracts for all three dependency classes.
  qmlContractsResult = mkLogosQmlModule {
    src = fixturesRoot + "/qml-module-with-contracts";
    configFile = fixturesRoot + "/qml-module-with-contracts/metadata.json";
    flakeInputs = {
      required_dep = dependencyInput requiredLidl;
      optional_dep = dependencyInput optionalLidl;
    };
  };
  contractsPkg = qmlContractsResult.packages.${system}.default;

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

  # Test 11: the package advertises the source directory that nix-bundle-lgx
  # maps to root-level assets/lidl.
  test "${contractsPkg.lgxAssets.lidl}" = "share/logos"
  echo "PASS: QML package declares its platform-independent LIDL assets"

  # Test 12: every dependency class is present and canonicalized, while the UI
  # plugin itself publishes no callable module contract.
  for dep in required_dep optional_dep iface_dep; do
    test -f "${contractsPkg}/share/logos/$dep.lidl"
    grep -q "^module $dep {" "${contractsPkg}/share/logos/$dep.lidl"
    ! grep -q 'Authored formatting\|compact layout' "${contractsPkg}/share/logos/$dep.lidl"
  done
  test ! -e "${contractsPkg}/share/logos/qml_contract_consumer.lidl"
  echo "PASS: QML package contains only canonical dependency contracts"

  echo ""
  echo "All QML integration tests passed."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
