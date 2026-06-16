# Tests for parseMetadata.nix
{ assertEq, assertBool, assertHasAttr, assertThrows, parseMetadata }:

let
  parse = parseMetadata.parseModuleConfig;

  # ---------------------------------------------------------------------------
  # Minimal valid config (only required field: name)
  # ---------------------------------------------------------------------------
  minimal = parse ''{ "name": "test_module" }'';

  # ---------------------------------------------------------------------------
  # Fully populated config
  # ---------------------------------------------------------------------------
  full = parse (builtins.toJSON {
    name = "full_module";
    version = "2.3.4";
    type = "ui";
    category = "networking";
    description = "A full module";
    main = "full_module_plugin";
    icon = "icon.png";
    dependencies = [ "dep_a" "dep_b" ];
    include = [ "extra.so" ];
    nix = {
      packages = {
        build = [ "pkg-config" ];
        runtime = [ "nlohmann_json" "openssl" ];
      };
      external_libraries = [
        { name = "mylib"; vendor_path = "lib"; }
      ];
      cmake = {
        find_packages = [ "Threads" "OpenSSL" ];
        extra_sources = [ "extra/helper.cpp" ];
        extra_include_dirs = [ "lib" "extra" ];
        extra_link_libraries = [ "pthread" ];
      };
    };
  });

  # ---------------------------------------------------------------------------
  # Config with no nix section
  # ---------------------------------------------------------------------------
  noNix = parse ''{ "name": "bare", "version": "0.1.0" }'';

  # ---------------------------------------------------------------------------
  # Partial nix section (only packages, no cmake) — shared binding
  # ---------------------------------------------------------------------------
  partialNix = parse ''{ "name": "x", "nix": { "packages": { "runtime": ["foo"] } } }'';

  # ---------------------------------------------------------------------------
  # Rust crate build deps (nix.rust block)
  # ---------------------------------------------------------------------------
  rustNative = parse (builtins.toJSON {
    name = "rust_native_module";
    codegen = { rust = { crate = "rust-lib"; }; };
    nix = {
      rust = {
        packages = { build = [ "pkg-config" ]; runtime = [ "openssl" ]; };
        env = { OPENSSL_NO_VENDOR = "1"; };
      };
    };
  });

in [
  # --- Minimal config: defaults ---
  (assertEq "minimal.name" minimal.name "test_module")
  (assertEq "minimal.version defaults to 1.0.0" minimal.version "1.0.0")
  (assertEq "minimal.type defaults to core" minimal.type "core")
  (assertEq "minimal.category defaults to general" minimal.category "general")
  (assertEq "minimal.description defaults" minimal.description "A Logos module")
  (assertEq "minimal.main defaults to null" minimal.main null)
  (assertEq "minimal.icon defaults to null" minimal.icon null)
  (assertEq "minimal.dependencies defaults to empty" minimal.dependencies [])
  (assertEq "minimal.include defaults to empty" minimal.include [])

  # --- Minimal config: nix defaults ---
  (assertEq "minimal.nix_packages.build defaults to empty" minimal.nix_packages.build [])
  (assertEq "minimal.nix_packages.runtime defaults to empty" minimal.nix_packages.runtime [])
  (assertEq "minimal.external_libraries defaults to empty" minimal.external_libraries [])
  (assertEq "minimal.cmake.find_packages defaults to empty" minimal.cmake.find_packages [])
  (assertEq "minimal.cmake.extra_sources defaults to empty" minimal.cmake.extra_sources [])
  (assertEq "minimal.cmake.extra_include_dirs defaults to empty" minimal.cmake.extra_include_dirs [])
  (assertEq "minimal.cmake.extra_link_libraries defaults to empty" minimal.cmake.extra_link_libraries [])
  (assertEq "minimal.interface defaults to legacy" minimal.interface "legacy")
  (assertEq "minimal.go_static_lib_names defaults to empty" minimal.go_static_lib_names [])

  # --- nix.rust defaults (empty for non-Rust / no native deps) ---
  (assertEq "minimal.nix_rust.packages.build defaults to empty" minimal.nix_rust.packages.build [])
  (assertEq "minimal.nix_rust.packages.runtime defaults to empty" minimal.nix_rust.packages.runtime [])
  (assertEq "minimal.nix_rust.env defaults to empty" minimal.nix_rust.env {})
  (assertEq "partialNix.nix_rust.packages.build defaults to empty" partialNix.nix_rust.packages.build [])
  (assertEq "partialNix.nix_rust.env defaults to empty" partialNix.nix_rust.env {})

  # --- nix.rust populated ---
  (assertEq "rustNative.nix_rust.packages.build" rustNative.nix_rust.packages.build [ "pkg-config" ])
  (assertEq "rustNative.nix_rust.packages.runtime" rustNative.nix_rust.packages.runtime [ "openssl" ])
  (assertEq "rustNative.nix_rust.env" rustNative.nix_rust.env { OPENSSL_NO_VENDOR = "1"; })

  # --- Minimal config: _raw preserved ---
  (assertHasAttr "minimal._raw has name" minimal._raw "name")

  # --- Full config: all values ---
  (assertEq "full.name" full.name "full_module")
  (assertEq "full.version" full.version "2.3.4")
  (assertEq "full.type" full.type "ui")
  (assertEq "full.category" full.category "networking")
  (assertEq "full.description" full.description "A full module")
  (assertEq "full.main" full.main "full_module_plugin")
  (assertEq "full.icon" full.icon "icon.png")
  (assertEq "full.dependencies" full.dependencies [ "dep_a" "dep_b" ])
  (assertEq "full.include" full.include [ "extra.so" ])
  (assertEq "full.nix_packages.build" full.nix_packages.build [ "pkg-config" ])
  (assertEq "full.nix_packages.runtime" full.nix_packages.runtime [ "nlohmann_json" "openssl" ])
  (assertEq "full.external_libraries count" (builtins.length full.external_libraries) 1)
  (assertEq "full.cmake.find_packages" full.cmake.find_packages [ "Threads" "OpenSSL" ])
  (assertEq "full.cmake.extra_sources" full.cmake.extra_sources [ "extra/helper.cpp" ])
  (assertEq "full.cmake.extra_include_dirs" full.cmake.extra_include_dirs [ "lib" "extra" ])
  (assertEq "full.cmake.extra_link_libraries" full.cmake.extra_link_libraries [ "pthread" ])

  # --- No nix section: everything defaults ---
  (assertEq "noNix.name" noNix.name "bare")
  (assertEq "noNix.version" noNix.version "0.1.0")
  (assertEq "noNix.nix_packages.build" noNix.nix_packages.build [])
  (assertEq "noNix.nix_packages.runtime" noNix.nix_packages.runtime [])
  (assertEq "noNix.external_libraries" noNix.external_libraries [])
  (assertEq "noNix.cmake.find_packages" noNix.cmake.find_packages [])

  # --- Missing name throws ---
  (assertThrows "missing name throws" (parse ''{ "version": "1.0.0" }''))

  # --- safeList: non-list dependencies coerced to empty ---
  (assertEq "string dependencies coerced to []"
    (parse ''{ "name": "x", "dependencies": "not_a_list" }'').dependencies
    [])

  # --- safeList: non-list include coerced to empty ---
  (assertEq "string include coerced to []"
    (parse ''{ "name": "x", "include": "not_a_list" }'').include
    [])

  # --- Extra unknown fields are preserved in _raw ---
  (assertHasAttr "extra fields in _raw"
    (parse ''{ "name": "x", "custom_field": 42 }'')._raw
    "custom_field")

  # --- Empty dependencies list ---
  (assertEq "explicit empty dependencies"
    (parse ''{ "name": "x", "dependencies": [] }'').dependencies
    [])

  # --- Partial nix section (only packages, no cmake) ---
  (assertEq "partial nix: runtime populated" partialNix.nix_packages.runtime [ "foo" ])
  (assertEq "partial nix: build defaults to empty" partialNix.nix_packages.build [])
  (assertEq "partial nix: cmake defaults" partialNix.cmake.find_packages [])

  # --- Type variations ---
  (assertEq "type core" (parse ''{ "name": "x", "type": "core" }'').type "core")
  (assertEq "type ui" (parse ''{ "name": "x", "type": "ui" }'').type "ui")
  (assertEq "type ui_qml" (parse ''{ "name": "x", "type": "ui_qml" }'').type "ui_qml")

  # --- Additional edge cases ---
  (assertEq "name with numbers"
    (parse ''{ "name": "module_v2" }'').name "module_v2")
  (assertEq "version with pre-release suffix"
    (parse ''{ "name": "x", "version": "1.0.0-beta.1" }'').version "1.0.0-beta.1")
  (assertEq "explicit null icon"
    (parse ''{ "name": "x", "icon": null }'').icon null)
  (assertEq "explicit null main"
    (parse ''{ "name": "x", "main": null }'').main null)
  # --- view field ---
  (assertEq "view defaults to null"
    (parse ''{ "name": "x" }'').view null)
  (assertEq "view parsed when set"
    (parse ''{ "name": "x", "view": "qml/Main.qml" }'').view "qml/Main.qml")
  (assertEq "view at root level"
    (parse ''{ "name": "x", "view": "Main.qml" }'').view "Main.qml")

  # --- ui_qml strict contract: view required, main optional ---
  (assertEq "ui_qml with view only"
    (let m = parse ''{ "name": "x", "type": "ui_qml", "view": "Main.qml" }'';
     in { t = m.type; v = m.view; mn = m.main; })
    { t = "ui_qml"; v = "Main.qml"; mn = null; })
  (assertEq "ui_qml with view and main"
    (let m = parse ''{ "name": "x", "type": "ui_qml", "view": "qml/Main.qml", "main": "my_plugin" }'';
     in { t = m.type; v = m.view; mn = m.main; })
    { t = "ui_qml"; v = "qml/Main.qml"; mn = "my_plugin"; })

  # go_build and build_command in external_libraries (universal/accounts-module pattern)
  (let
    universal = parse (builtins.toJSON {
      name = "x";
      nix.external_libraries = [{
        name = "golib";
        build_command = "make static-library";
        go_build = true;
        output_pattern = "build/libgolib.*";
      }];
    });
  in assertEq "universal extlib preserved"
    (builtins.head universal.external_libraries).name "golib")

  (let
    iface = parse ''{ "name": "m", "interface": "universal", "codegen": { "impl_class": "X" } }'';
  in assertBool "interface universal"
    (iface.interface == "universal" && iface.codegen.impl_class == "X"))

  (let
    goNames = parse (builtins.toJSON {
      name = "z";
      nix.external_libraries = [
        { name = "plain"; }
        { name = "go1"; go_build = true; }
      ];
    });
  in assertEq "go_static_lib_names picks go_build entries" goNames.go_static_lib_names [ "go1" ])

  # --- dependencies: object entries normalized to name strings ---
  (assertEq "dependency object/string entries normalized to names"
    (parse (builtins.toJSON {
      name = "x";
      dependencies = [ "a" { name = "b"; } { name = "c"; } ];
    })).dependencies
    [ "a" "b" "c" ])

  # --- dependency_overrides: defaults to empty attrset ---
  (assertEq "dependency_overrides defaults to {}"
    (parse ''{ "name": "x" }'').dependency_overrides {})

  # --- dependency_overrides: .lidl entry (no impl_class needed) ---
  (assertEq "dependency_overrides .lidl entry parsed"
    (parse (builtins.toJSON {
      name = "x";
      dependency_overrides = { dep_a = { file = "iface/dep_a.lidl"; }; };
    })).dependency_overrides
    { dep_a = { file = "iface/dep_a.lidl"; input = null; impl_class = null; }; })

  # --- dependency_overrides: .h entry with impl_class + input ---
  (assertEq "dependency_overrides .h entry parsed"
    (parse (builtins.toJSON {
      name = "x";
      dependency_overrides = {
        dep_b = { file = "src/dep_b_impl.h"; impl_class = "DepBImpl"; input = "dep_b_src"; };
      };
    })).dependency_overrides
    { dep_b = { file = "src/dep_b_impl.h"; impl_class = "DepBImpl"; input = "dep_b_src"; }; })

  # --- dependency_overrides: .h without impl_class throws ---
  (assertThrows "dependency_overrides .h without impl_class throws"
    (parse (builtins.toJSON {
      name = "x";
      dependency_overrides = { d = { file = "d.h"; }; };
    })))

  # --- dependency_overrides: entry without file throws ---
  (assertThrows "dependency_overrides without file throws"
    (parse (builtins.toJSON {
      name = "x";
      dependency_overrides = { d = { input = "z"; }; };
    })))
]
