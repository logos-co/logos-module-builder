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
    # Rev-pinned for the same reason logos-plugin-qt below is: the B3/B4 SDK
    # split has not reached logos-cpp-sdk's master, and the generator entry
    # points this builder now calls (buildHeaders' contract-driven wrapper,
    # the qt-generator hand-off) only exist on that branch. a04b278 is the tip
    # of feat/sdk-codegen-b3-d11 and a fast-forward from master (e3744fb is an
    # ancestor of it), so nothing on master is given up. Drop the rev once the
    # branch merges.
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk/a04b27888e1d126578f639ed46dae0c777990a10";
    logos-cpp-sdk.inputs.logos-protocol.follows = "logos-protocol";
    # Protocol layer (transports + lp_* C ABI + the protocol semver every
    # module gets stamped with) and the Qt developer layer modules link.
    #
    # Rev-pinned: logos-qt-host (in logos-plugin-qt, below) calls
    # TokenManager::forIdentity/isolateIdentity, which live on
    # feat/per-client-token-store and NOT on logos-protocol's master. This
    # input is the one every other protocol consumer here `follows`, so an
    # unpinned url would lock the whole closure onto a master that cannot
    # compile the host runtime. c8bab12 is a fast-forward from master
    # (e6d5b57 is an ancestor of it). Drop the rev once it merges.
    logos-protocol.url = "github:logos-co/logos-protocol/c8bab12834dbf92155b483546875e6078d17c74e";
    # Rev-pinned alongside logos-cpp-sdk: this builder probes logos-qt-sdk by a
    # header it owns and takes logos-qt-generator from it, and both of those
    # are the B3 branch's shape. 8a06b87 is the tip of feat/sdk-codegen-b3-d11
    # and a fast-forward from master (c6be61d is an ancestor of it).
    logos-qt-sdk.url = "github:logos-co/logos-qt-sdk/8a06b870e59afca3392de2bddf8eec5fe3b85225";
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
    # Pinned to an explicit rev, not to master. This builder needs three
    # outputs that master does not have yet — packages.<sys>.logos-qt-host,
    # .logos-qt-host-generator and .logos-view-templates — and without them
    # `rust-native-dep`, `test-framework-integration` and `view-interface-abi`
    # do not even EVALUATE, so CI is red before it builds anything. The rev is
    # spelled out here rather than left to the lock so that `nix flake update`
    # cannot silently walk it back to a master that still lacks those outputs.
    # Drop the rev (back to plain `github:logos-co/logos-plugin-qt`) once this
    # stack has landed on master.
    #
    # cc24fa1 is the tip of logos-plugin-qt's feat/b4-qt-host-windows-target,
    # rebased onto that repo's master (8846fc5 is an ancestor of it). It is the
    # SUPERSET of the sibling feat/b4-qt-host-windows-target-8ccb1fc branch:
    # that one re-baselines onto 8ccb1fc and drops the LogosModule.cmake
    # repoint and the view-templates commit, so its flake exposes no
    # packages.<sys>.logos-view-templates at all and `view-interface-abi`
    # below would hit the throw. Point both this and logos-plugin-core at the
    # superset. (It replaces the old fcf5a29 pin, whose content it carries
    # under rebased shas — 4c581a6/e4ea357/fcf5a29 are fe780a6/34704d1/3d7e3e6
    # there.)
    logos-plugin-qt.url = "github:logos-co/logos-plugin-qt/2d25069";
    logos-plugin-qt.inputs.logos-protocol.follows = "logos-protocol";
    # Core modules (type: core) use this backend — defaults to Qt, swappable
    # later. It MUST stay on the same rev as logos-plugin-qt above: the two
    # inputs are selected per module TYPE, they both carry LogosModule.cmake
    # and the Qt host runtime, and a split pin means core modules and ui
    # modules link two different copies of it.
    logos-plugin-core.url = "github:logos-co/logos-plugin-qt/2d25069";
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
    # module-side templates from logos-plugin-qt. Both sides moved to the
    # qt-host runtime together, so a master pin here would compare the new
    # templates against the old host and fail on a difference that does not
    # exist. 5510acd is the tip of feat/sdk-codegen-b4-qt-host and a
    # fast-forward from master (471dd56 is an ancestor of it).
    logos-view-module-runtime.url = "github:logos-co/logos-view-module-runtime/5510acd9eb7fcd49e420c9e530679edfa8f315ab";
    # Rev-pinned: the host shell for ui_qml `nix run` / integration tests took
    # the same qt-host repoint. 39f4f2b is the tip of feat/sdk-codegen-b4-qt-host
    # and a fast-forward from master (288fec2 is an ancestor of it).
    logos-standalone-app.url = "github:logos-co/logos-standalone-app/39f4f2b507846bf6383f60a4c61d8a9445009227";
    logos-standalone-app.inputs.logos-design-system.follows = "logos-design-system";
    logos-standalone-app.inputs.logos-view-module-runtime.follows = "logos-view-module-runtime";
    # Test framework for module unit tests.
    #
    # Rev-pinned, unlike before: mkLogosModuleTests now passes
    # -DLOGOS_QT_HOST_ROOT, and it is LogosTest.cmake on this branch that
    # prefers it (master's copy knows only LOGOS_QT_SDK_ROOT). Left unpinned,
    # `nix flake update` silently locks master and `test-framework-integration`
    # links the unit tests against the wrong runtime root. c382ab1 is the tip
    # of feat/sdk-codegen-b4-test-framework and a fast-forward from master
    # (eb1600c is an ancestor of it).
    logos-test-framework.url = "github:logos-co/logos-test-framework/c382ab1d069a1b44cac6adcfc9c53c4f17c02971";
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

  outputs = { self, nixpkgs, logos-nix, logos-cpp-sdk, logos-protocol, logos-qt-sdk, logos-module, logos-plugin-qt, logos-plugin-core, logos-view-module-runtime, nix-bundle-logos-module-install, nix-bundle-lgx, logos-standalone-app, logos-test-framework, logos-rust-sdk, rust-overlay ? null, ... }:
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
            logos-plugin-qt.packages.${system}.logos-view-templates
              or (throw ("logos-module-builder: the pinned logos-plugin-qt "
                + "predates packages.<sys>.logos-view-templates, so the "
                + "LogosView*.in templates cannot be located. Bump the "
                + "logos-plugin-qt input — that pin is what moved; "
                + "logos-protocol is not the one to touch."));
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
              echo "Logos Module Builder development environment"
            '';
          };
        }
      );
    };
}
