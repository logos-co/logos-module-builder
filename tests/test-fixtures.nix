# Fixture-based metadata tests
# Reads real metadata.json files from tests/fixtures/ and verifies parsing.
# These catch issues that inline JSON strings miss: whitespace, encoding, field ordering.
{ assertEq, assertBool, assertHasAttr, parseMetadata, fixturesRoot }:

let
  # A fixed platform for the fixtures that are not platform-keyed, so those
  # assertions read exactly as they did when parseModuleConfig took the JSON
  # alone. The overlay fixture below parses for several targets instead.
  linuxX86 = { os = "linux"; architecture = "x86_64"; abi = "gnu"; };
  parse = json: parseMetadata.parseModuleConfig { inherit json; platform = linuxX86; };
  parseAt = system: json: parseMetadata.parseModuleConfig {
    inherit json;
    platform = parseMetadata.platformForSystem system;
  };

  # Parse each fixture's metadata.json from disk
  coreMeta     = parse (builtins.readFile (fixturesRoot + "/core-module/metadata.json"));
  universalMeta = parse (builtins.readFile (fixturesRoot + "/core-universal-module/metadata.json"));
  uiMeta       = parse (builtins.readFile (fixturesRoot + "/ui-module/metadata.json"));
  qmlMeta      = parse (builtins.readFile (fixturesRoot + "/qml-module/metadata.json"));
  backendMeta  = parse (builtins.readFile (fixturesRoot + "/ui-qml-backend-module/metadata.json"));
  extlibMeta   = parse (builtins.readFile (fixturesRoot + "/extlib-module/metadata.json"));
  depsMeta     = parse (builtins.readFile (fixturesRoot + "/module-with-deps/metadata.json"));

  # Platform-keyed fixture, parsed once per target. On disk rather than inline
  # because that is this file's whole purpose: an overlay list survives a round
  # trip through real JSON — nested objects, key ordering, trailing whitespace —
  # only if it is read from a file the way a module's actually is.
  overlayJson = builtins.readFile (fixturesRoot + "/platform-overlay-module/metadata.json");
  overlayLinux   = parseAt "x86_64-linux"   overlayJson;
  overlayDarwin  = parseAt "aarch64-darwin" overlayJson;
  overlayWindows = parseAt "x86_64-windows" overlayJson;

in [
  # ---------------------------------------------------------------------------
  # Standard core module (mirrors minimal template)
  # ---------------------------------------------------------------------------
  (assertEq "fixture core: name" coreMeta.name "test_core_module")
  (assertEq "fixture core: type" coreMeta.type "core")
  (assertEq "fixture core: version" coreMeta.version "2.0.0")
  (assertEq "fixture core: category" coreMeta.category "network")
  (assertEq "fixture core: main" coreMeta.main "test_core_module_plugin")
  (assertEq "fixture core: dependencies" coreMeta.dependencies [])
  (assertEq "fixture core: build packages" coreMeta.nix_packages.build [ "pkg-config" ])
  (assertEq "fixture core: runtime packages" coreMeta.nix_packages.runtime [ "nlohmann_json" ])
  (assertEq "fixture core: cmake find_packages" coreMeta.cmake.find_packages [ "Threads" ])
  (assertEq "fixture core: cmake extra_link_libraries" coreMeta.cmake.extra_link_libraries [ "pthread" ])
  (assertEq "fixture core: no external libraries" coreMeta.external_libraries [])
  # Mirrors the minimal template, which is universal (see test-templates.nix).
  # No `type: core` module in the workspace is still legacy-authored.
  (assertEq "fixture core: universal authoring" coreMeta.interface "universal")

  # ---------------------------------------------------------------------------
  # Universal interface core module (mirrors logos-accounts-module)
  # ---------------------------------------------------------------------------
  (assertEq "fixture universal: name" universalMeta.name "test_universal_module")
  (assertEq "fixture universal: type" universalMeta.type "core")
  (assertEq "fixture universal: category" universalMeta.category "accounts")
  # The point of this fixture. It is named/described "universal" and mirrors
  # logos-accounts-module (interface: universal), but carried no `interface`
  # key at all and so parsed as "legacy" — the fixture did not test the thing
  # its name claims. Pin it so it cannot silently regress to legacy again.
  (assertEq "fixture universal: universal authoring" universalMeta.interface "universal")
  (assertBool "fixture universal: has external libraries"
    (builtins.length universalMeta.external_libraries > 0) true)
  (assertEq "fixture universal: extlib name"
    (builtins.head universalMeta.external_libraries).name "testgolib")
  (assertBool "fixture universal: extlib has go_build"
    (builtins.head universalMeta.external_libraries).go_build true)
  (assertEq "fixture universal: extlib build_command"
    (builtins.head universalMeta.external_libraries).build_command "make static-library")
  (assertEq "fixture universal: extlib output_pattern"
    (builtins.head universalMeta.external_libraries).output_pattern "build/libtestgolib.*")
  (assertEq "fixture universal: cmake extra_include_dirs"
    universalMeta.cmake.extra_include_dirs [ "lib" ])
  # capabilities preserved in _raw
  (assertHasAttr "fixture universal: _raw has capabilities" universalMeta._raw "capabilities")

  # ---------------------------------------------------------------------------
  # UI module (mirrors logos-package-manager-ui)
  # ---------------------------------------------------------------------------
  (assertEq "fixture ui: name" uiMeta.name "test_ui_module")
  (assertEq "fixture ui: type" uiMeta.type "ui")
  (assertEq "fixture ui: version" uiMeta.version "1.5.0")
  (assertEq "fixture ui: main" uiMeta.main "test_ui_module_plugin")
  (assertEq "fixture ui: icon" uiMeta.icon null)
  # Deliberately legacy: `type: ui` has no template and exactly one real
  # instance (logos-basecamp), which is legacy-authored. There is no defined
  # universal shape for `type: ui` — autoCodegen would route it down the plain
  # universal (core) path. This fixture is the only on-disk `type: ui` parse
  # subject; keep it legacy and pinned.
  (assertEq "fixture ui: legacy authoring" uiMeta.interface "legacy")

  # ---------------------------------------------------------------------------
  # QML module (used for integration build test)
  # ---------------------------------------------------------------------------
  (assertEq "fixture qml: name" qmlMeta.name "test_qml_module")
  (assertEq "fixture qml: type" qmlMeta.type "ui_qml")
  (assertEq "fixture qml: version" qmlMeta.version "0.1.0")
  (assertEq "fixture qml: view" qmlMeta.view "Main.qml")
  (assertEq "fixture qml: dependencies" qmlMeta.dependencies [])
  # Deliberately legacy, matching the ui-qml (QML-only) template: a QML-only
  # module has no C++ backend, so there is nothing for universal codegen to
  # derive a contract from. mkLogosQmlModule never consults `interface` at all,
  # and universal + ui_qml would route to uiCodegen, which demands a .rep this
  # fixture does not have. This fixture is BUILT by the qml-integration check.
  (assertEq "fixture qml: legacy authoring" qmlMeta.interface "legacy")

  # ---------------------------------------------------------------------------
  # External library module (mirrors waku-module vendor pattern)
  # ---------------------------------------------------------------------------
  (assertEq "fixture extlib: name" extlibMeta.name "test_extlib_module")
  (assertBool "fixture extlib: has external libraries"
    (builtins.length extlibMeta.external_libraries > 0) true)
  (assertEq "fixture extlib: first lib name"
    (builtins.head extlibMeta.external_libraries).name "testlib")
  (assertEq "fixture extlib: first lib vendor_path"
    (builtins.head extlibMeta.external_libraries).vendor_path "vendor/testlib")
  (assertEq "fixture extlib: second lib name"
    (builtins.elemAt extlibMeta.external_libraries 1).name "otherlib")
  (assertEq "fixture extlib: second lib build_command"
    (builtins.elemAt extlibMeta.external_libraries 1).build_command "cmake --build .")
  (assertEq "fixture extlib: cmake extra_include_dirs"
    extlibMeta.cmake.extra_include_dirs [ "vendor/testlib" "vendor/other" ])
  # Mirrors the external-lib template and the real vendor-extlib core modules
  # (storage, wallet, libp2p, blockchain) — all universal.
  (assertEq "fixture extlib: universal authoring" extlibMeta.interface "universal")

  # ---------------------------------------------------------------------------
  # ui_qml module with C++ backend (mirrors logos-package-manager-ui)
  # ---------------------------------------------------------------------------
  (assertEq "fixture backend: name" backendMeta.name "test_ui_qml_backend")
  (assertEq "fixture backend: type" backendMeta.type "ui_qml")
  (assertEq "fixture backend: main" backendMeta.main "test_ui_qml_backend_plugin")
  (assertEq "fixture backend: view" backendMeta.view "qml/Main.qml")
  (assertEq "fixture backend: dependencies" backendMeta.dependencies [ "some_core_module" ])
  # Both main and view present — the canonical ui_qml-with-backend shape
  (assertBool "fixture backend: has main and view"
    (backendMeta.main != null && backendMeta.view != null) true)
  # Deliberately legacy: this fixture mirrors logos-package-manager-ui, which
  # is STILL legacy-authored (ui_qml + C++ backend, no `interface` key). The
  # universal ui_qml shape is already covered on disk by the ui-qml-backend
  # TEMPLATE (test-templates.nix asserts interface + codegen.rep), so keeping
  # this one legacy preserves the only on-disk legacy ui_qml-with-backend
  # parse subject rather than duplicating template coverage.
  (assertEq "fixture backend: legacy authoring" backendMeta.interface "legacy")

  # ---------------------------------------------------------------------------
  # Module with dependencies
  # ---------------------------------------------------------------------------
  (assertEq "fixture deps: name" depsMeta.name "test_module_with_deps")
  (assertEq "fixture deps: type" depsMeta.type "ui_qml")
  (assertEq "fixture deps: dependencies" depsMeta.dependencies [ "dep_alpha" "dep_beta" ])
  (assertEq "fixture deps: view" depsMeta.view "Main.qml")
  # Deliberately legacy for the same reason as the qml fixture: QML-only
  # (view set, main null) has no C++ backend to derive a contract from.
  (assertEq "fixture deps: legacy authoring" depsMeta.interface "legacy")

  # ---------------------------------------------------------------------------
  # Cross-fixture consistency checks
  # ---------------------------------------------------------------------------
  (assertBool "all fixture names are non-empty"
    (coreMeta.name != "" && universalMeta.name != "" && uiMeta.name != "" &&
     qmlMeta.name != "" && extlibMeta.name != "" && depsMeta.name != "")
    true)
  (assertBool "all fixture versions are non-empty"
    (coreMeta.version != "" && universalMeta.version != "" && uiMeta.version != "" &&
     qmlMeta.version != "" && extlibMeta.version != "" && depsMeta.version != "")
    true)
  (assertBool "all fixture types are valid"
    (builtins.elem coreMeta.type [ "core" "ui" "ui_qml" ] &&
     builtins.elem universalMeta.type [ "core" "ui" "ui_qml" ] &&
     builtins.elem uiMeta.type [ "core" "ui" "ui_qml" ] &&
     builtins.elem qmlMeta.type [ "core" "ui" "ui_qml" ] &&
     builtins.elem backendMeta.type [ "core" "ui" "ui_qml" ] &&
     builtins.elem extlibMeta.type [ "core" "ui" "ui_qml" ] &&
     builtins.elem depsMeta.type [ "core" "ui" "ui_qml" ])
    true)

  # ---------------------------------------------------------------------------
  # ui_qml strict contract: view required, main optional
  # ---------------------------------------------------------------------------
  # QML-only: view set, main null
  (assertBool "qml-only: view is set" (qmlMeta.view != null) true)
  (assertEq "qml-only: main is null" qmlMeta.main null)

  # With backend: both view and main set
  (assertBool "backend: view is set" (backendMeta.view != null) true)
  (assertBool "backend: main is set" (backendMeta.main != null) true)

  # deps module (QML-only with deps)
  (assertBool "deps: view is set" (depsMeta.view != null) true)
  (assertEq "deps: main is null" depsMeta.main null)

  # ---------------------------------------------------------------------------
  # Platform-keyed fixture, read from disk
  # ---------------------------------------------------------------------------
  # ONE `include` spelling per target — which is the entire point of the
  # feature, and which the shape of this fixture has to demonstrate rather than
  # merely permit. It used to be written the obvious way:
  #
  #   "include": ["libcore.so"],
  #   "platforms": [ {"when":{"os":"darwin"},  "include":["libcore.dylib"]},
  #                  {"when":{"os":"windows"}, "include":["libcore.dll"]} ]
  #
  # and that is WRONG in the exact way the feature exists to remove. Lists
  # CONCATENATE, so darwin resolved to ["libcore.so","libcore.dylib"] and
  # windows to ["libcore.so","libcore.dll"]: still a cross-platform superset,
  # still relying on mkLogosModule tolerating a name that matches nothing, still
  # a list that drifts unvalidated — which is how logos-package-downloader-module
  # ended up naming .so and .dylib but not .dll. The .so is not a base value, it
  # is the LINUX value, so it belongs in the Linux overlay with the others.
  #
  # The correct shape, and the one an author should copy: an EMPTY base plus one
  # overlay per OS. It is also what makes the assertions below meaningful — each
  # target gets exactly one name, so a resolver that leaked a non-matching entry
  # would fail here instead of producing a longer list nobody reads.
  #
  # The point of doing this from a file at all: the inline cases in
  # test-parse-metadata.nix are built with builtins.toJSON, which can never
  # produce the shapes a hand-written metadata.json does.
  (assertEq "fixture overlay: include on linux"   overlayLinux.include   [ "libcore.so" ])
  (assertEq "fixture overlay: include on darwin"  overlayDarwin.include  [ "libcore.dylib" ])
  (assertEq "fixture overlay: include on windows" overlayWindows.include [ "libcore.dll" ])

  # Stated directly, because "one spelling per target" is the property, not the
  # particular strings: no target may resolve to a superset.
  (assertBool "fixture overlay: every target gets exactly ONE include entry"
    (builtins.length overlayLinux.include   == 1
     && builtins.length overlayDarwin.include  == 1
     && builtins.length overlayWindows.include == 1)
    true)

  # The krb5 case: a runtime package that CANNOT be declared as a superset,
  # because resolving it against a mingw package set is an evaluation-time
  # failure long before anything is compiled.
  (assertEq "fixture overlay: linux gets krb5"
    overlayLinux.nix_packages.runtime [ "nlohmann_json" "krb5" ])
  (assertEq "fixture overlay: windows does not"
    overlayWindows.nix_packages.runtime [ "nlohmann_json" ])

  # An architecture-only selector spelled `arm64`, canonicalised to aarch64 —
  # it must reach aarch64-darwin and skip x86_64-linux.
  #
  # `cmake.extra_link_libraries` is used here only because it is the one
  # overlay-able key with a distinct shape; note that NOTHING in the workspace
  # currently consumes `config.cmake.*` (parsed at parseMetadata.nix:188-192,
  # zero readers anywhere), so this asserts resolution, not configuration. Do
  # not copy this fixture as an example of how to add a link library.
  (assertEq "fixture overlay: arm64 selector reaches aarch64-darwin"
    overlayDarwin.cmake.extra_link_libraries [ "atomic" ])
  (assertEq "fixture overlay: arm64 selector skips x86_64"
    overlayLinux.cmake.extra_link_libraries [ ])

  # Fields no overlay touches are identical across targets — a resolver that
  # leaked overlay residue into the base would show up here first.
  (assertEq "fixture overlay: untouched fields are target-independent"
    { inherit (overlayLinux) name version type main; build = overlayLinux.nix_packages.build; }
    { inherit (overlayWindows) name version type main; build = overlayWindows.nix_packages.build; })
]
