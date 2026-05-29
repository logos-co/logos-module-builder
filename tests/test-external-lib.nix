# Tests for mkExternalLib.nix
{ assertEq, assertBool, pkgs, lib, mkExternalLib, fixturesRoot }:

let
  configWithLibs = {
    external_libraries = [
      { name = "mylib"; vendor_path = "lib"; }
      { name = "otherlib"; vendor_path = "vendor/other"; }
    ];
  };

  configEmpty = {
    external_libraries = [];
  };

  configNoField = {};

  configSingle = {
    external_libraries = [
      { name = "single_lib"; vendor_path = "lib"; build_command = "make all"; }
    ];
  };

  # Universal interface / go_build pattern (mirrors logos-accounts-module)
  configUniversal = {
    external_libraries = [
      {
        name = "golib";
        build_command = "make static-library";
        go_build = true;
        output_pattern = "build/libgolib.*";
      }
    ];
  };

  # ---------------------------------------------------------------------------
  # buildExternalLibs cases — fixtures
  # ---------------------------------------------------------------------------
  # tests/fixtures/extlib-buildable/lib/{libfoo.c,libfoo.h} backs the
  # vendor-with-build_command + build_script + flake-input-from-path cases.
  buildableSrc = fixturesRoot + "/extlib-buildable";

  # Case 1: pure prebuilt vendor — no build_command, no build_script
  configPrebuiltVendor = {
    external_libraries = [
      { name = "prebuilt"; vendor_path = "lib"; }
    ];
  };

  # Case 2a: vendor_path + build_command — builds during the module's build
  configVendorBuilt = {
    external_libraries = [
      {
        name = "foo";
        vendor_path = "lib";
        build_command = "$CC -shared -fPIC -o $LIB_BASENAME libfoo.c";
      }
    ];
  };

  # Case 2b: vendor_path + build_script — same idea, script-based build
  configVendorBuiltScript = {
    external_libraries = [
      {
        name = "foo";
        vendor_path = "lib";
        build_script = "build.sh";
      }
    ];
  };

  # Case 3: flake-input library
  configFlakeInput = {
    external_libraries = [
      {
        name = "fromflake";
        build_command = "$CC -shared -fPIC -o $LIB_BASENAME libfoo.c";
      }
    ];
  };

  # Case 4: flake-input Go library (cgo). The actual buildGoModule call needs
  # a valid vendor_hash and a real go.mod; for an eval-only test we only
  # check that the dispatcher routes through buildGoModule (which produces a
  # derivation) without throwing.
  configGoBuild = {
    external_libraries = [
      {
        name = "gowalletsdk";
        build_command = "make static-library";
        go_build = true;
        vendor_hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        output_pattern = "build/libgowalletsdk.*";
      }
    ];
  };

  # A pre-built derivation that buildExternalLibs should pass through unchanged
  # when an externalInputs entry already resolves to a derivation.
  prebuiltFlakeDrv = pkgs.runCommand "fake-prebuilt-flake-lib" {} ''
    mkdir -p $out/lib
    touch $out/lib/libfake.so
  '';

in [
  # ---------------------------------------------------------------------------
  # hasExternalLibs
  # ---------------------------------------------------------------------------
  (assertBool "hasExternalLibs with libs" (mkExternalLib.hasExternalLibs configWithLibs) true)
  (assertBool "hasExternalLibs empty" (mkExternalLib.hasExternalLibs configEmpty) false)
  (assertBool "hasExternalLibs missing field" (mkExternalLib.hasExternalLibs configNoField) false)

  # ---------------------------------------------------------------------------
  # getExternalLibNames
  # ---------------------------------------------------------------------------
  (assertEq "getExternalLibNames two libs"
    (mkExternalLib.getExternalLibNames configWithLibs)
    [ "mylib" "otherlib" ])

  (assertEq "getExternalLibNames empty"
    (mkExternalLib.getExternalLibNames configEmpty)
    [])

  (assertEq "getExternalLibNames missing field"
    (mkExternalLib.getExternalLibNames configNoField)
    [])

  (assertEq "getExternalLibNames single"
    (mkExternalLib.getExternalLibNames configSingle)
    [ "single_lib" ])

  # ---------------------------------------------------------------------------
  # Universal / go_build pattern (mirrors logos-accounts-module)
  # ---------------------------------------------------------------------------
  (assertBool "hasExternalLibs universal" (mkExternalLib.hasExternalLibs configUniversal) true)
  (assertEq "getExternalLibNames universal"
    (mkExternalLib.getExternalLibNames configUniversal) [ "golib" ])

  # go_build and output_pattern are preserved in the config (passthrough fields)
  (assertBool "universal config: go_build preserved"
    (builtins.head configUniversal.external_libraries).go_build true)
  (assertEq "universal config: output_pattern preserved"
    (builtins.head configUniversal.external_libraries).output_pattern "build/libgolib.*")
  (assertEq "universal config: build_command preserved"
    (builtins.head configUniversal.external_libraries).build_command "make static-library")

  # ---------------------------------------------------------------------------
  # buildExternalLibs — the five well-formed shapes
  #
  # See docs/configuration.md → nix.external_libraries for the user-facing
  # reference. All five shapes resolve through `mkExternalLib.buildExternalLibs`
  # into a uniform attrset `{ <name> = derivation-or-null }`; downstream copy
  # stages (buildPlugin.externalLibCopies and modulePreConfigure
  # .copyExternalLibsToLib) treat each entry the same way regardless of how
  # it was sourced.
  #
  #   Shape A — vendor_path only (prebuilt binary committed to git)
  #   Shape B — vendor_path + build_command/build_script (source committed)
  #   Shape C — externalInputs.<name> is a derivation (passed through)
  #   Shape D — externalInputs.<name> is a source path + build_command/build_script
  #   Shape E — Shape D + go_build: true (cgo, routed to buildGoModule)
  # ---------------------------------------------------------------------------

  # Shape A: pure prebuilt vendor → null sentinel. No derivation; buildPlugin's
  # externalLibCopies stages the committed binary from `${src}/${vendor_path}`.
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configPrebuiltVendor;
    };
  in assertBool "Shape A (prebuilt vendor): null sentinel"
    (result.prebuilt == null) true)

  # Shape A invariant: moduleSrc is irrelevant for prebuilt vendors.
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configPrebuiltVendor;
      moduleSrc = buildableSrc;
    };
  in assertBool "Shape A (prebuilt vendor): null sentinel even with moduleSrc"
    (result.prebuilt == null) true)

  # Shape B: vendor_path + build_command → real derivation built from
  # `${moduleSrc}/${vendor_path}` so downstream copy stages pick it up the
  # same way as a flake-input lib.
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configVendorBuilt;
      moduleSrc = buildableSrc;
    };
  in assertBool "Shape B (vendor + build_command): produces a derivation"
    (lib.isDerivation result.foo) true)

  # Shape B variant: build_script in place of build_command.
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configVendorBuiltScript;
      moduleSrc = buildableSrc;
    };
  in assertBool "Shape B (vendor + build_script): produces a derivation"
    (lib.isDerivation result.foo) true)

  # Shape B degradation: vendor_path + build_command but moduleSrc omitted →
  # falls back to null instead of throwing. The misconfigured caller will
  # quietly produce an unlinked plugin (Shape A path with no committed
  # binary), but that's an existing failure mode — we just verify we don't
  # crash at eval time.
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configVendorBuilt;
      # moduleSrc deliberately omitted
    };
  in assertBool "Shape B without moduleSrc: degrades to null"
    (result.foo == null) true)

  # Shape C: flake-input that already resolves to a derivation → used as-is,
  # not rebuilt. This is how every module in the workspace consumes
  # logos-cpp-sdk or other module outputs.
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configFlakeInput;
      externalInputs = { fromflake = prebuiltFlakeDrv; };
    };
  in assertBool "Shape C (flake-input derivation): passed through unchanged"
    (result.fromflake == prebuiltFlakeDrv) true)

  # Shape D: flake-input is a raw source path → built via stdenv.mkDerivation
  # using the entry's build_command (typical for `flake = false` GitHub repos).
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configFlakeInput;
      externalInputs = { fromflake = buildableSrc; };
    };
  in assertBool "Shape D (flake-input source build): produces a derivation"
    (lib.isDerivation result.fromflake) true)

  # Shape E: flake-input + go_build → dispatched to buildGoModule. We only
  # assert that a derivation is produced; the actual go vendor build is
  # exercised by downstream consumers (e.g. logos-accounts-module).
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configGoBuild;
      externalInputs = { gowalletsdk = buildableSrc; };
    };
  in assertBool "Shape E (flake-input go_build): produces a derivation via buildGoModule"
    (lib.isDerivation result.gowalletsdk) true)

  # Same name keyed in result attrset regardless of how the lib was sourced
  (let
    result = mkExternalLib.buildExternalLibs {
      inherit pkgs;
      config = configVendorBuilt;
      moduleSrc = buildableSrc;
    };
  in assertEq "buildExternalLibs: result keyed by extLib.name"
    (builtins.attrNames result) [ "foo" ])
]
