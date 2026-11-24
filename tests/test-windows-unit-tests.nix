# mkLogosModuleTests on x86_64-windows: the fixture's test executable, the DLLs
# it imports, and the manifest logos-windows-ci runs it from. Linux can only
# build it; windows.yml runs `fixture` on a Windows runner.
{ pkgs, mkLogosModuleTests, fixturesRoot }:

let
  fixturePath = fixturesRoot + "/test-framework-module";

  fixture = (mkLogosModuleTests {
    src = fixturePath;
    testDir = fixturePath + "/tests";
    configFile = fixturePath + "/metadata.json";
  }).x86_64-windows.unit-tests;

  expectedManifest = builtins.toFile "test_framework_module.json" (builtins.toJSON {
    suites = [{
      name = "test_framework_module_tests";
      exe = "bin/test_framework_module_tests.exe";
      kind = "exe";
    }];
  });

  check = pkgs.runCommand "windows-unit-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -euo pipefail
    exe=${fixture}/bin/test_framework_module_tests.exe

    test -f "$exe"
    [ "$(head -c 2 "$exe")" = MZ ]
    echo "PASS: the test executable is a PE"

    diff -u <(jq -S . ${expectedManifest}) <(jq -S . ${fixture}/share/logos-tests/test_framework_module.json)
    echo "PASS: the manifest names it as one exe suite"

    for dll in Qt6Core.dll Qt6RemoteObjects.dll; do
      test -e ${fixture}/bin/$dll || { echo "FAIL: $dll was not linked beside the executable" >&2; exit 1; }
    done
    echo "PASS: the Qt DLLs it imports are beside it"

    mkdir -p $out
    echo passed > $out/results.txt
  '';

in { inherit check fixture; }
