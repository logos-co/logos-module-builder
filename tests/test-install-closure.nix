# A .lgx is a gzipped tar, so #lgx and #install keep the store paths their plugin loads only
# through nix-bundle-lgx's payload record; #install reaches it via its nix-bundle-lgx follows.
{ pkgs, mkLogosModule, fixturesRoot, runtimeLib }:

let
  system = pkgs.stdenv.hostPlatform.system;
  fixture = fixturesRoot + "/runtime-lib-module";
  module = mkLogosModule {
    src = fixture;
    configFile = fixture + "/metadata.json";
  };
  inherit (module.packages.${system}) lgx install;
  closureOf = drv: "${pkgs.closureInfo { rootPaths = [ drv ]; }}/store-paths";

  # Its own derivation, so the sandbox holds #install's recorded closure and not #lgx's.
  loadProbe = pkgs.runCommandCC "install-closure-load-probe" { } ''
    cat > probe.c <<'C'
    #include <dlfcn.h>
    #include <stdio.h>
    int main(int argc, char** argv) {
      if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) { printf("%s\n", dlerror()); return 1; }
      return 0;
    }
    C
    $CC probe.c -o probe
    plugin=${install}/modules/runtime_lib_probe/runtime_lib_probe_plugin.so
    test -f "$plugin" || { echo "FAIL: no plugin at $plugin"; find ${install}; exit 1; }
    ./probe "$plugin" || { echo "FAIL: the installed plugin does not load from #install's closure"; exit 1; }
    touch $out
  '';
in pkgs.runCommand "install-closure-tests" { } ''
  set -euo pipefail
  grep -qxF ${runtimeLib} ${closureOf lgx} \
    || { echo "FAIL: #lgx does not carry ${runtimeLib}, which its plugin links"; exit 1; }
  grep -qxF ${runtimeLib} ${closureOf install} \
    || { echo "FAIL: #install does not carry ${runtimeLib}, which its plugin links"; exit 1; }
  ${pkgs.lib.optionalString pkgs.stdenv.isLinux "test -e ${loadProbe}"}
  echo "PASS: #lgx and #install carry ${runtimeLib}"
  mkdir -p $out && echo passed > $out/results.txt
''
