# Tests for parseMetadata.nix
{ lib, assertEq, assertBool, assertHasAttr, assertThrows, parseMetadata }:

let
  # A fixed platform, so every existing assertion below reads exactly as it did
  # when parseModuleConfig took the JSON alone. Overlay-specific cases build
  # their own platforms; see the `platforms` section (and tests/test-platform-
  # triples.nix, which pins these three values to the real package set).
  linuxX86 = { os = "linux"; architecture = "x86_64"; abi = "gnu"; };
  parse = json: parseMetadata.parseModuleConfig { inherit json; platform = linuxX86; };

  # ---------------------------------------------------------------------------
  # Platform-overlay helpers
  # ---------------------------------------------------------------------------
  # `at` parses a module for one nix system, going through platformForSystem so
  # the tests use the SAME triple constructor the builders do — a hand-rolled
  # { os = "win"; } would validate against nothing and quietly assert nothing.
  pf = parseMetadata.platformForSystem;
  at = system: attrs:
    parseMetadata.parseModuleConfig {
      platform = pf system;
      json = builtins.toJSON ({ name = "m"; } // attrs);
    };
  # Same, with no target at all — the shape a builder uses above forAllSystems.
  atNone = attrs:
    parseMetadata.parseModuleConfig {
      platform = null;
      json = builtins.toJSON ({ name = "m"; } // attrs);
    };

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

  # ---------------------------------------------------------------------------
  # host_services — the privileged, closed-set declaration
  # ---------------------------------------------------------------------------
  noServices    = parse ''{ "name": "plain_module" }'';
  trustRoot     = parse (builtins.toJSON {
    name = "capability_module"; host_services = [ "token_registry" "token_delivery" ];
  });

in [
  # --- Minimal config: defaults ---
  # --- host_services ---
  (assertEq "host_services defaults to empty" noServices.host_services [])
  # `dynamic_calls` was a listed service and is now refused like any other
  # unknown name. It never gated anything — the by-name path is ungated at every
  # layer — while lp_grant_host_services rejects an unrecognised entry WHOLESALE
  # (logos_protocol.cpp:695-702), so declaring it cost a module the grants that
  # did work. Refusing it at build time is the point of removing it.
  (assertThrows "dynamic_calls is no longer a host service"
    (parse (builtins.toJSON { name = "webview_app"; host_services = [ "dynamic_calls" ]; })))
  (assertEq "the trust root may hold both trust-root services"
    trustRoot.host_services [ "token_registry" "token_delivery" ])

  # An unknown name is refused OUTRIGHT rather than filtered out: a module
  # asking for a privilege that does not exist is mistaken about what it is
  # running with, and silently dropping the entry hides that.
  (assertThrows "an unknown host service is refused"
    (parse (builtins.toJSON { name = "x"; host_services = [ "root_access" ]; })))
  (assertThrows "a non-string host service is refused"
    (parse (builtins.toJSON { name = "x"; host_services = [ 42 ]; })))

  # The one that actually guards anything: a module that is NOT the trust root
  # must not be able to grant itself the trust-root services by editing its own
  # metadata.json.
  (assertThrows "a non-privileged module cannot ask for token_registry"
    (parse (builtins.toJSON { name = "sneaky_module"; host_services = [ "token_registry" ]; })))
  (assertThrows "a non-privileged module cannot ask for token_delivery"
    (parse (builtins.toJSON { name = "sneaky_module"; host_services = [ "token_delivery" ]; })))
  # Every remaining service is trust-root, so there is no longer a
  # "permitted for anyone" name to mix in — the old form of this test used
  # dynamic_calls, which would now throw for being unknown rather than for
  # failing the allowlist, i.e. pass for the wrong reason. What is still worth
  # pinning is that asking for BOTH does not slip past.
  (assertThrows "a non-privileged module cannot ask for both trust-root services"
    (parse (builtins.toJSON {
      name = "sneaky_module"; host_services = [ "token_registry" "token_delivery" ];
    })))

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
    (iface.interface == "universal" && iface.codegen.impl_class == "X") true)

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

  # ---------------------------------------------------------------------------
  # Platform-keyed metadata: `platforms` overlays
  # ---------------------------------------------------------------------------
  # The selector is a triple whose three components are independently optional,
  # and the list is ORDERED because a map could not express "general first,
  # specific last". Every rule here is written to make an authoring mistake a
  # throw rather than an overlay that quietly never fires: a superset nobody
  # validates is how the .so/.dylib/.dll `include` lists drifted, and how
  # logos-package-downloader-module ended up without its .dll.

  # --- no platforms at all: byte-identical answer on every target ---
  # The regression that matters most. Roughly every module in the tree has no
  # `platforms` block, so if resolution changed ANY of them the change is wrong.
  # (`_platform` is the one attr that must differ — it records WHICH answer this
  # config is, so a caller can assert what it is holding.)
  (assertEq "no platforms: same config on linux and the mingw cross"
    (removeAttrs (at "x86_64-linux"  { include = [ "a.so" ]; nix.packages.runtime = [ "zstd" ]; }) [ "_platform" ])
    (removeAttrs (at "x86_64-windows" { include = [ "a.so" ]; nix.packages.runtime = [ "zstd" ]; }) [ "_platform" ]))

  # --- os-only selector: matches every arch on that OS ---
  (assertEq "os-only overlay applies on the matching OS"
    (at "x86_64-linux" {
      include = [ "libcore.so" ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    }).include
    [ "libcore.so" "extra.so" ])

  (assertEq "os-only overlay applies on the other arch of the same OS"
    (at "aarch64-linux" {
      include = [ "libcore.so" ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    }).include
    [ "libcore.so" "extra.so" ])

  # --- os-only selector: non-match leaves the base untouched ---
  (assertEq "os-only overlay does not apply on another OS"
    (at "aarch64-darwin" {
      include = [ "libcore.so" ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    }).include
    [ "libcore.so" ])

  # --- architecture-only selector, written with the alias an author reaches for ---
  # nixpkgs spells it `aarch64`; every LGX variant name and every Apple document
  # spells it `arm64`. Both are canonicalised through lib.systems.parse.cpuTypes,
  # so "arm64" matches rather than silently never firing.
  (assertEq "architecture-only overlay: arm64 canonicalises to aarch64 (darwin)"
    (at "aarch64-darwin" {
      include = [ ];
      platforms = [ { when.architecture = "arm64"; include = [ "atomic-shim" ]; } ];
    }).include
    [ "atomic-shim" ])

  (assertEq "architecture-only overlay crosses OS boundaries (linux aarch64 too)"
    (at "aarch64-linux" {
      include = [ ];
      platforms = [ { when.architecture = "arm64"; include = [ "atomic-shim" ]; } ];
    }).include
    [ "atomic-shim" ])

  (assertEq "architecture-only overlay skips the other arch"
    (at "x86_64-linux" {
      include = [ ];
      platforms = [ { when.architecture = "aarch64"; include = [ "atomic-shim" ]; } ];
    }).include
    [ ])

  # --- full triple ---
  # This is the headline selector, and it is only correct because the Windows
  # target's abi really is `gnu` (x86_64-w64-mingw32). `lib.systems.elaborate
  # "x86_64-windows"` says `msvc`, so a resolver that took the shortcut of
  # elaborating the system string would make this exact entry match nothing on
  # the one platform the workspace cross-builds for.
  (assertEq "full triple matches the mingw cross"
    (at "x86_64-windows" {
      platforms = [ { when = { os = "windows"; architecture = "x86_64"; abi = "gnu"; };
                      include = [ "extra.dll" ]; } ];
    }).include
    [ "extra.dll" ])

  (assertEq "full triple does not match a different OS"
    (at "x86_64-linux" {
      platforms = [ { when = { os = "windows"; architecture = "x86_64"; abi = "gnu"; };
                      include = [ "extra.dll" ]; } ];
    }).include
    [ ])

  # --- abi alone is legal, and matches MORE than it looks like it does ---
  # Pinned rather than left to folklore: `gnu` is the abi of x86_64-linux,
  # aarch64-linux AND the mingw cross, so a lone {"abi":"gnu"} spans two
  # operating systems. It is not a mingw discriminator and will not become one
  # until a musl or msvc target exists.
  (assertEq "abi-only overlay applies on linux"
    (at "x86_64-linux" { platforms = [ { when.abi = "gnu"; include = [ "g" ]; } ]; }).include
    [ "g" ])
  (assertEq "abi-only overlay ALSO applies on the windows cross"
    (at "x86_64-windows" { platforms = [ { when.abi = "gnu"; include = [ "g" ]; } ]; }).include
    [ "g" ])
  (assertEq "abi-only overlay skips darwin, whose abi is \"unknown\""
    (at "aarch64-darwin" { platforms = [ { when.abi = "gnu"; include = [ "g" ]; } ]; }).include
    [ ])

  # --- several matching overlays apply, in DECLARATION order ---
  (assertEq "every matching overlay applies, concatenating in order"
    (at "x86_64-windows" {
      include = [ "base" ];
      platforms = [
        { when.abi = "gnu"; include = [ "from-abi" ]; }
        { when.os = "windows"; include = [ "from-os" ]; }
        { when = { os = "windows"; architecture = "x86_64"; abi = "gnu"; };
          include = [ "from-triple" ]; }
      ];
    }).include
    [ "base" "from-abi" "from-os" "from-triple" ])

  # --- scalars: LAST matching overlay wins ---
  # Written on `nix.rust.toolchain` rather than on `main`, and that is not an
  # arbitrary choice of example: `main` is REFUSED at the top level (see the
  # `topDeferred` cases below), so `nix.rust.toolchain` is the overlay-able
  # scalar. It is also a realistic one — a crate whose deps out-pace the pinned
  # rustc on one target only.
  (assertEq "scalar overwrite: specific entry declared last wins"
    (at "x86_64-windows" {
      nix = {
        rust.toolchain = "1.90.0";
        platforms = [
          { when.os = "windows"; rust.toolchain = "1.95.0"; }
          { when = { os = "windows"; architecture = "x86_64"; abi = "gnu"; };
            rust.toolchain = "1.96.0"; }
        ];
      };
    }).nix_rust.toolchain
    "1.96.0")

  # ...and the same two entries REVERSED give the other answer. Ordering is
  # declaration order, never specificity — the ordered list makes "general
  # first, specific last" expressible, not automatic. Anyone reading only the
  # case above would assume the resolver ranks selectors; it does not.
  (assertEq "scalar overwrite: reversing the declaration reverses the answer"
    (at "x86_64-windows" {
      nix = {
        rust.toolchain = "1.90.0";
        platforms = [
          { when = { os = "windows"; architecture = "x86_64"; abi = "gnu"; };
            rust.toolchain = "1.96.0"; }
          { when.os = "windows"; rust.toolchain = "1.95.0"; }
        ];
      };
    }).nix_rust.toolchain
    "1.95.0")

  # --- nested attrset: recursed key by key, siblings survive ---
  # The krb5 case, which is the reason this feature exists: krb5 is an
  # EVALUATION-time hard failure for a mingw host (its closure reaches bash,
  # whose meta.badPlatforms excludes a windows/pe host), so it cannot be
  # declared as part of a cross-platform superset the way `include` can.
  (assertEq "nix.packages.runtime concatenates and leaves .build alone"
    (at "x86_64-linux" {
      nix = {
        packages = { build = [ "pkg-config" ]; runtime = [ "nlohmann_json" ]; };
        platforms = [ { when.os = "linux"; packages.runtime = [ "krb5" ]; } ];
      };
    }).nix_packages
    { build = [ "pkg-config" ]; runtime = [ "nlohmann_json" "krb5" ]; })

  (assertEq "nix.packages.runtime is left alone on the non-matching target"
    (at "x86_64-windows" {
      nix = {
        packages = { build = [ "pkg-config" ]; runtime = [ "nlohmann_json" ]; };
        platforms = [ { when.os = "linux"; packages.runtime = [ "krb5" ]; } ];
      };
    }).nix_packages
    { build = [ "pkg-config" ]; runtime = [ "nlohmann_json" ]; })

  # A base-only key inside an overlaid attrset must survive: an overlay is a
  # MERGE, not a replacement. `nix.rust.env` is the realistic case (per-target
  # CFLAGS_* alongside a shared var).
  (assertEq "nested attrset merge keeps base-only keys"
    (at "x86_64-windows" {
      nix = {
        rust.env = { SHARED = "1"; };
        platforms = [ { when.os = "windows"; rust.env = { WINDOWS_ONLY = "2"; }; } ];
      };
    }).nix_rust.env
    { SHARED = "1"; WINDOWS_ONLY = "2"; })

  # ...and the recursion is not one level deep, which is the rule the spec sketch
  # got wrong. "Scalars and attrsets OVERWRITE" is the simpler rule and it is
  # the wrong one: every overlay-able key under `nix` IS an attrset, so
  # whole-object overwrite would replace `rust` wholesale here and take
  # `packages.build`, `env` and `toolchain` down with it — and "lists
  # concatenate" would become unreachable for the entire `nix` block, since no
  # list is ever a direct child of packages/cmake/rust. Recursion is what lets
  # the two rules compose: descend through the objects, apply the list/scalar
  # rule at the leaf where the author actually wrote a value.
  (assertEq "attrset merge recurses all the way down; siblings survive at every level"
    (at "x86_64-windows" {
      nix = {
        rust = {
          packages = { build = [ "pkg-config" ]; runtime = [ "openssl" ]; };
          env = { SHARED = "1"; };
          toolchain = "1.90.0";
        };
        platforms = [ { when.os = "windows"; rust.packages.runtime = [ "windows-sys" ]; } ];
      };
    }).nix_rust
    { packages = { build = [ "pkg-config" ]; runtime = [ "openssl" "windows-sys" ]; };
      env = { SHARED = "1"; };
      toolchain = "1.90.0"; })

  # --- an overlay under `nix` AND one at the top level, same module ---
  # The two lists have disjoint key sets (nothing may appear in both), so they
  # can never interact and need no ordering rule between them. Pinned so that
  # stays true.
  (assertEq "top-level and nix overlays both apply, independently"
    (let c = at "x86_64-windows" {
      include = [ "libcore.so" ];
      platforms = [ { when.os = "windows"; include = [ "libcore.dll" ]; } ];
      nix = {
        packages.runtime = [ "zstd" ];
        platforms = [ { when.os = "windows"; packages.runtime = [ "windows-only" ]; } ];
      };
    }; in { inherit (c) include; runtime = c.nix_packages.runtime; })
    { include = [ "libcore.so" "libcore.dll" ];
      runtime = [ "zstd" "windows-only" ]; })

  # --- an empty `when` is refused ---
  # An overlay that matches every platform IS the base config, so writing one
  # states the opposite of what it means. Every other way to get an accidental
  # match-everything (a misspelled key, a missing `when`) already throws;
  # allowing this one would be the single silent hole.
  (assertThrows "empty `when` is refused"
    (at "x86_64-linux" { platforms = [ { when = { }; include = [ "x" ]; } ]; }))

  (assertThrows "a missing `when` is refused rather than defaulting to match-all"
    (at "x86_64-linux" { platforms = [ { include = [ "x" ]; } ]; }))

  (assertThrows "an unknown key in `when` is refused"
    (at "x86_64-linux" { platforms = [ { when.platform = "linux"; include = [ "x" ]; } ]; }))

  # --- deny-listed fields ---
  # `host_services` is the sharp one: it is a SECURITY declaration checked
  # against a hardcoded allowlist, and a platform-varying privilege set would
  # mean auditing the Linux build tells you nothing about the Windows one.
  (assertThrows "a platform overlay may not set host_services"
    (at "x86_64-linux" {
      platforms = [ { when.os = "linux"; host_services = [ "token_registry" ]; } ];
    }))

  # `type` selects the BACKEND, and both builders read it above forAllSystems
  # where no target exists — there is no per-platform answer to give them.
  (assertThrows "a platform overlay may not set type"
    (at "x86_64-linux" { platforms = [ { when.os = "linux"; type = "ui"; } ]; }))

  # `interface` / `codegen` decide the generated contract, hence the interface
  # hash: a Linux consumer calling a Windows provider built from a different
  # contract is a mismatch at introspect time, not a build error.
  (assertThrows "a platform overlay may not set interface"
    (at "x86_64-linux" { platforms = [ { when.os = "linux"; interface = "cdylib"; } ]; }))

  # The two levels have DISJOINT allowlists, so a top-level key under `nix` is
  # refused too — that is what removes any ordering question between the lists.
  (assertThrows "a nix-level overlay may not set a top-level field"
    (at "x86_64-linux" { nix.platforms = [ { when.os = "linux"; include = [ "x" ]; } ]; }))

  (assertThrows "a top-level overlay may not set a nix-level field"
    (at "x86_64-linux" { platforms = [ { when.os = "linux"; packages.runtime = [ "x" ]; } ]; }))

  # --- `main` and `dependencies`: refused, and refused for a different reason ---
  #
  # Both used to be in `topAllowed`, and both were resolved for the BUILD and
  # not for the ARTIFACT. The shipped metadata.json is the SOURCE file copied
  # verbatim (mkLogosQmlModule.nix's `cp ${configFile} $out/lib/metadata.json`,
  # and the core path embeds the same file via configure_file), and the
  # LogosModules umbrella is generated at build time by logos-plugin-qt's
  # buildPlugin.nix out of that same raw `dependencies` array. So a core module
  # that platform-keyed `main` evaluated GREEN with no diagnostic anywhere —
  # mkLogosModule never reads `config.main`, so the platform-null poison that is
  # supposed to catch this only ever fired on the ui_qml path — and shipped a
  # manifest naming a plugin that does not exist on the non-base targets.
  (assertThrows "a platform overlay may not set `main` (yet)"
    (at "x86_64-linux" { platforms = [ { when.os = "linux"; main = "linux_plugin"; } ]; }))

  (assertThrows "a platform overlay may not set `dependencies` (yet)"
    (at "x86_64-linux" {
      platforms = [ { when.os = "linux"; dependencies = [ "waku_module" ]; } ];
    }))

  # ...and on every target, not only the one the selector names. A refusal that
  # depended on which machine ran the parse would be the same content-conditional
  # guarantee the whole design is written against.
  (assertThrows "a platform-keyed `main` is refused on targets it does not match either"
    (at "aarch64-darwin" { platforms = [ { when.os = "windows"; main = "win_plugin"; } ]; }))

  (assertThrows "a platform-keyed `main` is refused with no target at all"
    (atNone { platforms = [ { when.os = "windows"; main = "win_plugin"; } ]; }).name)

  # The allowlist itself, pinned. Widening it back is then a deliberate edit in
  # two files rather than one word added to a list.
  (assertEq "only `include` may vary at the top level"
    parseMetadata.overlayAllowed.top [ "include" ])

  (assertEq "the nix-level allowlist is unchanged"
    parseMetadata.overlayAllowed.nix [ "packages" "external_libraries" "cmake" "rust" ])

  # A throw message is not something a pure-Nix test can read, so the refusal
  # texts are exported as data and asserted here. The point is not that the two
  # keys are refused — the cases above cover that — but that the refusal still
  # EXPLAINS itself: an author who hits it needs to know it is "not yet" rather
  # than "never", and the next person to re-admit the key needs to know exactly
  # what has to land first.
  (assertEq "the deferred top-level fields are exactly `main` and `dependencies`"
    (builtins.attrNames parseMetadata.overlayDeferredTop) [ "dependencies" "main" ])

  (assertBool "the `main` refusal names the read that is missing"
    (lib.hasInfix "config.main" parseMetadata.overlayDeferredTop.main
     && lib.hasInfix "verbatim" parseMetadata.overlayDeferredTop.main)
    true)

  (assertBool "the `dependencies` refusal names the umbrella generator"
    (lib.hasInfix "buildPlugin.nix" parseMetadata.overlayDeferredTop.dependencies)
    true)

  (assertBool "the precondition names both halves of the plumbing that must land"
    (lib.hasInfix "modulePreConfigure.nix" parseMetadata.overlayDeferredPrecondition
     && lib.hasInfix "del(.platforms)" parseMetadata.overlayDeferredPrecondition
     && lib.hasInfix "mkLogosQmlModule.nix" parseMetadata.overlayDeferredPrecondition)
    true)

  # --- a `platforms` key somewhere overlays are never read from ---
  #
  # Resolution looks at exactly two paths, so `nix.packages.platforms` — which
  # is the shape an author reaches for, because they are thinking "this block
  # varies by platform" and put the list next to the block — was read by
  # nothing. The base shipped to every target and the module evaluated green.
  #
  # Note what each of these modules has in common: NO legal `platforms` key. So
  # every one of them takes resolvePlatforms' early return, which is why the
  # sweep has to run on that path — the modules that can make this mistake are
  # exactly the modules that never reach the overlay machinery. Each case reads
  # `.name`, a field that is never platform-keyed, so nothing but the sweep
  # itself can be doing the throwing.
  (assertThrows "a `platforms` list under nix.packages is refused, not ignored"
    (at "x86_64-linux" {
      nix.packages.platforms = [ { when.os = "linux"; runtime = [ "krb5" ]; } ];
    }).name)

  (assertThrows "a `platforms` list under nix.rust is refused, not ignored"
    (at "x86_64-linux" {
      nix.rust.platforms = [ { when.os = "windows"; env = { WIN = "1"; }; } ];
    }).name)

  (assertThrows "a `platforms` list under nix.cmake is refused, not ignored"
    (at "x86_64-linux" {
      nix.cmake.platforms = [ { when.os = "linux"; extra_link_libraries = [ "dl" ]; } ];
    }).name)

  # The sweep descends into LISTS as well as objects: `nix.external_libraries`
  # is a list of objects, and "put the platforms list inside the library entry
  # it varies" is the same mistake one level down.
  (assertThrows "a `platforms` key inside an external_libraries entry is refused"
    (at "x86_64-linux" {
      nix.external_libraries = [
        { name = "foo"; platforms = [ { when.os = "linux"; vendor_path = "v"; } ]; }
      ];
    }).name)

  (assertThrows "a `platforms` key under codegen is refused"
    (at "x86_64-linux" { codegen.platforms = [ { when.os = "linux"; impl_class = "X"; } ]; }).name)

  # ...and it is refused when a LEGAL overlay list is present too, so a module
  # that got one of the two right does not get the other silently dropped.
  (assertThrows "a misplaced `platforms` is refused even beside a legal one"
    (at "x86_64-linux" {
      nix = {
        packages = { runtime = [ "zstd" ]; platforms = [ { when.os = "linux"; } ]; };
        platforms = [ { when.os = "linux"; packages.runtime = [ "krb5" ]; } ];
      };
    }).nix_packages)

  # A `platforms` nested inside an overlay BODY is refused too — that one was
  # already caught by the body allowlist, and this pins that it stays caught.
  (assertThrows "a `platforms` key inside an overlay body is refused"
    (at "x86_64-linux" { platforms = [ { when.os = "linux"; platforms = [ ]; } ]; }))

  # The negative: the two legal paths must NOT be swept up by the check that
  # exists to protect them. (Every overlay case above this line is really the
  # same assertion; this one states it directly.)
  (assertEq "the two legal `platforms` paths still resolve"
    (let c = at "x86_64-linux" {
      include = [ ];
      platforms = [ { when.os = "linux"; include = [ "a.so" ]; } ];
      nix = {
        packages.runtime = [ ];
        platforms = [ { when.os = "linux"; packages.runtime = [ "krb5" ]; } ];
      };
    }; in { inherit (c) include; runtime = c.nix_packages.runtime; })
    { include = [ "a.so" ]; runtime = [ "krb5" ]; })

  # --- R2: a platform-keyed field parsed with NO platform must not answer ---
  # This is the failure mode the whole design turns on. Returning the base value
  # here would be indistinguishable from a correct answer at every call site,
  # and would reintroduce exactly the hand-written superset the feature removes.
  (assertThrows "reading a platform-keyed field with platform = null throws"
    (atNone {
      include = [ "libcore.so" ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    }).include)

  (assertThrows "reading a platform-keyed nix field with platform = null throws"
    (atNone {
      nix = {
        packages.runtime = [ "zstd" ];
        platforms = [ { when.os = "linux"; packages.runtime = [ "krb5" ]; } ];
      };
    }).nix_packages)

  # ...but the refusal is FIELD-SCOPED, and that is deliberate. Both builders
  # need `name` and `type` above forAllSystems to pick a backend and to publish
  # a system-agnostic `config` output; failing the whole parse would take those
  # down with it and make the feature unusable for the module that adopts it.
  (assertEq "a platform-null parse still answers for fields no overlay may vary"
    (atNone {
      type = "ui";
      include = [ "libcore.so" ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    }).type
    "ui")

  # A module with no overlays is unaffected by a platform-null parse — this is
  # what keeps every existing call site working.
  (assertEq "a platform-null parse is unchanged for a module with no overlays"
    (atNone { include = [ "libcore.so" ]; }).include
    [ "libcore.so" ])

  # --- R3: an unrecognised selector value must throw, not never-match ---
  # A silently-skipped overlay is indistinguishable from a correct one at eval
  # time and shows up as a missing file at load time on the machine with the
  # least tooling. Both validation stages are exercised: "amd64" is absent from
  # the nixpkgs table entirely, while "freebsd" and "musl" canonicalise fine and
  # are caught only by the reachability check.
  (assertThrows "an unrecognised architecture spelling throws"
    (at "x86_64-linux" { platforms = [ { when.architecture = "amd64"; include = [ "x" ]; } ]; }))

  (assertThrows "an unrecognised os spelling throws"
    (at "x86_64-linux" { platforms = [ { when.os = "win"; include = [ "x" ]; } ]; }))

  (assertThrows "a valid-but-unreachable os throws (no Logos target has it)"
    (at "x86_64-linux" { platforms = [ { when.os = "freebsd"; include = [ "x" ]; } ]; }))

  (assertThrows "a valid-but-unreachable abi throws"
    (at "x86_64-linux" { platforms = [ { when.abi = "musl"; include = [ "x" ]; } ]; }))

  # The non-short-circuit rule. With an `&&` chain this case validates CLEAN on
  # Linux: the os mismatch decides the answer before "amd64" is ever forced, so
  # the typo ships and only throws on macOS — a green Linux CI run proving
  # nothing, which is how most Windows defects in this workspace reached a tag.
  (assertThrows "a typo in a NON-matching overlay still throws"
    (at "x86_64-linux" {
      platforms = [ { when = { os = "darwin"; architecture = "amd64"; }; include = [ "x" ]; } ];
    }))

  # ...and it throws even when nothing ever reads the field the overlay sets.
  # Resolution is forced eagerly: metadata.json is a few KB of plain JSON, so
  # checking it whole is free, and left lazy a bad selector under `nix.platforms`
  # stays silent on every build that happens not to read `nix.packages`.
  (assertThrows "a bad selector throws even if only `name` is read"
    (at "x86_64-linux" {
      nix.platforms = [ { when.os = "freebsd"; packages.runtime = [ "x" ]; } ];
    }).name)

  # --- shape errors in the overlay body ---
  (assertThrows "a type mismatch between base and overlay throws"
    (at "x86_64-linux" {
      include = [ "a" ];
      platforms = [ { when.os = "linux"; include = "b"; } ];
    }))

  # There is no removal operator in v1: null over a scalar is a blanking
  # operator and null over a list is removal, and both need a rule for what
  # happens when two overlays disagree. Refused rather than guessed.
  (assertThrows "null in an overlay is refused (no removal operator in v1)"
    (at "x86_64-linux" {
      include = [ "a" ];
      platforms = [ { when.os = "linux"; include = null; } ];
    }))

  # An explicit null in the BASE is "unset", not a type — `"toolchain": null`
  # means "the pinned nixpkgs rustc" — so an overlay must be able to fill it.
  # Null is asymmetric on purpose (unset-then-set yes, set-then-unset no).
  (assertEq "an overlay may fill a base field that is explicitly null"
    (at "x86_64-windows" {
      nix = {
        rust.toolchain = null;
        platforms = [ { when.os = "windows"; rust.toolchain = "1.96.0"; } ];
      };
    }).nix_rust.toolchain
    "1.96.0")

  # `platforms` is a LIST, not an object keyed by selector — the ordering above
  # is exactly what an object could not express.
  (assertThrows "an object-shaped `platforms` is refused"
    (at "x86_64-linux" { platforms = { linux.include = [ "x" ]; }; }))

  # --- external_libraries is a list of OBJECTS folded by name ---
  # lib.listToAttrs keeps the FIRST entry on a duplicate key, so a naive
  # concatenation would let the BASE entry win over the overlay meant to refine
  # it — the exact inverse of "specific last", with nothing raised. Refused.
  (assertThrows "overlays leaving a duplicate external_libraries name are refused"
    (at "x86_64-linux" {
      nix = {
        external_libraries = [ { name = "foo"; vendor_path = "vendor/foo"; } ];
        platforms = [ { when.os = "linux";
                        external_libraries = [ { name = "foo"; vendor_path = "vendor/foo-linux"; } ]; } ];
      };
    }))

  # A distinct name is fine, and go_static_lib_names must be derived from the
  # RESOLVED list — otherwise a platform-only Go archive silently loses its
  # whole-archive link flags.
  (assertEq "go_static_lib_names is derived from the resolved external_libraries"
    (at "x86_64-linux" {
      nix = {
        external_libraries = [ { name = "base_lib"; go_build = true; } ];
        platforms = [ { when.os = "linux";
                        external_libraries = [ { name = "linux_lib"; go_build = true; } ]; } ];
      };
    }).go_static_lib_names
    [ "base_lib" "linux_lib" ])

  # --- _raw is the RESOLVED tree, with `platforms` gone ---
  # A consumer reading `_raw.include` off the pre-resolution tree would get the
  # unresolved superset: the same silent wrong answer, one layer down. And
  # nothing should be able to re-read the unresolved overlay list.
  (assertEq "_raw carries the resolved value"
    (at "x86_64-linux" {
      include = [ "libcore.so" ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    })._raw.include
    [ "libcore.so" "extra.so" ])

  (assertBool "_raw no longer carries the `platforms` key"
    ((at "x86_64-linux" {
      include = [ ];
      platforms = [ { when.os = "linux"; include = [ "extra.so" ]; } ];
    })._raw ? platforms)
    false)

  # --- the platform argument is validated the SAME way a selector is ---
  # Symmetric validation is what makes "a well-spelled selector always matches
  # its own platform" a property of the code rather than a hope, and it stops a
  # test from hand-rolling { os = "win"; } and quietly asserting nothing.
  (assertThrows "a misspelled platform triple is refused"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}'';
      platform = { os = "win"; architecture = "x86_64"; abi = "gnu"; };
    }))

  (assertThrows "a partial platform triple is refused"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}'';
      platform = { os = "linux"; };
    }))

  # ...and it is refused for a module with NO `platforms` block, which is every
  # module in the tree today. This is the one that matters, and the two cases
  # above do not cover it: they force the WHOLE config, so `_platform` (which
  # re-validates the argument) is what throws. Read one ordinary field instead
  # — `name`, which no overlay may vary — and the platform argument was only
  # ever forced by the overlay machinery, which a module with no overlays never
  # reaches. So an invalid `platform` was ACCEPTED IN SILENCE by every module in
  # the tree, and would have started throwing the day someone in a different
  # repo added an overlay months later: a guarantee conditional on module
  # CONTENT, which is exactly what parseMetadata.nix's header argues must not
  # exist. Each spelling below is its own case because each fails a different
  # branch of validatePlatform.
  (assertThrows "a bare system STRING as `platform` is refused (module has no overlays)"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}''; platform = "x86_64-linux";
    }).name)

  (assertThrows "a non-attrset `platform` is refused (module has no overlays)"
    (parseMetadata.parseModuleConfig { json = ''{"name":"m"}''; platform = true; }).name)

  (assertThrows "a PARTIAL platform triple is refused (module has no overlays)"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}''; platform = { os = "linux"; };
    }).name)

  (assertThrows "a platform triple with the WRONG KEYS is refused (module has no overlays)"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}''; platform = { os = "linux"; arch = "x86_64"; abi = "gnu"; };
    }).name)

  (assertThrows "a MISSPELLED platform triple is refused (module has no overlays)"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}''; platform = { os = "win"; architecture = "x86_64"; abi = "gnu"; };
    }).name)

  (assertThrows "an UNREACHABLE platform triple is refused (module has no overlays)"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}''; platform = { os = "freebsd"; architecture = "x86_64"; abi = "gnu"; };
    }).name)

  # The other half of the same rule: `platform = null` is the ONE non-triple
  # that is legal, and it must still return the tree untouched for a module with
  # no overlays. Forcing the argument on every path must not turn "no target
  # known" into an error.
  (assertEq "`platform = null` still parses a module with no overlays"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m","include":["a.so"]}''; platform = null;
    }).include
    [ "a.so" ])

  (assertThrows "an unknown system has no platform triple"
    (parseMetadata.platformForSystem "riscv64-linux"))

  # --- the signature itself ---
  # A caller that omits the platform must fail at the CALL, before any module
  # content is read. Anything conditional on module content — "throw only if
  # the JSON declares platforms" — is a guarantee that holds until someone in
  # another repo adds an overlay months later.
  (assertThrows "omitting `platform` is an error even for a module with no overlays"
    (parseMetadata.parseModuleConfig { json = ''{"name":"m"}''; }))

  (assertThrows "the old positional (JSON-string) form is refused with a migration message"
    (parseMetadata.parseModuleConfig ''{"name":"m"}''))

  (assertThrows "an unexpected argument is refused"
    (parseMetadata.parseModuleConfig {
      json = ''{"name":"m"}''; platform = null; jsonContent = "oops";
    }))

  # --- _platform records which answer this config is ---
  (assertEq "_platform is the resolved triple"
    (at "x86_64-windows" { })._platform
    { os = "windows"; architecture = "x86_64"; abi = "gnu"; })
]
