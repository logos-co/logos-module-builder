# Builds a universal module with an optional dependency. The universal glue writes
# its .lidl with one generator and reads it back with another, each on its own
# logos-lidl pin; when only the writer knew `optional_depends`, every such module
# failed to build and nothing here built one (logos-plugin-qt#37).
{ pkgs, mkLogosModule, fixturesRoot, templatesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;

  # The shipped template doubles as the dependency: it publishes packages.<sys>.lidl.
  minimal = mkLogosModule {
    src = templatesRoot + "/minimal-module";
    configFile = templatesRoot + "/minimal-module/metadata.json";
  };

  fixture = fixturesRoot + "/universal-optional-deps";
  consumer = mkLogosModule {
    src = fixture;
    configFile = fixture + "/metadata.json";
    flakeInputs = { inherit minimal; };
  };

  moduleLib = consumer.packages.${system}.lib;

in pkgs.runCommand "universal-optional-deps-tests" {} ''
  set -euo pipefail
  # share/logos/<name>.lidl is the file the build's generators read back, so a
  # built module plus the clause in that file proves the reader parsed it.
  sidecar=${moduleLib}/share/logos/optional_consumer.lidl
  test -f "$sidecar" || { echo "FAIL: no LIDL sidecar at $sidecar"; exit 1; }
  grep -q 'optional_depends' "$sidecar" \
    || { echo "FAIL: sidecar has no optional_depends clause:"; cat "$sidecar"; exit 1; }
  echo "PASS: optional_consumer built from a .lidl carrying optional_depends"
  mkdir -p $out && echo passed > $out/results.txt
''
