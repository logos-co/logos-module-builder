# Unit tests linking two shared external libraries: each lib dir must be its own
# rpath entry. dyld reads a ':'-joined entry as one path that does not exist.
{ pkgs, mkLogosModuleTests, fixturesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  moduleSrc = fixturesRoot + "/extlib-rpath-module";

  # Installed under an @rpath name / bare soname, so only the rpath finds it.
  mkSharedLib = name: value: pkgs.stdenv.mkDerivation {
    pname = "lib${name}";
    version = "1.0.0";
    dontUnpack = true;
    buildPhase = ''
      cat > ${name}.h <<EOF
      #ifdef __cplusplus
      extern "C"
      #endif
      int ${name}_value(void);
      EOF
      echo 'int ${name}_value(void) { return ${toString value}; }' > ${name}.c
      ${if isDarwin
        then "$CC -dynamiclib -install_name @rpath/lib${name}.dylib -o lib${name}.dylib ${name}.c"
        else "$CC -shared -fPIC -Wl,-soname,lib${name}.so -o lib${name}.so ${name}.c"}
    '';
    installPhase = ''
      mkdir -p $out/lib $out/include
      cp lib${name}.* $out/lib/
      cp ${name}.h $out/include/
    '';
  };

  rpatha = mkSharedLib "rpatha" 1;
  rpathb = mkSharedLib "rpathb" 2;

  tests = (mkLogosModuleTests {
    src = moduleSrc;
    testDir = moduleSrc + "/tests";
    configFile = moduleSrc + "/metadata.json";
    externalLibInputs = { inherit rpatha rpathb; };
  }).${system}.unit-tests;

in pkgs.runCommand "external-lib-rpath-tests" {
  nativeBuildInputs = [ pkgs.stdenv.cc.bintools.bintools ];
  passthru = { inherit rpatha rpathb tests; };
} ''
  set -euo pipefail
  # wrapQtAppsHook moves the real binary aside.
  bin=${tests}/bin/.extlib_rpath_module_tests-wrapped
  [ -f "$bin" ] || bin=${tests}/bin/extlib_rpath_module_tests

  ${if isDarwin then ''
    needed=$(otool -L "$bin")
    entries=$(otool -l "$bin" | awk '$1 == "cmd" { rp = ($2 == "LC_RPATH") } rp && $1 == "path" { print $2 }')
    for lib in librpatha librpathb; do
      grep -Fq "@rpath/$lib.dylib" <<<"$needed" \
        || { echo "FAIL: $lib is not loaded through @rpath:"; echo "$needed"; exit 1; }
    done
  '' else ''
    needed=$(readelf -d "$bin")
    entries=$(sed -n 's/.*(RUNPATH).*\[\(.*\)\]$/\1/p' <<<"$needed" | tr ':' '\n')
    for lib in librpatha librpathb; do
      grep -Fq "[$lib.so]" <<<"$needed" \
        || { echo "FAIL: $lib is not a bare-soname dependency:"; echo "$needed"; exit 1; }
    done
  ''}
  echo "rpath entries:"; echo "$entries"
  for dir in ${rpatha}/lib ${rpathb}/lib; do
    grep -Fxq "$dir" <<<"$entries" \
      || { echo "FAIL: $dir is not its own rpath entry"; exit 1; }
  done
  echo "PASS: each external lib dir is its own rpath entry"

  # No loader env vars here, unlike the build's own test run.
  ${tests}/bin/extlib_rpath_module_tests
  echo "PASS: the installed test binary loads both libraries"

  mkdir -p $out
  echo passed > $out/results.txt
''
