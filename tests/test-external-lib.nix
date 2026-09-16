# Tests for mkExternalLib.nix
{ assertEq, assertBool, assertThrows, mkExternalLib }:

let
  # resolveInput, as mkLogosModule and mkLogosModuleTests both call it.
  resolve = mkExternalLib.resolveInput { system = "x86_64-linux"; };
  resolvePortable = mkExternalLib.resolveInput { system = "x86_64-linux"; variant = "portable"; };
  resolveWindows = mkExternalLib.resolveInput { system = "x86_64-windows"; };
  resolveWindowsPortable = mkExternalLib.resolveInput { system = "x86_64-windows"; variant = "portable"; };
  # Publishes its Windows build under the platform that builds it, as zerokit does.
  crossFlake = {
    packages.x86_64-linux = {
      default = { marker = "linux-default"; };
      lib = { marker = "linux-lib"; };
      lib-windows-x86_64 = { marker = "windows-lib"; };
      lib-portable-windows-x86_64 = { marker = "windows-lib-portable"; };
    };
  };
  crossEntry = {
    input = crossFlake;
    packages.default = "lib";
    systems.x86_64-windows = {
      system = "x86_64-linux";
      packages = { default = "lib-windows-x86_64"; portable = "lib-portable-windows-x86_64"; };
    };
  };
  fakeFlake = {
    outPath = "/unbuilt-source";
    packages.x86_64-linux = {
      default = { marker = "default"; };
      lib = { marker = "lib"; };
      lib-portable = { marker = "lib-portable"; };
    };
  };

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
  # resolveInput
  # ---------------------------------------------------------------------------
  (assertEq "resolveInput: bare flake input -> packages.default, not its source"
    (resolve "mylib" fakeFlake).marker "default")
  (assertEq "resolveInput: structured -> named package"
    (resolve "mylib" { input = fakeFlake; packages.default = "lib"; }).marker "lib")
  (assertEq "resolveInput: structured without packages -> default"
    (resolve "mylib" { input = fakeFlake; }).marker "default")
  (assertEq "resolveInput: portable variant"
    (resolvePortable "mylib" { input = fakeFlake; packages = { default = "lib"; portable = "lib-portable"; }; }).marker
    "lib-portable")
  (assertEq "resolveInput: variant falls back to packages.default"
    (resolvePortable "mylib" { input = fakeFlake; packages.default = "lib"; }).marker "lib")
  (assertEq "resolveInput: non-flake source passes through"
    (resolve "mylib" { outPath = "/src"; }).outPath "/src")
  (assertThrows "resolveInput: structured entry naming a missing package"
    (resolve "mylib" { input = fakeFlake; packages.default = "nope"; }))
  (assertEq "resolveInput: systems override reads another system's package set"
    (resolveWindows "mylib" crossEntry).marker "windows-lib")
  (assertEq "resolveInput: systems override, portable variant"
    (resolveWindowsPortable "mylib" crossEntry).marker "windows-lib-portable")
  (assertEq "resolveInput: systems override leaves other systems alone"
    (resolve "mylib" crossEntry).marker "linux-lib")
  (assertEq "resolveInput: same-system override renames only"
    (resolve "mylib" { input = crossFlake; packages.default = "nope"; systems.x86_64-linux.packages.default = "lib"; }).marker
    "linux-lib")
  (assertThrows "resolveInput: an override that moves must name its packages"
    (resolveWindows "mylib" { input = crossFlake; packages.default = "lib"; systems.x86_64-windows.system = "x86_64-linux"; }))
  (assertThrows "resolveInput: a moved override never falls back to that system's default"
    (resolveWindows "mylib" { input = crossFlake; systems.x86_64-windows = { system = "x86_64-linux"; packages.portable = "lib-portable-windows-x86_64"; }; }))
  (assertThrows "resolveInput: systems override naming a missing package"
    (resolveWindows "mylib" { input = crossFlake; systems.x86_64-windows = { system = "x86_64-linux"; packages.default = "nope"; }; }))

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
