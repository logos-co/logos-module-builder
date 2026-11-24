# A core module that asks for or provides intents ships its metadata.json in
# lib/ — and so in its .lgx and install directory — where intents_module reads
# `provides` / `uses`. One that declares neither ships nothing new.
{ pkgs, mkLogosModule, templatesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;
  src = templatesRoot + "/minimal-module";
  base = builtins.fromJSON (builtins.readFile (src + "/metadata.json"));
  build = patch: (mkLogosModule {
    inherit src;
    configFile = builtins.toFile "metadata.json" (builtins.toJSON (base // patch));
  }).packages.${system}.lib;

  plain = build { };
  asking = build { uses = [ { intent = "signing.approve"; } ]; };
  providing = build { provides = [ { intent = "test.echo"; } ]; };

in pkgs.runCommand "intent-declarations-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -euo pipefail
  if [ -e ${plain}/lib/metadata.json ]; then
    echo "FAIL: a module with no intents ships metadata.json"; exit 1
  fi
  echo "PASS: no intents, no metadata.json"
  test "$(jq -r '.uses[0].intent' ${asking}/lib/metadata.json)" = signing.approve
  echo "PASS: a module that asks ships its uses"
  test "$(jq -r '.provides[0].intent' ${providing}/lib/metadata.json)" = test.echo
  echo "PASS: a module that provides ships its provides"
  mkdir -p $out && echo passed > $out/results.txt
''
