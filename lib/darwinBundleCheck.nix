# macOS: nothing an assembled app loads may be missing on the machine that runs it.
#
# Modules reach an app inside LGX archives (see mkStandaloneApp), and nix cannot
# scan a tar for store paths, so an absolute path baked into a bundled Mach-O is
# invisible to reference scanning: nix never registers it, never substitutes it,
# and the plugin fails to dlopen wherever it does not already exist — which
# makes the failure look intermittent, since whether a path happens to be on the
# machine depends on what else that machine built. Linux has no equivalent hole
# because autoPatchelfHook resolves and validates every DT_NEEDED at build time.
{ lib }:

rec {
  # `logos-check-dylib-closure <store-paths-file> <root>...` exits non-zero,
  # naming every offender, when a Mach-O under any <root> loads an absolute
  # store path that <store-paths-file> does not list.
  validator = pkgs: pkgs.writeShellApplication {
    name = "logos-check-dylib-closure";
    runtimeInputs = [ pkgs.darwin.cctools ];
    text = ''
      paths="$1"
      shift

      loads=$(mktemp)
      for root in "$@"; do
        find -L "$root" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 |
          while IFS= read -r -d "" macho; do
            # `find` also turns up scripts and data, which otool rejects — a
            # rejected file simply has no load commands to collect. LC_ID_DYLIB
            # is left out on purpose: it names the file itself, not a load.
            otool -l "$macho" 2>/dev/null | awk -v macho="$macho" '
              $1 == "cmd" { collect = ($2 ~ /^LC_(LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB)$/) }
              collect && $1 == "name" && $2 ~ "^/nix/store/" { print macho, $2 }
            ' || true
          done
      done > "$loads"

      dangling=0
      while read -r macho dep; do
        # /nix/store/<hash>-<name>/lib/libfoo.dylib -> /nix/store/<hash>-<name>
        if ! grep -qxF "$(echo "$dep" | cut -d/ -f1-4)" "$paths"; then
          if [ "$dangling" -eq 0 ]; then
            echo "error: these libraries load paths that are outside the closure:" >&2
          fi
          printf '  %s\n    loads %s\n' "$macho" "$dep" >&2
          dangling=1
        fi
      done < "$loads"

      if [ "$dangling" -ne 0 ]; then
        echo >&2
        echo "Nothing installs those paths alongside the library that wants them, so it" >&2
        echo "will fail to load. Bundle each one beside its consumer and point the load" >&2
        echo "command at @loader_path (install_name_tool -change), in the postInstall of" >&2
        echo "the module that ships the consumer." >&2
        exit 1
      fi
    '';
  };

  # Fails to build when a Mach-O under `roots` loads an absolute store path
  # outside the closure of `closureRoots` — the paths the app actually realises.
  # Returns null off darwin, where there is nothing to check.
  check = { pkgs, name, roots, closureRoots }:
    if !pkgs.stdenv.hostPlatform.isDarwin then null
    else pkgs.runCommand "${name}-dylib-closure" {} ''
      ${lib.getExe (validator pkgs)} \
        ${pkgs.closureInfo { rootPaths = closureRoots; }}/store-paths \
        ${lib.escapeShellArgs (map toString roots)}
      touch $out
    '';
}
