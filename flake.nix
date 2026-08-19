{
  description = "Logos Module Builder - Shared library for building Logos modules with minimal boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    # Optional newer rustc for crates whose deps out-pace the nixpkgs rustc
    # (opt-in per module via metadata `nix.rust.toolchain`).
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    # SDK and module deps — owned by this builder, injected into backends.
    #
    # Unpinned again: this used to carry a rev (620f2e1, tip of
    # feat/sdk-codegen-b3-d11) because the B3/B4 SDK split — the capability
    # split and the generator entry points this builder calls (buildHeaders'
    # contract-driven wrapper, the qt-generator hand-off) — had not reached
    # master. logos-cpp-sdk#138 ("split the SDK by capability, retire the
    # provider-header path, and harden the cdylib decode") MERGED and closed
    # that gap; master (95d7b3a) carries cpp/logos_host_services.h and the rest
    # of the split, so plain master is correct again. NOTE: the PR was
    # SQUASH-merged, so `git merge-base --is-ancestor 620f2e1 master` is
    # correctly false — ancestry is the wrong test, the files are the test.
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-cpp-sdk.inputs.logos-protocol.follows = "logos-protocol";
    # Protocol layer (transports + lp_* C ABI + the protocol semver every
    # module gets stamped with) and the Qt developer layer modules link.
    #
    # Unpinned again: this used to carry c8bab12 because logos-qt-host (in
    # logos-plugin-qt, below) calls TokenManager::forIdentity/isolateIdentity,
    # which lived only on feat/per-client-token-store. logos-protocol#59
    # ("per-client token store, the host-services C ABI, and a container
    # shape-check") MERGED, so master (f4407ff) now has both
    # forIdentity/isolateIdentity in cpp/token_manager.h and
    # lp_grant_host_services/lp_token_keys in cpp/logos_protocol.h. Since this
    # input is the one every other protocol consumer here `follows`, master is
    # now the right thing for the whole closure to land on. NOTE: SQUASH-merged,
    # so ancestry of c8bab12 in master is correctly false — check the files.
    logos-protocol.url = "github:logos-co/logos-protocol";
    # Unpinned: feat/sdk-codegen-b3-d11 merged (logos-qt-sdk#33), so the header
    # this builder probes and the logos-qt-generator it takes are both on master
    # in their B3 shape. Also SQUASH-merged — ancestry of aca2951 in master is
    # correctly false; the files are what to check.
    #
    # Worth recording why this one mattered: nothing makes logos-qt-sdk `follows`
    # anywhere, so a single revision across consumers was upheld by hand-pinning
    # the same rev — and it had already drifted (this repo pinned aca2951 while
    # logos-test-framework and logos-basecamp pinned 8a06b870). Tracking master
    # makes the one-revision property structural instead of conventional.
    logos-qt-sdk.url = "github:logos-co/logos-qt-sdk";
    logos-qt-sdk.inputs.logos-protocol.follows = "logos-protocol";
    logos-qt-sdk.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-module.url = "github:logos-co/logos-module";
    # UI modules (type: ui, ui_qml) always use Qt.
    #
    # This backend also owns the Qt HOST RUNTIME every plugin links
    # (packages.<sys>.logos-qt-host), so its logos-protocol input is now
    # load-bearing and must be the SAME logos-protocol the module links —
    # exactly the reason logos-qt-sdk above carries the same `follows`. Two
    # protocol builds on one link line means two TokenManager singletons.
    #
    # Unpinned again. This used to carry an explicit rev because the builder
    # needs two outputs master did not have — packages.<sys>.logos-qt-host and
    # .logos-qt-host-generator — and without them `rust-native-dep` and
    # `test-framework-integration` do not even EVALUATE. logos-plugin-qt#19
    # ("the Qt host runtime and cdylib-glue generator") MERGED and closed that
    # gap: master (9b2c64e) publishes both, keyed by `forAllTargets`, so even
    # packages.x86_64-windows.logos-qt-host resolves. NOTE: SQUASH-merged, so
    # `merge-base --is-ancestor 2d25069 master` is correctly false; the outputs
    # in master's flake.nix are the test that matters.
    #
    # It no longer needs .logos-view-templates from here. The four LogosView*.in
    # templates moved OUT of this backend into logos-view-module (below), which
    # owns the ui_qml authoring flavour end to end; logos-plugin-qt is now
    # exclusively what makes a cdylib module loadable by logos-module-loader-qt.
    #
    # The old 2d25069 pin was the tip of feat/b4-qt-host-windows-target; the
    # whole of it, Windows target included, is in master via #19. master's
    # cmake/ directory is GONE — that is expected, not a regression: the view
    # templates moved to logos-view-module (below) and cmake/LogosModule.cmake
    # lives in THIS repo, so the builder never reads cmake/ from this backend.
    logos-plugin-qt.url = "github:logos-co/logos-plugin-qt";
    logos-plugin-qt.inputs.logos-protocol.follows = "logos-protocol";
    # Core modules (type: core) use this backend — defaults to Qt, swappable
    # later. It MUST stay on the same rev as logos-plugin-qt above: the two
    # inputs are selected per module TYPE, they both carry the Qt host runtime,
    # and a split pin means core modules and ui modules link two different
    # copies of it — two logos-qt-hosts in one closure. Unpinned together with
    # logos-plugin-qt above now that logos-plugin-qt#19 has merged.
    logos-plugin-core.url = "github:logos-co/logos-plugin-qt";
    logos-plugin-core.inputs.logos-protocol.follows = "logos-protocol";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    nix-bundle-logos-module-install.url = "github:logos-co/nix-bundle-logos-module-install";
    # Host shell used by `nix run` / integration tests for ui_qml modules.
    # Design system + view-module-runtime are pinned HERE (not only inside
    # standalone's lock) so a bump for module testing is one lock update on
    # this flake — no standalone release required.
    logos-design-system.url = "github:logos-co/logos-design-system";
    # Rev-pinned: `view-interface-abi` below reads this runtime's HOST-side
    # declaration of the view plugin interfaces and diffs it against the
    # module-side templates from logos-view-module. Both sides moved to the
    # qt-host runtime together, so a master pin here would compare the new
    # templates against the old host and fail on a difference that does not
    # exist. UNPINNED now: logos-view-module-runtime#25 merged, so master carries
    # the qt-host repoint and no longer rev-pins logos-plugin-qt itself — the two
    # sides of the ABI check are back in step on master.
    logos-view-module-runtime.url = "github:logos-co/logos-view-module-runtime";
    # The MODULE side of that same pair, and the ui_qml authoring flavour as a
    # whole: LogosViewModule.cmake, the four LogosView*.in templates
    # logos_module(REP_FILE ...) instantiates, and the view glue generator.
    # They used to live in logos-plugin-qt; that backend is now exclusively
    # what makes a cdylib module loadable by logos-module-loader-qt, so the
    # authoring half moved to the repo that owns it end to end.
    #
    # Two things here consume it, and they want the SAME bytes: the
    # `view-interface-abi` check below reads
    # packages.<sys>.logos-view-templates/LogosView*.h.in directly, and
    # lib/{mkLogosModule,buildCppPlugin}.nix hand that same store path to
    # every plugin build as LOGOS_VIEW_TEMPLATE_DIR (cmake flag + env var),
    # because cmake/LogosModule.cmake here refuses to guess.
    #
    # ACYCLIC: logos-view-module is a LEAF — its only input is logos-nix, so it
    # cannot reach back to this builder. That is the property that let the
    # templates move at all; logos-plugin-qt could not host both consumers
    # without one of them depending on the other the wrong way round.
    #
    # Rev-pinned for the same reason logos-plugin-qt is: `nix flake update` must
    # not be able to walk this back to a commit without
    # packages.<sys>.logos-view-templates, which `view-interface-abi` and every
    # ui_qml plugin build need. UNPINNED: 1f95a75 (the #2 merge that moved the
    # templates in) IS this repo's master tip, so the pin was already a no-op.
    logos-view-module.url = "github:logos-co/logos-view-module";
    logos-view-module.inputs.logos-nix.follows = "logos-nix";
    # Unpinned: logos-standalone-app#37 merged (master 13b81c9), so the host shell
    # for ui_qml `nix run` / integration tests carries the qt-host repoint, the
    # hot-reload fix (#36) and the capability-bundling removal on master. Squash
    # merge, so b67eddd is not an ancestor of it — the content is.
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    logos-standalone-app.inputs.logos-design-system.follows = "logos-design-system";
    logos-standalone-app.inputs.logos-view-module-runtime.follows = "logos-view-module-runtime";
    # Test framework for module unit tests.
    #
    # Rev-pinned, unlike before: mkLogosModuleTests now passes
    # -DLOGOS_QT_HOST_ROOT, and it is LogosTest.cmake on this branch that
    # prefers it (master's copy knows only LOGOS_QT_SDK_ROOT). Left unpinned,
    # `nix flake update` silently locks master and `test-framework-integration`
    # links the unit tests against the wrong runtime root. UNPINNED: that gap is
    # closed — logos-test-framework#6 merged and master's cmake/LogosTest.cmake
    # now knows LOGOS_QT_HOST_ROOT (6 references), which is what the pin was
    # waiting on.
    logos-test-framework.url = "github:logos-co/logos-test-framework";
    logos-test-framework.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    # The Rust SDK provides logos-lidl-gen (the generator the builder runs for
    # codegen.rust modules) and the SDK source the crate links. logos-rust-sdk
    # depends BACK on this builder for its own integration tests, so its
    # logos-module-builder input is cut with `follows` to break the cycle — we
    # only consume its lidl-gen package + source tree, never its tests. The other
    # branch-pinned test-only inputs are cut too so they aren't fetched.
    logos-rust-sdk.url = "github:logos-co/logos-rust-sdk/0b4b8edd5127378b78890297f5fcec738b81f8e2";
    logos-rust-sdk.inputs.logos-nix.follows = "logos-nix";
    logos-rust-sdk.inputs.logos-module-builder.follows = "logos-cpp-sdk";
    logos-rust-sdk.inputs.logos-logoscore-cli.follows = "logos-cpp-sdk";
    nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, logos-nix, logos-cpp-sdk, logos-protocol, logos-qt-sdk, logos-module, logos-plugin-qt, logos-plugin-core, logos-view-module, logos-view-module-runtime, nix-bundle-logos-module-install, nix-bundle-lgx, logos-standalone-app, logos-test-framework, logos-rust-sdk, rust-overlay ? null, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });

      # Import the library functions
      # Use rawLib from backends — we inject logos-cpp-sdk/logos-module ourselves
      lib = import ./lib {
        inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app;
        inherit logos-nix;
        inherit logos-cpp-sdk logos-protocol logos-qt-sdk logos-module logos-test-framework logos-rust-sdk;
        # The FLAKE, not its lib: the cdylib glue generator is a package of it.
        inherit logos-plugin-qt;
        # Likewise a FLAKE, for packages.<sys>.logos-view-templates — the
        # LOGOS_VIEW_TEMPLATE_DIR every ui_qml plugin build is handed.
        inherit logos-view-module;
        inherit rust-overlay;
        inherit (nixpkgs) lib;
        uiBackend = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
        coreBackend = logos-plugin-core.rawLib or logos-plugin-core.lib;
        builderRoot = ./.;
      };
    in
    {
      # Export the library functions for use by modules
      lib = lib;

      # The logos-rust-sdk source tree at the rev this builder pins — exposed so a
      # codegen.rust module can stage it as `../logos-rust-sdk-src` to generate its
      # Cargo.lock against the SAME SDK the builder links, without needing a
      # logos-rust-sdk input in the module's own flake.
      packages = forAllSystems ({ pkgs, ... }: {
        rust-sdk-src = pkgs.runCommand "logos-rust-sdk-src" {} "cp -r ${logos-rust-sdk} $out";
      });

      # Also expose as an overlay for convenience
      overlays.default = final: prev: {
        logosModuleBuilder = lib;
      };

      # Templates for scaffolding new modules
      templates = {
        default = {
          path = ./templates/minimal-module;
          description = "Minimal Logos module template";
        };

        with-external-lib = {
          path = ./templates/external-lib-module;
          description = "Logos module template with external library";
        };

        ui-qml-backend = {
          path = ./templates/ui-qml-backend;
          description = "Logos ui_qml module with C++ backend (process-isolated) and QML view";
        };

        ui-qml = {
          path = ./templates/ui-qml;
          description = "Logos ui_qml module (QML-only, no C++ backend)";
        };
      };

      # Tests — pure Nix evaluation tests (no compilation)
      checks = forAllSystems ({ pkgs, system, ... }: {
        default = import ./tests {
          inherit pkgs;
          inherit (nixpkgs) lib;
          inherit (lib) parseMetadata common mkExternalLib;
        };
        # Integration test: actually builds a QML module from a fixture
        qml-integration = import ./tests/test-qml-integration.nix {
          inherit pkgs;
          mkLogosQmlModule = lib.mkLogosQmlModule;
          fixturesRoot = ./tests/fixtures;
        };
        # Integration test: builds and runs unit tests via logos-test-framework
        test-framework-integration = import ./tests/test-framework-integration.nix {
          inherit pkgs;
          mkLogosModuleTests = lib.mkLogosModuleTests;
          inherit (lib) parseMetadata;
          fixturesRoot = ./tests/fixtures;
        };
        # Integration test: verifies static library (.a) support in EXTERNAL_LIBS
        static-extlib = import ./tests/test-static-extlib.nix {
          inherit pkgs;
        };
        # WHICH Qt host runtime logos_module() links, and that a root with no
        # host runtime in it is a hard error rather than a silent skip.
        qt-host-repoint = import ./tests/test-qt-host-repoint.nix {
          inherit pkgs;
        };
        # The module-side and host-side declarations of the view plugin
        # interfaces must agree. Two copies that cannot be merged, bound only
        # by an IID string, where a mismatch is silent — see the file header.
        # This repo is the only one that sees both sides.
        view-interface-abi = import ./tests/test-view-interface-abi.nix {
          inherit pkgs;
          viewTemplates =
            logos-view-module.packages.${system}.logos-view-templates
              or (throw ("logos-module-builder: the pinned logos-view-module "
                + "predates packages.<sys>.logos-view-templates, so the "
                + "LogosView*.in templates cannot be located. Bump the "
                + "logos-view-module input — the templates moved OUT of "
                + "logos-plugin-qt into it, so neither logos-plugin-qt nor "
                + "logos-protocol is the pin to touch."));
          viewRuntime = logos-view-module-runtime;
        };
        # Integration test: a Rust cdylib module with an external system build dep
        # declared via the `nix.rust` block — proves pkg-config/openssl-style deps
        # reach the crate's buildRustPackage compile.
        rust-native-dep = import ./tests/test-rust-native-dep.nix {
          inherit pkgs;
          mkLogosModule = lib.mkLogosModule;
          fixturesRoot = ./tests/fixtures;
        };
      });

      # Development shell for working on the builder itself
      devShells = forAllSystems ({ pkgs, system, ... }:
        let
          logosSdk = logos-cpp-sdk.packages.${system}.default;
          logosModule = logos-module.packages.${system}.default;
          uiLib = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
          backendShell = uiLib.devShellInputs pkgs { inherit logosModule; };
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = backendShell.nativeBuildInputs ++ [
              logosSdk
              pkgs.yq  # For YAML parsing in scripts
            ];
            buildInputs = backendShell.buildInputs;
            shellHook = ''
              ${backendShell.shellHook}
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              # The backend stopped exporting this when the templates left it.
              # Text files with no platform dimension, so plain `${system}`
              # here is fine — this flake's `systems` list is native-only.
              export LOGOS_VIEW_TEMPLATE_DIR="${logos-view-module.packages.${system}.logos-view-templates}"
              echo "Logos Module Builder development environment"
            '';
          };
        }
      );
    };
}
