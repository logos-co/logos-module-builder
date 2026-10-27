# Integration test for `"backend": "module"`: BUILDS a copy of the
# ui-qml-backend template that opts in, and checks the one .lgx it produces
# holds both halves — the QML view and the backend core module
# `ui_example_backend` — with the shipped metadata.json naming the backend,
# which is how a shell finds it, and that the backend's callable surface is
# view_endpoint() alone.
{ pkgs, mkLogosQmlModule, fixturesRoot, logosModule }:

let
  system = pkgs.stdenv.hostPlatform.system;
  libExt = if pkgs.stdenv.hostPlatform.isDarwin then ".dylib" else ".so";

  app = mkLogosQmlModule {
    src = fixturesRoot + "/ui-qml-module-backend";
    configFile = fixturesRoot + "/ui-qml-module-backend/metadata.json";
  };
  lgx = app.packages.${system}.lgx;
  backendLib = app.packages.${system}.lib;

  # A wrong value, or the key on an app with no .rep backend, must fail the
  # evaluation rather than quietly build a ui-host backend.
  withMetadata = srcDir: patch: mkLogosQmlModule {
    src = fixturesRoot + "/${srcDir}";
    configFile = builtins.toFile "metadata.json" (builtins.toJSON (
      builtins.fromJSON (builtins.readFile (fixturesRoot + "/${srcDir}/metadata.json")) // patch));
  };
  fails = m: !(builtins.tryEval (builtins.deepSeq m.packages.${system}.default.drvPath true)).success;
  misspelled = fails (withMetadata "ui-qml-module-backend" { backend = "modul"; });
  withoutRep = fails (withMetadata "qml-module" { backend = "module"; });
  # The common case: a backend (`main`) with no .rep view contract.
  withoutCodegen = fails (mkLogosQmlModule {
    src = fixturesRoot + "/ui-qml-module-backend";
    configFile = builtins.toFile "metadata.json" (builtins.toJSON (builtins.removeAttrs
      (builtins.fromJSON (builtins.readFile (fixturesRoot + "/ui-qml-module-backend/metadata.json")))
      [ "codegen" ]));
  });

in pkgs.runCommand "qml-module-backend-tests" {
  nativeBuildInputs = [ pkgs.jq pkgs.gnutar pkgs.gzip logosModule pkgs.qt6.qttools ];
} ''
  set -euo pipefail
  pkg=$(find ${lgx} -name '*.lgx' | head -1)
  test -n "$pkg"
  mkdir x && tar -xzf "$pkg" -C x
  variant=$(find x/variants -mindepth 1 -maxdepth 1 -type d | head -1)
  test -n "$variant"

  test -f "$variant/ui_example_backend_plugin${libExt}"
  echo "PASS: the backend plugin ships in the app's .lgx"
  test -f "$variant/qml/Main.qml"
  echo "PASS: the view ships next to it"
  if find x -name 'ui_example_plugin${libExt}' | grep -q .; then
    echo "FAIL: a ui-host plugin was built as well" >&2; exit 1
  fi
  echo "PASS: no ui-host plugin"

  test "$(jq -r .backend "$variant/metadata.json")" = ui_example_backend
  test "$(jq -r .main "$variant/metadata.json")" = ui_example_backend_plugin
  test "$(jq -r .type "$variant/metadata.json")" = ui_qml
  echo "PASS: shipped metadata.json names the backend module and its file"

  # And the signed manifest, which a shell reads before anything is installed
  # (nix-bundle-lgx copies the key; logos-package 0.7.0 keeps it).
  test "$(jq -r .backend x/manifest.json)" = ui_example_backend
  echo "PASS: the .lgx manifest names the backend module"

  ${if misspelled then "true" else "echo 'FAIL: backend = \"modul\" evaluated'; exit 1"}
  ${if withoutRep then "true" else "echo 'FAIL: backend = module without a .rep backend evaluated'; exit 1"}
  ${if withoutCodegen then "true" else "echo 'FAIL: backend = module with main but no codegen.rep evaluated'; exit 1"}
  echo "PASS: a wrong backend value, or the key without a .rep backend, is an error"

  # What logos core sees: the provider's methods, not the plugin QObject's
  # (which has deleteLater, initLogos, ... — callable by any token holder if
  # the generated glue handed core the plugin itself).
  export QT_QPA_PLATFORM=offscreen
  methods=$(lm methods ${backendLib}/lib/ui_example_backend_plugin${libExt} --json \
    | jq -c '[.[].name]')
  echo "backend methods: $methods"
  test "$methods" = '["view_endpoint"]'
  echo "PASS: the backend module's only method is view_endpoint()"

  # The backend is a core module: its embedded metadata must not carry the
  # view's keys. qtplugininfo prints all of it (lm prints selected fields only).
  embedded=$(qtplugininfo --full-json ${backendLib}/lib/ui_example_backend_plugin${libExt} \
             | jq -c '.. | objects | select(has("name") and .name == "ui_example_backend")' | head -1)
  echo "backend metadata: $embedded"
  test "$(jq -r '.type' <<<"$embedded")" = core
  for key in backend provides uses view icon; do
    if [ "$(jq -r --arg k "$key" 'has($k)' <<<"$embedded")" = true ]; then
      echo "FAIL: the backend module carries the view's \"$key\""; exit 1
    fi
  done
  echo "PASS: the backend module is type core and carries none of the view's keys"

  touch $out
''
