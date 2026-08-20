# Test runner for logos-module-builder
# All tests are pure Nix evaluation — no compilation needed.
# Usage: nix build .#checks.<system>.default
{ pkgs, lib, parseMetadata, common, mkExternalLib, fixturesRoot ? ./fixtures }:

let
  # Helper: assert with message. Throws on failure.
  assertEq = name: actual: expected:
    if actual == expected then true
    else builtins.throw "FAIL ${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";

  assertBool = name: actual: expected:
    if actual == expected then true
    else builtins.throw "FAIL ${name}: expected ${builtins.toString expected}, got ${builtins.toString actual}";

  assertHasAttr = name: attrset: key:
    if builtins.hasAttr key attrset then true
    else builtins.throw "FAIL ${name}: missing attribute '${key}' in ${builtins.toJSON (builtins.attrNames attrset)}";

  assertThrows = name: expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
      if !result.success then true
      else builtins.throw "FAIL ${name}: expected expression to throw, but it succeeded with ${builtins.toJSON result.value}";

  # Import test modules
  parseMetadataTests = import ./test-parse-metadata.nix { inherit assertEq assertBool assertHasAttr assertThrows parseMetadata; };
  commonTests = import ./test-common.nix { inherit pkgs lib assertEq assertBool assertHasAttr common; };
  externalLibTests = import ./test-external-lib.nix { inherit assertEq assertBool mkExternalLib; };
  templateTests = import ./test-templates.nix { inherit assertEq assertBool assertHasAttr parseMetadata; builderRoot = ./..; };
  collectDepsTests = import ./test-collectAllModuleDeps.nix { inherit assertEq assertBool assertHasAttr common; };
  fixtureTests = import ./test-fixtures.nix { inherit assertEq assertBool assertHasAttr parseMetadata fixturesRoot; };
  # The consumer axis (codegen.consumer_api_style) and the gate on it. Its own
  # file rather than more cases in test-parse-metadata.nix: what it pins is a
  # safety boundary (which images may hold a LogosAPI-free consumer wrapper),
  # not a parsing default, and the reasoning belongs next to the cases.
  consumerApiStyleTests = import ./test-consumer-api-style.nix { inherit assertEq assertBool assertThrows parseMetadata; };
  modulePreConfigureTests = import ./test-module-pre-configure.nix {
    inherit lib assertBool assertThrows;
    modulePreConfigure = import ../lib/modulePreConfigure.nix { inherit lib; };
  };

  # Collect all test results into a list of bools (all must be true)
  allTests = parseMetadataTests ++ commonTests ++ externalLibTests ++ templateTests ++ collectDepsTests ++ fixtureTests ++ modulePreConfigureTests ++ consumerApiStyleTests;

  # Force evaluation of all tests
  allPassed = builtins.deepSeq allTests (builtins.length allTests);

in pkgs.runCommand "logos-module-builder-tests" {} ''
  echo "Running logos-module-builder tests..."
  echo "All ${builtins.toString allPassed} tests passed."
  mkdir -p $out
  echo "${builtins.toString allPassed} tests passed" > $out/results.txt
''
