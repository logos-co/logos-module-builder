# Core module builder function
# This is the main entry point for building Logos modules.
# Plugin compilation and header generation are delegated to a backend selected
# by metadata.json "type": core modules use coreBackend, UI modules use uiBackend.
{ nixpkgs, lib, common, parseMetadata, builderRoot, uiBackend, coreBackend, logos-cpp-sdk, logos-protocol ? null, logos-qt-sdk ? null, logos-module, logos-test-framework, logos-rust-sdk ? null, nix-bundle-lgx, nix-bundle-logos-module-install, logos-standalone-app }:

{
  # Required: Path to the module source
  src,

  # Required: Path to the metadata.json configuration file
  configFile,

  # Optional: all flake inputs — dependencies in metadata.json are resolved automatically
  flakeInputs ? {},

  # Optional: Additional flake inputs for external libraries
  externalLibInputs ? {},

  # Optional: Extra build inputs to add
  extraBuildInputs ? [],

  # Optional: Extra native build inputs to add
  extraNativeBuildInputs ? [],

  # Optional: Extra inputs/env for the Rust crate compile (cdylib modules).
  # Programmatic escape hatch complementing metadata `nix.rust` — for arbitrary
  # derivations or store-path env that can't be named by a nixpkgs attr path.
  # Merged on top of the metadata-declared inputs (rustEnv wins on key conflict).
  rustExtraNativeBuildInputs ? [],
  rustExtraBuildInputs ? [],
  rustEnv ? {},

  # Optional: Override any config values
  configOverrides ? {},

  # Optional: Custom preConfigure hook
  preConfigure ? "",

  # Optional: Custom postInstall hook
  postInstall ? "",

  # Optional: override the logos-standalone-app used for `nix run`.
  # By default, UI modules (type = "ui") automatically get apps.default wired up
  # using the standalone app bundled with logos-module-builder.
  logosStandalone ? null,

  # Optional: Unit test configuration. When provided, a checks.<system>.unit-tests
  # output is automatically generated using logos-test-framework.
  #   tests = {
  #     dir = ./tests;        # Required: directory containing test sources + CMakeLists.txt
  #     mockCLibs = [];       # Optional: C libraries to mock at link time
  #     preConfigure = "";    # Optional: custom preConfigure hook
  #     extraBuildInputs = [];
  #     extraCmakeFlags = [];
  #   };
  tests ? null,
}:

let
  # Parse the module configuration
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];

  # Select backend based on module type: core modules are swappable, UI stays Qt
  selectedBackend =
    if config.type == "core" then coreBackend
    else uiBackend;

  # Import sub-builders (backend-agnostic)
  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };
  mkStandaloneApp = import ./mkStandaloneApp.nix;
  modulePreConfigure = import ./modulePreConfigure.nix { inherit lib; };

  # When this flake ships cmake/LogosModule.cmake, override LOGOS_MODULE_BUILDER_ROOT
  # so the extended macros (generated_code glob, metadata copy, Go static libs) are used.
  # Otherwise let the backend's default take over — it already sets
  # LOGOS_MODULE_BUILDER_ROOT to its own root which has cmake/LogosModule.cmake.
  hasBuilderCmake = builtins.pathExists (builderRoot + "/cmake/LogosModule.cmake");

  # Helper to get a package from nixpkgs by name
  getPkg = pkgs: name:
    let evaluatedName = builtins.seq name name;
    in if builtins.isString evaluatedName
       then lib.getAttrFromPath (lib.splitString "." evaluatedName) pkgs
       else builtins.throw "getPkg expected string but got ${builtins.typeOf evaluatedName}";

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  # Package outputs
  packages = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };

      # ── Concrete dependency classification ─────────────────────────────────
      # A dependency's typed `modules().<dep>` wrapper is generated from its
      # published LIDL contract (`packages.<sys>.lidl`) WITHOUT building the
      # dep's plugin. Deps that don't expose a `lidl` output yet take the
      # TRANSITIONAL header-copy fallback (`legacyHeaderDepNames`), which DOES
      # build them — identical to today's behavior.
      # Returns the dep's published LIDL output, or null if the input isn't a
      # flake exposing packages.<system>.lidl (e.g. a raw-derivation dep, or a
      # module built by a builder that predates this feature) — those fall
      # through to the TRANSITIONAL header-copy path. Guard every level so a
      # non-flake input never throws.
      depLidlOf = name:
        let i = flakeInputs.${name} or null;
        in if i != null && i ? packages && i.packages ? ${system}
           then (i.packages.${system}.lidl or null)
           else null;
      depIsLidl = name: (config.dependency_overrides ? ${name}) || (depLidlOf name != null);

      # LIDL-based deps → `--dep <name>=<lidl>` for the generator. An override
      # forces a specific definition (.lidl, or .h + impl_class); otherwise we
      # use the dep's published `lidl` output.
      staticDeps = map (name:
        let ov = config.dependency_overrides.${name} or null;
        in if ov != null then {
             inherit name;
             impl_class = ov.impl_class;
             path = if ov.input != null
                    then (if flakeInputs ? ${ov.input}
                          then "${flakeInputs.${ov.input}}/${ov.file}"
                          else throw "dependency_overrides.${name}: flake input '${ov.input}' was not passed to mkLogosModule.")
                    else "${src}/${ov.file}";
           } else {
             inherit name;
             impl_class = null;
             path = "${depLidlOf name}/${name}.lidl";
           }
      ) (lib.filter depIsLidl config.dependencies);

      # TRANSITIONAL: header-copy fallback for deps that predate the `lidl`
      # output. These deps ARE built (their headers come from introspecting the
      # compiled plugin). Remove this block — and the `moduleDepIncludes` use in
      # the plugin backends — once every module exposes packages.<sys>.lidl.
      legacyHeaderDepNames = lib.filter (name: !(depIsLidl name)) config.dependencies;

      # Resolve the fallback deps from inputs. Each entry is exposed
      # as a struct so the plugin builder can pick BOTH the dep's
      # plugin .dylib AND the right header variant for its own
      # --api-style without re-running the codegen at consume time.
      # Backward-compatible fallbacks let older deps (which only
      # expose `default`) still work — they get treated as Qt-typed.
      moduleInputs = lib.filterAttrs (n: _: builtins.elem n legacyHeaderDepNames) flakeInputs;
      resolvedModuleDeps = lib.mapAttrs (_: input:
        let
          ps = input.packages.${system} or null;
          # Pre-version of this refactor: input was the raw flake-output
          # derivation (not a packages set). Preserve that path so an
          # external flake-input dep still works.
          fallback = if input ? packages.${system}.default
                     then input.packages.${system}.default else input;
        in
        if ps != null then {
          default     = ps.default;
          lib         = ps.lib or ps.default;
          headers-qt  = ps.headers-qt or ps.include or ps.default;
          headers-std = ps.headers-std or ps.headers-qt or ps.include or ps.default;
          # lp (Qt-free) variant for core universal consumers. Falls back to
          # std/qt for a dep built by an older builder that predates headers-lp.
          headers-lp  = ps.headers-lp or ps.headers-std or ps.headers-qt or ps.include or ps.default;
        } else {
          default     = fallback;
          lib         = fallback;
          headers-qt  = fallback;
          headers-std = fallback;
          headers-lp  = fallback;
        }
      ) moduleInputs;

      # Resolve interface dependencies (method/event contracts) to concrete
      # definition-file paths. A LOCAL interface lives in this repo's `src`;
      # a REMOTE one comes from a flake input named by `input` — mirroring
      # how `dependencies` resolve to flake inputs. We resolve the path here
      # so the generator never touches flake inputs: it just receives
      # `--interface <name>=<path>[=<impl_class>]`. (System-independent, but
      # kept in this scope alongside resolvedModuleDeps for locality.)
      resolvedInterfaceDeps = map (e: {
        inherit (e) name impl_class;
        path = if e.input != null
               then (if flakeInputs ? ${e.input}
                     then "${flakeInputs.${e.input}}/${e.file}"
                     else throw "interface_dependencies: interface '${e.name}' references flake input '${e.input}', but no such input was passed to mkLogosModule (declare it in flake.nix and pass it via flakeInputs).")
               else "${src}/${e.file}";
      }) config.interface_dependencies;

      # Resolve a single externalLibInputs entry for a given variant.
      # Supports both simple (bare flake input) and structured ({ input, packages }) formats.
      resolveExtInput = variant: name: value:
        if builtins.isAttrs value && value ? input then
          let
            flakeInput = value.input;
            packages = value.packages or {};
            pkgName = packages.${variant} or packages.default or "default";
          in
            if flakeInput ? packages.${system}.${pkgName}
            then flakeInput.packages.${system}.${pkgName}
            else builtins.throw ''
              External lib "${name}": flake input does not provide packages.${system}.${pkgName}.
              Check the "externalLibInputs" structured entry and ensure the flake input exposes the expected package.
            ''
        else
          if value ? packages.${system}.default then value.packages.${system}.default else value;

      # Whether any external lib input declares per-variant packages
      hasVariants = lib.any (v: builtins.isAttrs v && v ? input && v ? packages)
        (lib.attrValues externalLibInputs);

      buildPkgs   = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.runtime);

      # Rust crate compile inputs (metadata nix.rust). build -> nativeBuildInputs
      # (host tools), runtime -> buildInputs (link libs). Resolved with the same
      # dotted-path getPkg as buildPkgs/runtimePkgs. Fed only to rustStaticLib,
      # not the C++ plugin link.
      rustNativeBuildPkgs = map (getPkg pkgs) (lib.filter builtins.isString config.nix_rust.packages.build);
      rustBuildPkgs       = map (getPkg pkgs) (lib.filter builtins.isString config.nix_rust.packages.runtime);

      # Pre-resolve default variant external libs (always needed, avoids
      # duplicate evaluation when hasVariants triggers a second buildVariant).
      defaultResolvedExternalLibs = lib.mapAttrs (resolveExtInput "default") externalLibInputs;
      defaultExternalLibs = mkExternalLib.buildExternalLibs {
        inherit pkgs config src;
        externalInputs = defaultResolvedExternalLibs;
      };

      # Resolve SDK deps for this system — injected into the backend
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosQtSdk = logos-qt-sdk.packages.${system}.default;
      # The Qt glue generator (universal/cdylib/ui backends) — Qt code is
      # the Qt layer's product; logos-cpp-generator keeps Qt-free outputs.
      logosQtGenerator = logos-qt-sdk.packages.${system}.logos-qt-generator;
      logosProtocolPkg = logos-protocol.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;

      # The logos-protocol semver — parsed from the protocol header the
      # whole stack links. Stamped into every module's embedded metadata
      # (see modulePreConfigure.stampProtocolVersion). null (no stamp) only
      # if the input is somehow absent — modules then load as "legacy".
      protocolVersion =
        if logos-protocol == null then null
        else
          let
            header = builtins.readFile "${logos-protocol}/cpp/logos_protocol.h";
            parts = builtins.split "LOGOS_PROTOCOL_VERSION_STRING \"([^\"]*)\"" header;
          in if builtins.length parts < 2 then null
             else builtins.head (builtins.elemAt parts 1);

      # ── Rust cdylib authoring (codegen.rust) ───────────────────────────────
      # A Rust module's module-impl C ABI scaffold (logos_module_* exports +
      # typed trait + RustModuleContext + dep clients) is generated from the SAME
      # .lidl contract that drives the Qt glue, and the crate is compiled to a
      # staticlib — both done HERE by the builder, exactly as it runs the C++
      # generator. The author writes no build.rs and the module's flake stays
      # trivial (no buildRustPackage / preConfigure staging).
      #
      # logos-lidl-gen AND the SDK source the crate links both come from this
      # builder's own logos-rust-sdk input — so a Rust module's flake.nix is
      # identical to a C++ one (just logos-module-builder), and the generator and
      # the runtime SDK are the SAME pinned rev (no skew). logos-rust-sdk depends
      # back on this builder for its tests, so its module-builder input is cut
      # with `follows` in flake.nix to break the cycle (see there).
      isRustModule = (config.codegen or {}) ? rust;
      rustCfg = (config.codegen or {}).rust or {};
      rustCrateDir =
        "${src}/${rustCfg.crate or (throw "codegen.rust must set 'crate' (the crate directory, e.g. \"rust-lib\") in ${config.name}")}";
      # The staticlib basename (produces lib<name>.a) — read from the crate's
      # Cargo.toml ([lib].name, else [package].name with - -> _) so the author
      # needn't repeat it. codegen.rust.staticlib still overrides if set.
      rustCargoToml =
        if !isRustModule then {}
        else builtins.fromTOML (builtins.readFile "${rustCrateDir}/Cargo.toml");
      rustStaticName =
        rustCfg.staticlib
          or (rustCargoToml.lib.name
              or (lib.replaceStrings ["-"] ["_"] rustCargoToml.package.name));
      # Rust-FIRST authoring: when codegen.rust names the contract `trait`, that
      # trait is declared in the crate and the .lidl is DERIVED from it at build
      # time (logos-lidl-gen --from-rust over the crate source) — exactly as a
      # universal C++ module derives its .lidl from the impl header. The .rs file
      # is the single source of truth: no committed .lidl, no manual derive step.
      # The scaffold is then generated with --no-trait (the trait is the
      # author's). Without `trait`, the module is contract-first: codegen.lidl is
      # a committed file and the trait is generated.
      rustTrait = rustCfg.trait or null;
      rustDeriveMode = rustTrait != null;
      # The .rs file holding the trait (+ optional <Trait>Events companion),
      # relative to the crate dir.
      rustSource = rustCfg.source or "src/lib.rs";
      rustSdk =
        if !isRustModule then null
        else if logos-rust-sdk == null
        then throw "codegen.rust module '${config.name}' requires logos-module-builder to be built with a logos-rust-sdk input (it provides the lidl-gen generator + the SDK source). Update the builder."
        else logos-rust-sdk;
      rustGen = if !isRustModule then null else rustSdk.packages.${system}.lidl-gen;

      # The dep contracts that feed the Rust generator: the same resolved
      # concrete + interface deps the C++ generator gets. Concrete deps →
      # `modules().<dep>`; interface deps → a bound client (`<Iface>Client::bind`).
      # Both arrive as `--dep name=<lidl>` (the Rust CLI has no separate
      # interface flag — every generated client carries new() AND bind()).
      rustDepFlags = lib.concatStringsSep " " (
        (map (d: "--dep ${d.name}=${d.path}") staticDeps)
        ++ (map (e: "--dep ${e.name}=${e.path}") resolvedInterfaceDeps)
      );

      # The contract .lidl, derived from the crate's trait in rust-first mode.
      # Reused by the scaffold gen, the Qt glue (staged into the build below), and
      # the published `packages.<sys>.lidl`.
      derivedLidl =
        if !rustDeriveMode then null
        else pkgs.runCommand "logos-${config.name}-derived-lidl" {
          nativeBuildInputs = [ rustGen ];
        } ''
          mkdir -p $out
          logos-lidl-gen --from-rust "${rustCrateDir}/${rustSource}" \
            --trait ${rustTrait} --module-name ${config.name} --module-version ${config.version} \
            -o "$out/${config.name}.lidl"
        '';

      # The .lidl the generators consume: the derived one (rust-first) or the
      # committed codegen.lidl (contract-first).
      rustLidlPath =
        if rustDeriveMode then "${derivedLidl}/${config.name}.lidl"
        else "${src}/${config.codegen.lidl}";

      rustScaffold =
        if !isRustModule then null
        else pkgs.runCommand "logos-${config.name}-rust-scaffold" {
          nativeBuildInputs = [ rustGen ];
        } ''
          mkdir -p $out
          logos-lidl-gen "${rustLidlPath}" --provider ${lib.optionalString rustDeriveMode "--no-trait"} \
            ${lib.optionalString ((config.concurrency or "single") == "multi") "--concurrency multi"} ${rustDepFlags} \
            ${lib.optionalString (protocolVersion != null) "--protocol-version ${protocolVersion}"} \
            -o "$out/provider_gen.rs"
        '';

      # Rust-first only: stage the derived .lidl into generated_code/ BEFORE the
      # Qt-glue codegen runs — that's where cdylibCodegen reads it for a rust-first
      # module (so no codegen.lidl is needed in metadata; the builder owns the
      # path). Empty for contract-first, where the .lidl is committed.
      lidlStaging = lib.optionalString rustDeriveMode ''
        mkdir -p generated_code
        cp ${derivedLidl}/${config.name}.lidl generated_code/${config.name}.lidl
      '';

      # The crate source laid out for the build: the crate under rust-lib/ (with
      # the generated scaffold injected at generated/provider_gen.rs) and the
      # builder's logos-rust-sdk source alongside it, so the crate's
      # `logos-rust-sdk = { path = "../logos-rust-sdk-src" }` dep resolves against
      # the SAME rev the generator came from. The author crate carries only the
      # trait impl + hook — no build.rs, no OUT_DIR.
      rustCrateSrc =
        if !isRustModule then null
        else pkgs.runCommand "logos-${config.name}-rust-src" {} ''
          mkdir -p $out
          cp -r ${rustCrateDir} $out/rust-lib
          chmod -R u+w $out/rust-lib
          mkdir -p $out/rust-lib/generated
          cp ${rustScaffold}/provider_gen.rs $out/rust-lib/generated/provider_gen.rs
          cp -r ${rustSdk} $out/logos-rust-sdk-src
        '';

      rustStaticLib =
        if !isRustModule then null
        else pkgs.rustPlatform.buildRustPackage {
          pname = rustStaticName;
          version = config.version;
          src = rustCrateSrc;
          sourceRoot = "logos-${config.name}-rust-src/rust-lib";
          cargoLock = {
            lockFile = "${rustCrateDir}/Cargo.lock";
            allowBuiltinFetchGit = true;
          };
          # External system build deps for the crate compile — from metadata
          # `nix.rust` plus the programmatic escape-hatch args. Empty by default,
          # so modules with no native deps build exactly as before.
          nativeBuildInputs = rustNativeBuildPkgs ++ rustExtraNativeBuildInputs;
          buildInputs = rustBuildPkgs ++ rustExtraBuildInputs;
          env = config.nix_rust.env // rustEnv;
          doCheck = false;
        };

      # Stage the compiled staticlib where LogosModule.cmake's
      # LOGOS_MODULE_RUST_STATIC_LIBS block finds it (the plugin build's lib/).
      rustStaging = lib.optionalString isRustModule ''
        mkdir -p lib
        cp ${rustStaticLib}/lib/lib${rustStaticName}.a lib/
      '';


      # Backend arguments for a given external-lib variant ("default" or
      # "portable"). Shared by buildVariant (compiles the plugin) and the
      # generate output (snapshots the post-codegen source tree) so both use the
      # identical preConfigure / deps / env.
      mkPluginArgs = variant:
        let
          externalLibs =
            if variant == "default" then defaultExternalLibs
            else mkExternalLib.buildExternalLibs {
              inherit pkgs config src;
              externalInputs = lib.mapAttrs (resolveExtInput variant) externalLibInputs;
            };

          # rustStaging (empty for non-Rust modules) drops the compiled Rust
          # staticlib into lib/ before cmake, where the LOGOS_MODULE_RUST_STATIC_LIBS
          # block links it — the builder-driven replacement for the per-flake
          # buildRustPackage + cp the author used to write by hand.
          userPreConfigure =
            rustStaging + (
              if builtins.isFunction preConfigure
              then preConfigure { inherit externalLibs; }
              else preConfigure);

          preConfigureStr = modulePreConfigure.compose {
            inherit config externalLibs protocolVersion;
            userPre = userPreConfigure;
            # Stage the rust-first derived .lidl before the glue codegen reads it.
            preCodegen = lidlStaging;
            fixDarwin = false;
            # logos-plugin-qt buildPlugin already stages external libs into lib/
            copyExternals = false;
          };

          goCmakeFlags = lib.optionals (config.go_static_lib_names != []) [
            "-DLOGOS_MODULE_GO_STATIC_LIBS=${lib.concatStringsSep ";" config.go_static_lib_names}"
          ];

          # LOGOS_API_STYLE forwards through to logos-cpp-generator and
          # picks which type surface the generated <Module> client wrappers
          # (and the umbrella LogosModules struct) expose. Mirrors the
          # backend's apiStyle (logos-plugin-qt buildPlugin.nix): core
          # universal modules are header-first cdylibs → Qt-free lp_* wrappers.
          # UI universal backends (type: ui_qml) are NOT modules — they derive a
          # Qt SimpleSource whose .rep slots are Qt-typed, so their
          # LogosUiPluginContext.modules() dep wrappers are Qt-typed too (the
          # generator default — no flag). Every other interface keeps qt.
          # (Only consulted in the source layout; nix builds get apiStyle from
          # the backend's --general-only call.)
          apiStyleCmakeFlags =
            if config.interface == "universal" && (config.type or "core") != "ui_qml"
            then [ "-DLOGOS_API_STYLE=lp" ]
            else [];
        # The backend only knows about Qt + logosModule (interface.h).
        # SDK (generator, lib, headers) is injected via extra* args.
        in ({
          inherit pkgs src config postInstall logosModule;
          preConfigure = preConfigureStr;
          moduleDeps = resolvedModuleDeps;
          inherit externalLibs;
          extraNativeBuildInputs = extraNativeBuildInputs ++ buildPkgs ++ [ logosSdk logosQtGenerator pkgs.jq ];
          extraBuildInputs = extraBuildInputs ++ runtimePkgs ++ [ logosQtSdk logosProtocolPkg ];
          extraCmakeFlags = [
            "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
            "-DLOGOS_QT_SDK_ROOT=${logosQtSdk}"
            "-DLOGOS_PROTOCOL_ROOT=${logosProtocolPkg}"
          ] ++ goCmakeFlags ++ apiStyleCmakeFlags
            ++ lib.optionals isRustModule [ "-DLOGOS_MODULE_RUST_STATIC_LIBS=${rustStaticName}" ];
          extraEnv = {
            LOGOS_CPP_SDK_ROOT = "${logosSdk}";
            LOGOS_QT_SDK_ROOT = "${logosQtSdk}";
            LOGOS_PROTOCOL_ROOT = "${logosProtocolPkg}";
          } // lib.optionalAttrs hasBuilderCmake {
            LOGOS_MODULE_BUILDER_ROOT = "${builderRoot}";
          };
        }
        # Only pass interfaceDeps when the module declares any — keeps existing
        # dependency-only modules buildable against a backend that predates the
        # interface-dependencies feature (graceful degradation). A Rust module's
        # deps ALSO feed the Rust generator (rustDepFlags) for the typed
        # modules()/bind() it actually calls; they still go to the C++ backend
        # too so the generated umbrella (logos_sdk.h, emitted from
        # metadata.dependencies) finds each dep's api header and compiles.
        // lib.optionalAttrs (config.interface_dependencies != []) {
          interfaceDeps = resolvedInterfaceDeps;
        }
        # LIDL-based concrete deps → `--dep` flags (generate from the dep's
        # published LIDL, no dep plugin build). Gated so a backend that predates
        # this feature still builds (such deps then fall through unresolved).
        // lib.optionalAttrs (staticDeps != []) {
          inherit staticDeps;
        });

      # Compile the plugin for a variant (delegated to the backend).
      buildVariant = variant: selectedBackend.buildPlugin (mkPluginArgs variant);

      moduleLib = buildVariant "default";
      moduleLibPortable = if hasVariants then buildVariant "portable" else null;

      # Ready-to-build source tree: the backend runs every generator the build
      # runs, then snapshots the result (module source + generated_code/) instead
      # of compiling. Same args as the default plugin build, so the emitted tree
      # is exactly what a real build generates. Built from the module's
      # `nix develop` shell (which exports LOGOS_*_ROOT) without re-running codegen.
      moduleGenerate = selectedBackend.generate (mkPluginArgs "default");

      # Three header variants per module — Qt-typed, std-typed, and lp
      # (Qt-free, logos-protocol C ABI). Each is its own Nix derivation, so a
      # downstream module only realises the one its `--api-style` actually
      # consumes. The lp variant lets a core universal (header-first cdylib)
      # module copy a Qt-free typed wrapper for a LEGACY dependency that
      # publishes no `.lidl` (the wrapper is generated by introspecting the
      # dep's built plugin, so it works regardless of how the dep was
      # authored). Default output (`include`) stays the Qt variant for
      # backward compatibility with consumers that read `${dep}/include`.
      moduleIncludeQt = selectedBackend.buildHeaders {
        inherit pkgs src config logosSdk;
        pluginLib = moduleLib;
        apiStyle = "qt";
      };
      moduleIncludeStd = selectedBackend.buildHeaders {
        inherit pkgs src config logosSdk;
        pluginLib = moduleLib;
        apiStyle = "std";
      };
      moduleIncludeLp = selectedBackend.buildHeaders {
        inherit pkgs src config logosSdk;
        pluginLib = moduleLib;
        apiStyle = "lp";
      };

      # Publish this module's interface as LIDL — the language-neutral contract
      # a consumer turns into typed `modules().<name>` bindings WITHOUT building
      # this module's plugin (source → LIDL → C++). Cheap: runs only the C++
      # frontend (`--header-to-lidl`) over the impl header; no Qt/plugin compile.
      # Produced for universal modules; the impl header + class come from the
      # same convention `universalCodegen` uses (`codegen.impl_*` or defaults).
      lidlImplClass = config.codegen.impl_class or (modulePreConfigure.defaultImplClassFromName config.name);
      lidlIhRaw = config.codegen.impl_header or "${config.name}_impl.h";
      lidlImplHeaderRel = if lib.hasInfix "/" lidlIhRaw then lidlIhRaw else "src/${lidlIhRaw}";
      moduleLidl =
        if config.interface == "universal"
        then pkgs.runCommand "logos-${config.name}-lidl" {
               nativeBuildInputs = [ logosSdk ];
             } ''
               mkdir -p $out
               logos-cpp-generator --header-to-lidl "${src}/${lidlImplHeaderRel}" \
                 --impl-class "${lidlImplClass}" \
                 --metadata "${configFile}" \
                 -o "$out/${config.name}.lidl"
             ''
        # Cdylib modules publish their .lidl as the interface (whether the impl
        # is Rust or C++), so consumers generate typed bindings from it like for
        # any other dep. Contract-first modules copy the committed file; a
        # rust-first module publishes the .lidl DERIVED from its trait.
        else if rustDeriveMode
        then pkgs.runCommand "logos-${config.name}-lidl" {} ''
               mkdir -p $out
               cp "${derivedLidl}/${config.name}.lidl" "$out/${config.name}.lidl"
             ''
        else if config.interface == "cdylib" && config.codegen ? lidl
        then pkgs.runCommand "logos-${config.name}-lidl" {} ''
               mkdir -p $out
               cp "${src}/${config.codegen.lidl}" "$out/${config.name}.lidl"
             ''
        else null;

      # Combined package — copies the Qt-typed headers (backward
      # compat). The `//` merge exposes src + version on the derivation
      # so downstream bundlers (nix-bundle-lgx) can locate metadata.json.
      combined = (pkgs.runCommand "logos-${config.name}-module" {} ''
        mkdir -p $out/lib $out/include

        # Copy library files (not symlinks)
        if [ -d "${moduleLib}/lib" ]; then
          cp -rL ${moduleLib}/lib/* $out/lib/
        fi

        # Copy include files (not symlinks) — use find to avoid nullglob issues
        if [ -d "${moduleIncludeQt}/include" ] && [ -n "$(find ${moduleIncludeQt}/include -maxdepth 1 -not -name '.*' -not -path ${moduleIncludeQt}/include -print -quit)" ]; then
          cp -rL ${moduleIncludeQt}/include/* $out/include/
        fi
      '') // { inherit src; version = config.version; };

    in {
      # Individual outputs (e.g., nix build .#chat-lib)
      "${config.name}-lib" = moduleLib;
      "${config.name}-include" = moduleIncludeQt;
      "${config.name}-headers-qt"  = moduleIncludeQt;
      "${config.name}-headers-std" = moduleIncludeStd;
      "${config.name}-headers-lp"  = moduleIncludeLp;

      # Short aliases (e.g., nix build .#lib)
      lib = moduleLib;
      include = moduleIncludeQt;
      headers-qt  = moduleIncludeQt;
      headers-std = moduleIncludeStd;
      headers-lp  = moduleIncludeLp;

      # Default package - combined lib + include (nix build)
      default = combined;

      # Ready-to-build codebase: all code generators run, emitted as a source
      # tree (nix build .#generate). Build it from `nix develop` — no generator
      # re-runs (LogosModule.cmake consumes the pre-populated generated_code/).
      generate = moduleGenerate;
      "${config.name}-generate" = moduleGenerate;
    } // lib.optionalAttrs (moduleLibPortable != null) {
      "${config.name}-lib-portable" = moduleLibPortable;
      lib-portable = moduleLibPortable;
    } // lib.optionalAttrs (moduleLidl != null) {
      # Published LIDL contract — consumers generate bindings from this without
      # building the plugin. Cheap (frontend only). Absent for non-universal
      # modules, so consumers fall back to the header-copy path for those.
      "${config.name}-lidl" = moduleLidl;
      lidl = moduleLidl;
    }
  );

  # Development shell (delegates to backend for deps)
  devShells = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      logosQtSdk = logos-qt-sdk.packages.${system}.default;
      # The Qt glue generator (universal/cdylib/ui backends) — Qt code is
      # the Qt layer's product; logos-cpp-generator keeps Qt-free outputs.
      logosQtGenerator = logos-qt-sdk.packages.${system}.logos-qt-generator;
      logosProtocolPkg = logos-protocol.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;

      # The logos-protocol semver — parsed from the protocol header the
      # whole stack links. Stamped into every module's embedded metadata
      # (see modulePreConfigure.stampProtocolVersion). null (no stamp) only
      # if the input is somehow absent — modules then load as "legacy".
      protocolVersion =
        if logos-protocol == null then null
        else
          let
            header = builtins.readFile "${logos-protocol}/cpp/logos_protocol.h";
            parts = builtins.split "LOGOS_PROTOCOL_VERSION_STRING \"([^\"]*)\"" header;
          in if builtins.length parts < 2 then null
             else builtins.head (builtins.elemAt parts 1);

      backendShell = selectedBackend.devShellInputs pkgs { inherit logosModule; };
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;

      # Resolve external lib inputs for this system so we can point cmake directly
      # at their Nix store paths via LOGOS_EXT_ROOT_<NAME>, skipping the ./lib/ staging copy.
      resolveExtInputDev = name: value:
        if builtins.isAttrs value && value ? input then
          let pkgName = (value.packages or {}).default or "default";
          in value.input.packages.${system}.${pkgName} or null
        else
          value.packages.${system}.default or value;
      devExternalLibs = lib.filterAttrs (_: v: v != null && lib.isDerivation v)
        (lib.mapAttrs resolveExtInputDev externalLibInputs);
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = backendShell.nativeBuildInputs ++ buildPkgs ++ [ logosSdk ];
        buildInputs = backendShell.buildInputs ++ runtimePkgs ++ lib.attrValues devExternalLibs;
        shellHook = ''
          ${backendShell.shellHook}
          export LOGOS_CPP_SDK_ROOT="${logosSdk}"
          export LOGOS_QT_SDK_ROOT="${logos-qt-sdk.packages.${system}.default}"
          export LOGOS_PROTOCOL_ROOT="${logos-protocol.packages.${system}.default}"
          ${lib.optionalString hasBuilderCmake ''export LOGOS_MODULE_BUILDER_ROOT="${builderRoot}"''}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: drv: ''
            export LOGOS_EXT_ROOT_${lib.toUpper name}="${drv}"
          '') devExternalLibs)}
          echo "Logos ${config.name} module development environment"
          echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
          echo "LOGOS_MODULE_ROOT: $LOGOS_MODULE_ROOT"
          echo "LOGOS_MODULE_BUILDER_ROOT: $LOGOS_MODULE_BUILDER_ROOT"
        '';
      };
    }
  );

  # LGX package outputs (nix-bundle-lgx provided by the builder)
  nixBundleLgx = nix-bundle-lgx;

  optionalLgx =
    {
      packages = forAllSystems (system:
        let
          bundleLgx = nixBundleLgx.bundlers.${system}.default;
          bundleLgxPortable = nixBundleLgx.bundlers.${system}.portable;
          installDev = nix-bundle-logos-module-install.bundlers.${system}.dev;
          installPortable = nix-bundle-logos-module-install.bundlers.${system}.portable;
          moduleLib = packages.${system}.lib;
          # Use the portable-linked plugin for lgx-portable when available
          moduleLibForPortable =
            packages.${system}.lib-portable or moduleLib;
        in {
          lgx = bundleLgx moduleLib;
          install = installDev moduleLib;
          lgx-portable = bundleLgxPortable moduleLibForPortable;
          install-portable = installPortable moduleLibForPortable;
        }
      );
    };

  # Resolve the standalone app: explicit override > built-in from module-builder
  resolvedStandalone =
    if logosStandalone != null then logosStandalone
    else if config.type == "ui" then logos-standalone-app
    else null;

  optionalApps =
    if resolvedStandalone == null then {}
    else {
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # Collect all module dependencies (direct + transitive) for bundling
          allDeps = common.collectAllModuleDeps system flakeInputs config.dependencies;
        in {
          default = mkStandaloneApp {
            inherit pkgs;
            standalone   = resolvedStandalone.packages.${system}.default;
            plugin       = packages.${system}.default;
            metadataFile = configFile;
            dirName      = "logos-${config.name}-plugin-dir";
            format       = "qt-plugin";
            moduleDeps   = allDeps;
          };
        }
      );
    };

  # Merge LGX outputs into packages
  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (optionalLgx.packages.${system} or {})
  ) packages;

  # Build unit tests — explicit config wins, otherwise auto-detect tests/CMakeLists.txt
  mkTests = import ./mkLogosModuleTests.nix {
    inherit nixpkgs lib common parseMetadata;
    inherit logos-cpp-sdk logos-protocol logos-qt-sdk;
    logos-test-framework = logos-test-framework;
  };

  resolvedTests =
    if tests != null then tests
    else if builtins.pathExists (src + "/tests/CMakeLists.txt") then {
      dir = src + "/tests";
    }
    else null;

  testChecks =
    if resolvedTests == null then {}
    else mkTests {
      inherit src flakeInputs externalLibInputs;
      configFile = configFile;
      testDir = resolvedTests.dir;
      mockCLibs = resolvedTests.mockCLibs or [];
      preConfigure = resolvedTests.preConfigure or preConfigure;
      extraBuildInputs = resolvedTests.extraBuildInputs or [];
      extraCmakeFlags = resolvedTests.extraCmakeFlags or [];
    };

  optionalTests =
    if testChecks == {} then {}
    else { checks = testChecks; };

  # Also expose unit-tests as a package so `nix build .#unit-tests` works
  testPackages =
    if testChecks == {} then {}
    else lib.mapAttrs (_system: sysChecks:
      { unit-tests = sysChecks.unit-tests; }
    ) testChecks;

  finalPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (testPackages.${system} or {})
  ) mergedPackages;

in {
  packages = finalPackages;
  inherit devShells config;
  metadataJson = builtins.readFile configFile;
} // optionalApps // optionalTests
