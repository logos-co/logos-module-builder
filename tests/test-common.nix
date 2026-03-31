# Tests for common.nix
{ pkgs, lib, assertEq, assertBool, assertHasAttr, common }:

let
  # Mock pkgs for platform-specific tests
  mockLinux = {
    stdenv.hostPlatform = { isDarwin = false; isWindows = false; isLinux = true; };
  };
  mockDarwin = {
    stdenv.hostPlatform = { isDarwin = true; isWindows = false; isLinux = false; };
  };
  mockWindows = {
    stdenv.hostPlatform = { isDarwin = false; isWindows = true; isLinux = false; };
  };

in [
  # ---------------------------------------------------------------------------
  # systems
  # ---------------------------------------------------------------------------
  (assertEq "systems has 4 entries" (builtins.length common.systems) 4)
  (assertBool "systems contains aarch64-darwin"
    (builtins.elem "aarch64-darwin" common.systems) true)
  (assertBool "systems contains x86_64-linux"
    (builtins.elem "x86_64-linux" common.systems) true)
  (assertBool "systems contains aarch64-linux"
    (builtins.elem "aarch64-linux" common.systems) true)
  (assertBool "systems contains x86_64-darwin"
    (builtins.elem "x86_64-darwin" common.systems) true)

  # ---------------------------------------------------------------------------
  # nameFormats
  # ---------------------------------------------------------------------------

  # Standard snake_case name
  (assertEq "nameFormats.snake" (common.nameFormats "my_module").snake "my_module")
  (assertEq "nameFormats.pascal" (common.nameFormats "my_module").pascal "MyModule")
  (assertEq "nameFormats.camel" (common.nameFormats "my_module").camel "myModule")
  (assertEq "nameFormats.upper" (common.nameFormats "my_module").upper "MY_MODULE")

  # Single word (no underscores)
  (assertEq "nameFormats single word snake" (common.nameFormats "hello").snake "hello")
  (assertEq "nameFormats single word pascal" (common.nameFormats "hello").pascal "Hello")
  (assertEq "nameFormats single word camel" (common.nameFormats "hello").camel "hello")
  (assertEq "nameFormats single word upper" (common.nameFormats "hello").upper "HELLO")

  # Three parts
  (assertEq "nameFormats 3 parts pascal" (common.nameFormats "a_b_c").pascal "ABC")
  (assertEq "nameFormats 3 parts camel" (common.nameFormats "a_b_c").camel "aBC")

  # Hyphen in name (upper replaces - with _)
  (assertEq "nameFormats hyphen upper" (common.nameFormats "my-module").upper "MY_MODULE")

  # Edge cases
  (assertEq "nameFormats empty string snake" (common.nameFormats "").snake "")
  (assertEq "nameFormats empty string upper" (common.nameFormats "").upper "")
  (assertEq "nameFormats already capitalized pascal"
    (common.nameFormats "My_Module").pascal "MyModule")
  (assertEq "nameFormats four segments upper"
    (common.nameFormats "a_b_c_d").upper "A_B_C_D")

  # ---------------------------------------------------------------------------
  # getLibExtension
  # ---------------------------------------------------------------------------
  (assertEq "getLibExtension linux" (common.getLibExtension mockLinux) "so")
  (assertEq "getLibExtension darwin" (common.getLibExtension mockDarwin) "dylib")
  (assertEq "getLibExtension windows" (common.getLibExtension mockWindows) "dll")

  # ---------------------------------------------------------------------------
  # getPluginFilename
  # ---------------------------------------------------------------------------
  (assertEq "getPluginFilename linux"
    (common.getPluginFilename mockLinux "my_module") "my_module_plugin.so")
  (assertEq "getPluginFilename darwin"
    (common.getPluginFilename mockDarwin "my_module") "my_module_plugin.dylib")

  # ---------------------------------------------------------------------------
  # recursiveMerge
  # ---------------------------------------------------------------------------

  # Simple merge: last wins for scalars
  (assertEq "recursiveMerge scalar last wins"
    (common.recursiveMerge [ { a = 1; } { a = 2; } ]).a
    2)

  # Nested merge
  (assertEq "recursiveMerge nested"
    (common.recursiveMerge [ { a = { x = 1; }; } { a = { y = 2; }; } ]).a
    { x = 1; y = 2; })

  # List concatenation with dedup
  (assertEq "recursiveMerge list concat"
    (common.recursiveMerge [ { a = [ 1 2 ]; } { a = [ 2 3 ]; } ]).a
    [ 1 2 3 ])

  # Non-overlapping keys
  (assertEq "recursiveMerge disjoint"
    (common.recursiveMerge [ { a = 1; } { b = 2; } ])
    { a = 1; b = 2; })

  # Single attrset (identity)
  (assertEq "recursiveMerge single" (common.recursiveMerge [ { a = 1; } ]) { a = 1; })

  # Empty merge
  (assertEq "recursiveMerge empty" (common.recursiveMerge [ {} {} ]) {})

  # Deep nesting
  (assertEq "recursiveMerge deep"
    (common.recursiveMerge [
      { a = { b = { c = 1; }; }; }
      { a = { b = { d = 2; }; }; }
    ]).a.b
    { c = 1; d = 2; })

  # Three-way merge
  (assertEq "recursiveMerge three-way"
    (common.recursiveMerge [ { a = 1; } { b = 2; } { c = 3; } ])
    { a = 1; b = 2; c = 3; })

  # Scalar overrides nested (last wins)
  (assertEq "recursiveMerge scalar overrides nested"
    (common.recursiveMerge [ { a = { x = 1; }; } { a = 42; } ]).a
    42)

  # Edge cases
  (assertEq "recursiveMerge empty list" (common.recursiveMerge []) {})

  (assertEq "recursiveMerge list then scalar"
    (common.recursiveMerge [ { a = [ 1 2 ]; } { a = 42; } ]).a
    42)

  (assertEq "recursiveMerge null value"
    (common.recursiveMerge [ { a = null; } { a = 1; } ]).a
    1)

  # ---------------------------------------------------------------------------
  # collectAllModuleDeps — empty case
  # (comprehensive tests in test-collectAllModuleDeps.nix)
  # ---------------------------------------------------------------------------
  (assertEq "collectAllModuleDeps empty"
    (common.collectAllModuleDeps "x86_64-linux" {} [])
    {})
]
