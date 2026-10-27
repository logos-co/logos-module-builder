# `nix run .` / `.#ui-dev` for UI modules: hands the module to Basecamp's
# `dev` command (standalone mode), which installs its dependencies and runs it.
# This file only says WHAT to run; installing dependencies, checking versions
# and `--app` (other apps opened next to it) are Basecamp's.
#
# Passed to Basecamp: the module's `.#install`; every dependency, direct and
# transitive, as the .lgx package THIS flake builds (`--dep-package`), so its
# `follows` and `--override-input` hold — Basecamp installs them as they are;
# each direct dependency's source too (`--dep`), which an `--app` is built
# against; and for ui-dev the view's source dir for QML hot reload. Other
# arguments pass through.
#
# Basecamp is NOT a flake input of this builder: it already depends on the
# builder through the modules it bundles, and pulling it in would put its whole
# lock into every module's. The launcher runs `nix run <basecamp>#dev`, with
# <basecamp> = LOGOS_BASECAMP or github:logos-co/logos-basecamp.
# LOGOS_BASECAMP_DEV, a prebuilt `logos-basecamp-dev`, skips that step.
#
# The same goes for UI tests: `nix run .#ui-tests` passes tests/*.mjs to
# Basecamp's `dev --test`. Not a check — the Nix sandbox cannot fetch Basecamp.
#
# `.#ui-dev-portable` is the same against the portable build — what users run —
# through Basecamp's `dev-portable`: the module's `.#install-portable` and every
# dependency as its portable .lgx (a portable Basecamp loads only portable
# variants). LOGOS_BASECAMP_DEV_PORTABLE names a prebuilt
# `logos-basecamp-dev-portable`.
#
# Returns { package; portablePackage; app; testsApp; }: `.#ui-dev`,
# `.#ui-dev-portable` (null without installPortablePkg), `apps.default` and
# `apps.ui-tests` (null without test files).
{ pkgs
, system
, common
, name                # module name, as in metadata.json
, installPkg          # the module's `.#install` (modules/ and/or plugins/)
, installPortablePkg ? null  # its `.#install-portable`, for ui-dev-portable
, flakeInputs ? {}
, dependencies ? []   # metadata.json `dependencies` (names)
, viewEntry ? null    # metadata.json `view`, for QML hot reload
, testFiles ? []      # tests/*.mjs
}:

let
  lib = pkgs.lib;

  depInputs = lib.filterAttrs (n: _: builtins.elem n dependencies) flakeInputs;

  depArgsFor = portable: lib.concatStringsSep " " (
    lib.mapAttrsToList (n: pkg: lib.escapeShellArgs [ "--dep-package" "${n}=${pkg}" ])
      (common.collectModuleDeps { inherit portable; } system flakeInputs dependencies)
    ++ lib.mapAttrsToList (n: input: lib.escapeShellArgs [ "--dep" "${n}=path:${input.outPath}" ]) depInputs);
  depArgs = depArgsFor false;

  basecampFor = portable:
    let
      attr = if portable then "dev-portable" else "dev";
      prebuilt = if portable then "LOGOS_BASECAMP_DEV_PORTABLE" else "LOGOS_BASECAMP_DEV";
    in ''
      if [ -n "''${${prebuilt}:-}" ]; then
        exec "''$${prebuilt}" "''${args[@]}" "$@"
      fi
      ref="''${LOGOS_BASECAMP:-github:logos-co/logos-basecamp}"
      echo "run-logos-standalone-ui: starting $ref#${attr}" >&2
      echo "  (built or downloaded on first use; set ${prebuilt} to a prebuilt logos-basecamp-${attr} to skip this)" >&2
      exec nix run "$ref#${attr}" -- "''${args[@]}" "$@"
    '';
  basecamp = basecampFor false;

  # ui-dev: hot-reload the view from the source tree when run from the repo
  # root. The candidates mirror where the build looks for the view directory.
  devQmlPrelude = lib.optionalString (viewEntry != null) ''
    if [ -z "''${DEV_QML_PATH:-}" ]; then
      for candidate in "$PWD/src/${dirOf viewEntry}" "$PWD/${dirOf viewEntry}"; do
        if [ -f "$candidate/${baseNameOf viewEntry}" ]; then
          DEV_QML_PATH="$candidate"
          echo "run-logos-standalone-ui: hot-reloading QML from $candidate"
          echo "  (export DEV_QML_PATH to override, or LOGOS_QML_HOT_RELOAD=0 to disable)"
          break
        fi
      done
    fi
  '';

  mkRunner = { hotReload, portable ? false }: pkgs.writeShellApplication {
    name = if portable then "run-logos-standalone-ui-portable" else "run-logos-standalone-ui";
    text = ''
      args=(--module ${if portable then installPortablePkg else installPkg} ${depArgsFor portable})
      ${lib.optionalString hotReload devQmlPrelude}
      if [ -n "''${DEV_QML_PATH:-}" ]; then
        args+=(--qml-source "${name}=$DEV_QML_PATH")
      fi
      ${basecampFor portable}
    '';
  };
  mkRun = hotReload: mkRunner { inherit hotReload; };

  runTests = pkgs.writeShellApplication {
    name = "run-logos-ui-tests";
    text = ''
      args=(--module ${installPkg} ${depArgs} ${lib.concatMapStringsSep " " (f: "--test ${f}") testFiles})
      ${basecamp}
    '';
  };
in {
  package = mkRun true;
  portablePackage =
    if installPortablePkg == null then null
    else mkRunner { hotReload = true; portable = true; };
  app = {
    type = "app";
    program = "${mkRun false}/bin/run-logos-standalone-ui";
  };
  testsApp =
    if testFiles == [] then null
    else { type = "app"; program = "${runTests}/bin/run-logos-ui-tests"; };
}
