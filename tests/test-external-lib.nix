# Tests for mkExternalLib.nix
{ assertEq, assertBool, mkExternalLib }:

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
  # generateVendorBuildScript — check script content
  # ---------------------------------------------------------------------------

  # Default build command (make)
  (let
    script = mkExternalLib.generateVendorBuildScript {
      config = {};
      extLib = { name = "mylib"; vendor_path = "vendor/mylib"; };
    };
  in assertBool "vendor script contains make"
    (builtins.match ".*make.*" script != null) true)

  (let
    script = mkExternalLib.generateVendorBuildScript {
      config = {};
      extLib = { name = "mylib"; vendor_path = "vendor/mylib"; };
    };
  in assertBool "vendor script contains vendor path"
    (builtins.match ".*vendor/mylib.*" script != null) true)

  (let
    script = mkExternalLib.generateVendorBuildScript {
      config = {};
      extLib = { name = "mylib"; vendor_path = "vendor/mylib"; };
    };
  in assertBool "vendor script copies libs"
    (builtins.match ".*find.*libmylib.*" script != null) true)

  # Custom build command
  (let
    script = mkExternalLib.generateVendorBuildScript {
      config = {};
      extLib = { name = "foo"; vendor_path = "lib"; build_command = "cmake --build ."; };
    };
  in assertBool "vendor script uses custom command"
    (builtins.match ".*cmake --build.*" script != null) true)

  # Custom build script
  (let
    script = mkExternalLib.generateVendorBuildScript {
      config = {};
      extLib = { name = "bar"; vendor_path = "lib"; build_script = "build.sh"; };
    };
  in assertBool "vendor script uses build_script"
    (builtins.match ".*build.sh.*" script != null) true)

  # ---------------------------------------------------------------------------
  # Universal / go_build pattern (mirrors logos-accounts-module)
  # ---------------------------------------------------------------------------
  (assertBool "hasExternalLibs universal" (mkExternalLib.hasExternalLibs configUniversal) true)
  (assertEq "getExternalLibNames universal"
    (mkExternalLib.getExternalLibNames configUniversal) [ "golib" ])

  # Vendor build script with custom build_command (no vendor_path — uses ".")
  (let
    script = mkExternalLib.generateVendorBuildScript {
      config = {};
      extLib = { name = "golib"; vendor_path = "."; build_command = "make static-library"; };
    };
  in assertBool "vendor script uses custom build_command"
    (builtins.match ".*make static-library.*" script != null) true)

  # go_build and output_pattern are preserved in the config (passthrough fields)
  (assertBool "universal config: go_build preserved"
    (builtins.head configUniversal.external_libraries).go_build true)
  (assertEq "universal config: output_pattern preserved"
    (builtins.head configUniversal.external_libraries).output_pattern "build/libgolib.*")
  (assertEq "universal config: build_command preserved"
    (builtins.head configUniversal.external_libraries).build_command "make static-library")
]
