# Build a real universal module through the qt_remote_plain branch. Parser and
# pre-configure tests prove selection; this check proves the selected artifact
# carries the module-impl ABI and has no Qt dependency.
{ pkgs, mkLogosModule, fixturesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  fixture = fixturesRoot + "/plain-universal-module";
  rustFixture = fixturesRoot + "/rust-native-dep";
  # Exercise mkLogosModule's supported alternate-configFile path. Before the
  # staging fix the parser selected this document while the backend embedded
  # the fixture source's original metadata.json, so the build and runtime could
  # silently disagree about fields such as `transport`.
  alternateDescription = "Alternate metadata selected by configFile";
  alternateConfig = pkgs.writeText "plain-fixture-alternate-metadata.json"
    (builtins.toJSON ((builtins.fromJSON (builtins.readFile (fixture + "/metadata.json"))) // {
      description = alternateDescription;
    }));
  moduleLib = (mkLogosModule {
    src = fixture;
    configFile = alternateConfig;
  }).packages.${system}.lib;
  rustPlainConfig = pkgs.writeText "plain-rust-fixture-metadata.json"
    (builtins.toJSON ((builtins.fromJSON (builtins.readFile (rustFixture + "/metadata.json"))) // {
      transport = "qt_remote_plain";
    }));
  rustModuleLib = (mkLogosModule {
    src = rustFixture;
    configFile = rustPlainConfig;
  }).packages.${system}.lib;
  dependencyCommand = if isDarwin then "otool -L" else "readelf -d";
  nmFlags = if isDarwin then "-gU" else "-D --defined-only";
in
pkgs.runCommand "plain-transport-integration-tests" {
  nativeBuildInputs = [ pkgs.stdenv.cc.bintools.bintools pkgs.jq ]
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

  # A Rust provider contributes logos_module_dispatch from a static archive.
  # With no Qt glue referencing that archive, a normal lazy link drops it in
  # full. This assertion covers the force-load path used by plain cdylib modules.
  rust_plugins=$PWD/rust-plugins.txt
  find ${rustModuleLib}/lib ${rustModuleLib}/bin -type f \
    \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) \
    2>/dev/null | sort > "$rust_plugins" || true
  rust_count=$(wc -l < "$rust_plugins" | tr -d ' ')
  if [ "$rust_count" -ne 1 ]; then
    echo "FAIL: expected one plain Rust module library, found $rust_count" >&2
    cat "$rust_plugins" >&2
    exit 1
  fi
  rust_plugin=$(cat "$rust_plugins")
  ${dependencyCommand} "$rust_plugin" > $PWD/rust-dependencies.txt
  if grep -Eiq '(^|[/\\])Qt[0-9]|Qt[0-9](Core|RemoteObjects)' $PWD/rust-dependencies.txt; then
    echo "FAIL: qt_remote_plain Rust module links Qt:" >&2
    cat $PWD/rust-dependencies.txt >&2
    exit 1
  fi
  nm ${nmFlags} "$rust_plugin" > $PWD/rust-symbols.txt
  if ! grep -q 'logos_module_dispatch' $PWD/rust-symbols.txt; then
    echo "FAIL: plain Rust module does not export logos_module_dispatch" >&2
    cat $PWD/rust-symbols.txt >&2
    exit 1
  fi

  test -f ${moduleLib}/share/logos/plain_fixture.lidl
  metadata=${moduleLib}/lib/plain_fixture_plugin.metadata.json
  test "$(jq -r .transport "$metadata")" = qt_remote_plain
  test "$(jq -r .description "$metadata")" = ${pkgs.lib.escapeShellArg alternateDescription}
  mkdir -p $out
  cp $PWD/dependencies.txt $PWD/symbols.txt \
    $PWD/rust-dependencies.txt $PWD/rust-symbols.txt $out/
''
