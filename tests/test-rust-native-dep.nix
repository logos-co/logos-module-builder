# Integration test for the `nix.rust` block — external system build deps for a
# Rust cdylib module's crate compile (commit adding nix_rust to the builder).
#
# The fixture's build.rs probes zlib via pkg-config, which only resolves when the
# builder feeds metadata `nix.rust` packages into the `buildRustPackage` that
# compiles the crate (pkg-config -> nativeBuildInputs, zlib -> buildInputs).
# Without the wiring the build script panics and the module fails to build — so a
# successful build IS the regression test.
{ pkgs, mkLogosModule, fixturesRoot }:

let
  fixturePath = fixturesRoot + "/rust-native-dep";

  module = mkLogosModule {
    src = fixturePath;
    configFile = fixturePath + "/metadata.json";
  };

  system = pkgs.stdenv.hostPlatform.system;
  moduleDrv = module.packages.${system}.default;

in pkgs.runCommand "rust-native-dep-tests" {} ''
  set -euo pipefail
  echo "=== nix.rust (Rust external build deps) integration test ==="

  # Forcing moduleDrv realizes the full module build. Its crate compiled, which
  # means build.rs found zlib via pkg-config, which means nix.rust fed pkg-config
  # + zlib into the Rust crate compile.
  test -d ${moduleDrv}
  echo "PASS: rust_native_dep_module built — build.rs zlib pkg-config probe succeeded via nix.rust"

  mkdir -p $out
  echo "passed" > $out/results.txt
''
