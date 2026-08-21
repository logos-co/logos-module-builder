# Test runner for logos-module-builder
#
# Nothing here COMPILES anything — the derivation below is an echo — but "pure
# Nix evaluation" is no longer the whole truth either: test-platform-triples.nix
# instantiates all five package sets in common.systems, the x86_64-windows mingw
# cross among them, because the platform table it checks is only worth having if
# something pins it to what a real package set reports. So this check evaluates
# nixpkgs five times and is correspondingly slower than the rest; the other test
# files are still pure evaluation over metadata.
#
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
  parseMetadataTests = import ./test-parse-metadata.nix { inherit lib assertEq assertBool assertHasAttr assertThrows parseMetadata; };
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
  # The hand-written system -> platform-triple table, asserted against the real
  # package sets. Its own file because it is the only eval test that
  # instantiates nixpkgs five times, and because what it pins is a fact about
  # the CROSS target rather than anything about parsing. See its header for the
  # elaborate()-says-msvc trap it exists to catch.
  platformTripleTests = import ./test-platform-triples.nix {
    inherit assertEq common parseMetadata;
  };
  modulePreConfigureTests = import ./test-module-pre-configure.nix {
    inherit lib assertBool assertThrows;
    modulePreConfigure = import ../lib/modulePreConfigure.nix { inherit lib; };
  };

  # Every suite, LABELLED. The label is not decoration: the elements of these
  # lists are bare bools, so a failure report that could only say "element 274"
  # would send the reader counting through nine files.
  suites = [
    { name = "test-parse-metadata";       tests = parseMetadataTests; }
    { name = "test-common";               tests = commonTests; }
    { name = "test-external-lib";         tests = externalLibTests; }
    { name = "test-templates";            tests = templateTests; }
    { name = "test-collectAllModuleDeps"; tests = collectDepsTests; }
    { name = "test-fixtures";             tests = fixtureTests; }
    { name = "test-module-pre-configure"; tests = modulePreConfigureTests; }
    { name = "test-consumer-api-style";   tests = consumerApiStyleTests; }
    { name = "test-platform-triples";     tests = platformTripleTests; }
  ];

  # ── Why every element is type-checked and not merely deepSeq'd ─────────────
  #
  # `builtins.deepSeq` does not force a LAMBDA — it forces to WHNF and a lambda
  # is already there — so a partially applied assertion is a perfectly good list
  # element that asserts nothing and still counts toward the total printed
  # below. That is not hypothetical: `assertBool "interface universal" (...)`
  # sat in test-parse-metadata.nix missing its third argument, evaluating to a
  # lambda, reported as a passing test, for as long as the file has existed. A
  # test suite whose failure mode is "silently shrinks" is worse than a smaller
  # suite, because the number at the end is what everyone reads.
  #
  # So each element must be a bool AND must be true. assertEq/assertBool/
  # assertThrows already throw on failure and return `true`, so a `false` here
  # means someone put a raw comparison in the list — also worth catching.
  checkSuite = suite: lib.imap0 (i: t:
    if !(builtins.isBool t) then
      throw ("FAIL ${suite.name}[${toString i}]: this list element is a "
             + "${builtins.typeOf t}, not a bool. A ${builtins.typeOf t} is most "
             + "likely an assertion missing an argument — assertEq and assertBool "
             + "take THREE (name, actual, expected), assertThrows takes two. "
             + "builtins.deepSeq does not force a lambda, so such an element would "
             + "otherwise be counted as a passing test forever.")
    else if !t then
      throw ("FAIL ${suite.name}[${toString i}]: assertion evaluated to false. The "
             + "assert* helpers throw on failure and return true, so a bare false "
             + "means a raw comparison was put in the list instead of an assertion.")
    else t
  ) suite.tests;

  allTests = lib.concatMap checkSuite suites;

  # Force evaluation of all tests
  allPassed = builtins.deepSeq allTests (builtins.length allTests);

in pkgs.runCommand "logos-module-builder-tests" {} ''
  echo "Running logos-module-builder tests..."
  echo "All ${builtins.toString allPassed} tests passed."
  mkdir -p $out
  echo "${builtins.toString allPassed} tests passed" > $out/results.txt
''
