# Tests for collectAllModuleDeps in common.nix
# Uses mock flake inputs — no real derivations needed since the function
# just walks attrsets and collects package references.
{ assertEq, assertBool, assertHasAttr, common }:

let
  sys = "x86_64-linux";

  # --- Mock module inputs ---
  # Each mock simulates a flake input with packages.<system>.lgx, config, and inputs.

  # Leaf module: no dependencies, has lgx output
  mockLeaf = name: {
    packages.${sys}.lgx = "mock-lgx-${name}";
    config.dependencies = [];
    inputs = {};
  };

  # Module with lgx output and dependencies
  mockWithDeps = name: deps: depInputs: {
    packages.${sys}.lgx = "mock-lgx-${name}";
    config.dependencies = deps;
    inputs = depInputs;
  };

  # ---------------------------------------------------------------------------
  # Scenario 1: Empty dependencies
  # ---------------------------------------------------------------------------
  emptyResult = common.collectAllModuleDeps sys {} [];

  # ---------------------------------------------------------------------------
  # Scenario 2: Single direct dependency
  # ---------------------------------------------------------------------------
  singleResult = common.collectAllModuleDeps sys {
    dep_a = mockLeaf "dep_a";
  } [ "dep_a" ];

  # ---------------------------------------------------------------------------
  # Scenario 3: Two direct dependencies
  # ---------------------------------------------------------------------------
  twoDirectResult = common.collectAllModuleDeps sys {
    dep_a = mockLeaf "dep_a";
    dep_b = mockLeaf "dep_b";
  } [ "dep_a" "dep_b" ];

  # ---------------------------------------------------------------------------
  # Scenario 4: Transitive chain (A depends on B, B depends on C)
  # ---------------------------------------------------------------------------
  transitiveResult = common.collectAllModuleDeps sys {
    dep_a = mockWithDeps "dep_a" [ "dep_b" ] {
      dep_b = mockWithDeps "dep_b" [ "dep_c" ] {
        dep_c = mockLeaf "dep_c";
      };
    };
  } [ "dep_a" ];

  # ---------------------------------------------------------------------------
  # Scenario 5: Diamond dependency (A and B both depend on C)
  # ---------------------------------------------------------------------------
  diamondResult = common.collectAllModuleDeps sys {
    dep_a = mockWithDeps "dep_a" [ "dep_c" ] {
      dep_c = mockLeaf "dep_c";
    };
    dep_b = mockWithDeps "dep_b" [ "dep_c" ] {
      dep_c = mockLeaf "dep_c";
    };
  } [ "dep_a" "dep_b" ];

  # ---------------------------------------------------------------------------
  # Scenario 6: Dep not in inputs (filtered out by filterAttrs)
  # ---------------------------------------------------------------------------
  missingInputResult = common.collectAllModuleDeps sys {
    dep_a = mockLeaf "dep_a";
  } [ "dep_a" "dep_nonexistent" ];

  # ---------------------------------------------------------------------------
  # Scenario 7: Direct overrides transitive
  # If A depends on C (transitive via A's inputs), and we also list C as direct,
  # the direct C should win.
  # ---------------------------------------------------------------------------
  directOverridesTransitive = common.collectAllModuleDeps sys {
    dep_a = mockWithDeps "dep_a" [ "dep_c" ] {
      dep_c = {
        packages.${sys}.lgx = "mock-lgx-dep_c-OLD";
        config.dependencies = [];
        inputs = {};
      };
    };
    dep_c = {
      packages.${sys}.lgx = "mock-lgx-dep_c-NEW";
      config.dependencies = [];
      inputs = {};
    };
  } [ "dep_a" "dep_c" ];

  # ---------------------------------------------------------------------------
  # Scenario 8: Deep transitive chain (A -> B -> C -> D)
  # ---------------------------------------------------------------------------
  deepChainResult = common.collectAllModuleDeps sys {
    dep_a = mockWithDeps "dep_a" [ "dep_b" ] {
      dep_b = mockWithDeps "dep_b" [ "dep_c" ] {
        dep_c = mockWithDeps "dep_c" [ "dep_d" ] {
          dep_d = mockLeaf "dep_d";
        };
      };
    };
  } [ "dep_a" ];

in [
  # --- Scenario 1: Empty ---
  (assertEq "collectDeps empty" emptyResult {})

  # --- Scenario 2: Single dep ---
  (assertHasAttr "collectDeps single: has dep_a" singleResult "dep_a")
  (assertEq "collectDeps single: dep_a value" singleResult.dep_a "mock-lgx-dep_a")
  (assertEq "collectDeps single: only one key" (builtins.attrNames singleResult) [ "dep_a" ])

  # --- Scenario 3: Two direct deps ---
  (assertHasAttr "collectDeps two: has dep_a" twoDirectResult "dep_a")
  (assertHasAttr "collectDeps two: has dep_b" twoDirectResult "dep_b")
  (assertEq "collectDeps two: dep_a value" twoDirectResult.dep_a "mock-lgx-dep_a")
  (assertEq "collectDeps two: dep_b value" twoDirectResult.dep_b "mock-lgx-dep_b")

  # --- Scenario 4: Transitive chain ---
  (assertHasAttr "collectDeps transitive: has dep_a" transitiveResult "dep_a")
  (assertHasAttr "collectDeps transitive: has dep_b" transitiveResult "dep_b")
  (assertHasAttr "collectDeps transitive: has dep_c" transitiveResult "dep_c")
  (assertEq "collectDeps transitive: dep_a value" transitiveResult.dep_a "mock-lgx-dep_a")
  (assertEq "collectDeps transitive: dep_b value" transitiveResult.dep_b "mock-lgx-dep_b")
  (assertEq "collectDeps transitive: dep_c value" transitiveResult.dep_c "mock-lgx-dep_c")

  # --- Scenario 5: Diamond ---
  (assertHasAttr "collectDeps diamond: has dep_a" diamondResult "dep_a")
  (assertHasAttr "collectDeps diamond: has dep_b" diamondResult "dep_b")
  (assertHasAttr "collectDeps diamond: has dep_c" diamondResult "dep_c")
  (assertEq "collectDeps diamond: exactly 3 keys"
    (builtins.length (builtins.attrNames diamondResult)) 3)

  # --- Scenario 6: Missing input filtered ---
  (assertEq "collectDeps missing: only dep_a"
    (builtins.attrNames missingInputResult) [ "dep_a" ])

  # --- Scenario 7: Direct overrides transitive ---
  (assertEq "collectDeps override: dep_c is NEW"
    directOverridesTransitive.dep_c "mock-lgx-dep_c-NEW")

  # --- Scenario 8: Deep chain ---
  (assertHasAttr "collectDeps deep: has dep_a" deepChainResult "dep_a")
  (assertHasAttr "collectDeps deep: has dep_b" deepChainResult "dep_b")
  (assertHasAttr "collectDeps deep: has dep_c" deepChainResult "dep_c")
  (assertHasAttr "collectDeps deep: has dep_d" deepChainResult "dep_d")
  (assertEq "collectDeps deep: exactly 4 keys"
    (builtins.length (builtins.attrNames deepChainResult)) 4)
]
