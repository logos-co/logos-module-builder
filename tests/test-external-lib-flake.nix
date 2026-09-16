# A flake-input external library shaped like logos-lidl (two static archives,
# nested headers, a lib/cmake/ package), linked by a module and by its unit
# tests. Each build stages it into lib/ itself; both must stage the same tree.
{ pkgs, mkLogosModule, mkLogosModuleTests, fixturesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;
  libSrc = fixturesRoot + "/extlib-flake-lib";
  moduleSrc = fixturesRoot + "/extlib-flake-module";

  extfixture = pkgs.stdenv.mkDerivation {
    pname = "extfixture";
    version = "1.0.0";
    src = libSrc;
    nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
  };

  # A bare flake input as the builder receives it: outPath is the unbuilt source.
  extfixtureInput = {
    _type = "flake";
    outPath = libSrc;
    packages.${system}.default = extfixture;
  };

  args = {
    src = moduleSrc;
    configFile = moduleSrc + "/metadata.json";
    externalLibInputs = { extfixture = extfixtureInput; extfixture_c = extfixtureInput; };
    # Runs after each build has staged lib/ and before cmake reads it.
    preConfigure = { externalLibs }: ''
      test -f "${externalLibs.extfixture}/lib/libextfixture.a" \
        || { echo "FAIL: externalLibs.extfixture is not the built package: ${externalLibs.extfixture}"; exit 1; }
      for f in libextfixture.a libextfixture_c.a extfixture/extfixture.hpp \
               extfixture/extfixture_c.h cmake/extfixture/extfixtureConfig.cmake; do
        test -f "lib/$f" || { echo "FAIL: lib/$f was not staged"; exit 1; }
      done
      if [ -n "$(find lib ! -perm -u+w -print -quit)" ]; then
        echo "FAIL: staged paths are read-only:"; find lib ! -perm -u+w; exit 1
      fi
    '';
  };

  moduleLib = (mkLogosModule args).packages.${system}.lib;
  tests = (mkLogosModuleTests (args // { testDir = moduleSrc + "/tests"; })).${system}.unit-tests;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

in pkgs.runCommand "external-lib-flake-tests" {
  nativeBuildInputs = [ pkgs.stdenv.cc.bintools.bintools ];
  passthru = { inherit extfixture moduleLib tests; };
} ''
  set -euo pipefail
  plugin=${moduleLib}/lib/extlib_flake_plugin.${if isDarwin then "dylib" else "so"}
  test -f "$plugin" || { echo "FAIL: no plugin at $plugin"; exit 1; }
  # Linux links a shared object with undefined symbols, so check the archive went in.
  # Exports table: -D on ELF, -g on Mach-O (see test-module-impl-abi-nm.nix).
  syms=$(nm ${if isDarwin then "-g" else "-D"} --defined-only "$plugin")
  grep -Eq ' T _?extfixture_c_version$' <<<"$syms" \
    || { echo "FAIL: $plugin does not export extfixture_c_version"; exit 1; }
  echo "PASS: module linked both archives of a flake-input library"
  test -d ${tests}/bin || { echo "FAIL: unit tests installed nothing"; exit 1; }
  echo "PASS: unit tests built and ran against the same staged library"
  mkdir -p $out && echo passed > $out/results.txt
''
