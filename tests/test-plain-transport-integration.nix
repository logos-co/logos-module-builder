# Build a real universal module through the qt_remote_plain branch. Parser and
# pre-configure tests prove selection; this check proves the selected artifact
# carries the module-impl ABI and has no Qt dependency.
{ pkgs, mkLogosModule, fixturesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  fixture = fixturesRoot + "/plain-universal-module";
  moduleLib = (mkLogosModule {
    src = fixture;
    configFile = fixture + "/metadata.json";
  }).packages.${system}.lib;
  dependencyCommand = if isDarwin then "otool -L" else "readelf -d";
  nmFlags = if isDarwin then "-gU" else "-D --defined-only";
in
pkgs.runCommand "plain-transport-integration-tests" {
  nativeBuildInputs = [ pkgs.stdenv.cc.bintools.bintools ]
    ++ pkgs.lib.optionals isDarwin [ pkgs.darwin.cctools ];
} ''
  set -euo pipefail

  plugins=$PWD/plugins.txt
  find ${moduleLib}/lib ${moduleLib}/bin -type f \
    \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) \
    2>/dev/null | sort > "$plugins" || true
  count=$(wc -l < "$plugins" | tr -d ' ')
  if [ "$count" -ne 1 ]; then
    echo "FAIL: expected one plain module library, found $count" >&2
    cat "$plugins" >&2
    exit 1
  fi
  plugin=$(cat "$plugins")

  ${dependencyCommand} "$plugin" > $PWD/dependencies.txt
  if grep -Eiq '(^|[/\\])Qt[0-9]|Qt[0-9](Core|RemoteObjects)' $PWD/dependencies.txt; then
    echo "FAIL: qt_remote_plain module links Qt:" >&2
    cat $PWD/dependencies.txt >&2
    exit 1
  fi

  nm ${nmFlags} "$plugin" > $PWD/symbols.txt
  if ! grep -q 'logos_module_dispatch' $PWD/symbols.txt; then
    echo "FAIL: plain module does not export logos_module_dispatch" >&2
    cat $PWD/symbols.txt >&2
    exit 1
  fi

  test -f ${moduleLib}/share/logos/plain_fixture.lidl
  mkdir -p $out
  cp $PWD/dependencies.txt $PWD/symbols.txt $out/
''
