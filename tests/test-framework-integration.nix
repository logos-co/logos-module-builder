# Integration test for logos-test-framework via mkLogosModuleTests.
# Builds and runs a fixture module's unit tests to verify the full pipeline:
#   CMake finds LogosTest.cmake → logos_test() configures the target →
#   test binary compiles against the framework → tests execute and pass.
{ pkgs, mkLogosModuleTests, parseMetadata, fixturesRoot }:

let
  fixturePath = fixturesRoot + "/test-framework-module";

  testResults = mkLogosModuleTests {
    src = fixturePath;
    testDir = fixturePath + "/tests";
    configFile = fixturePath + "/metadata.json";
  };

  system = pkgs.stdenv.hostPlatform.system;
  testDrv = testResults.${system}.unit-tests;

in pkgs.runCommand "test-framework-integration-tests" {} ''
  set -euo pipefail
  echo "=== Test Framework Integration Tests ==="

  # Test 1: derivation built successfully (it ran the tests during build)
  test -d ${testDrv}
  echo "PASS: test derivation built successfully"

  # Test 2: test binary was installed
  test -f ${testDrv}/bin/test_framework_module_tests || \
    test -f ${testDrv}/bin/.test_framework_module_tests-wrapped
  echo "PASS: test binary is present in output"

  echo ""
  echo "All test framework integration tests passed."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
