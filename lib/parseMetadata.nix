# Parse metadata.json as the single source of truth for a module.
# Runtime fields (name, type, dependencies, icon, main…) live at the top level
# and are read by Qt, logos-standalone-app, the nix bundler and the Nix build system.
# Nix/build-only fields live under the "nix" key and are ignored at runtime.
{ lib }:

{
  parseModuleConfig = jsonContent:
    let
      raw = builtins.fromJSON jsonContent;
      nix = raw.nix or {};
      safeList = val: if builtins.isList val then val else [];

      # The two fields the consumer axis below turns on, hoisted so the
      # attrset's own `interface` / `type` and the derivation of
      # `consumer_api_style` cannot drift apart (this set is not `rec`).
      moduleName_ = raw.name or "?";
      type_       = raw.type or "core";
      interface_  = raw.interface or "legacy";
      codegen_    = let c = raw.codegen or {}; in if builtins.isAttrs c then c else {};

      # ── Is this module's own image a cdylib PROVIDER? ─────────────────────
      #
      # True exactly when modulePreConfigure.autoCodegen gives the module the
      # module-impl C ABI export surface (logos_module_impl.h) in the SAME
      # image its generated consumer wrappers are compiled into:
      #
      #   interface "cdylib"                       -> cdylibCodegen
      #   interface "universal", type != "ui_qml"  -> universalCodegen
      #                                               (a header-first cdylib)
      #
      # and false for the two shapes that are Qt PLUGIN objects holding a
      # LogosAPI: `interface: "legacy"` (handcrafted Qt) and
      # `interface: "universal"` + `type: "ui_qml"` (a view backend, which is
      # not a module — uiCodegen emits only the view glue).
      #
      # This predicate is deliberately the SAME expression autoCodegen
      # branches on, because the thing it decides is where this image's auth
      # TOKENS come from:
      #
      #   cdylib   — `logos_module_accept_token` -> `lp_token_save`, straight
      #              into the TokenManager this image's outbound lp client
      #              reads (logos-cpp-sdk lidl_gen_cdylib.cpp; the Rust
      #              equivalent in logos-rust-sdk rustgen_provider.rs). A
      #              consumer wrapper here needs NO LogosAPI.
      #   Qt plugin — the host writes to the TokenManager in ITS image; the
      #              plugin links its own copy of the protocol library, so the
      #              tokens have to be MIRRORED across
      #              (logos::qt::LpBridge::syncTokens, reached only via
      #              `forTarget(api, ...)`). A consumer wrapper here that holds
      #              no LogosAPI authenticates as nobody, and the call comes
      #              back as a default value with no error raised.
      packagedAsCdylib_ =
        interface_ == "cdylib"
        || (interface_ == "universal" && type_ != "ui_qml");

      # ── codegen.consumer_api_style: "qt" | "lp" ───────────────────────────
      #
      # Which TYPE SURFACE this module's generated dependency wrappers expose
      # (`modules().<dep>` and the LogosModules umbrella). Independent of the
      # module's own PROVIDER surface, which `interface` alone decides.
      #
      # The default is exactly the value the build derived before this key
      # existed (logos-plugin-qt buildPlugin.nix's `apiStyle`), so an existing
      # metadata.json produces a byte-identical build.
      #
      # Only ONE override is reachable, and `packagedAsCdylib_` is why:
      #
      #   cdylib + "qt"  — ALLOWED, and the point of this key. The wrappers
      #     come out Qt-typed and origin-bound (`--binding origin`): they hold
      #     no LogosAPI and state this module's own name as the call origin.
      #     Correct here precisely because tokens arrive over the C ABI.
      #   Qt plugin + "lp" — REFUSED below. The lp wrappers hold no LogosAPI
      #     either, and in a Qt plugin image nothing would ever populate the
      #     TokenManager they read.
      consumerApiStyleDerived_ = if packagedAsCdylib_ then "lp" else "qt";
      consumerApiStyleDeclared_ = codegen_.consumer_api_style or null;
      consumerApiStyle_ =
        if consumerApiStyleDeclared_ == null then consumerApiStyleDerived_
        else if !(builtins.isString consumerApiStyleDeclared_)
                || !(builtins.elem consumerApiStyleDeclared_ [ "qt" "lp" ]) then
          throw ("metadata.json: module '${moduleName_}' sets codegen.consumer_api_style = "
                 + "${builtins.toJSON consumerApiStyleDeclared_}. Valid values are \"qt\" "
                 + "(Qt-typed dependency wrappers) and \"lp\" (Qt-free, the logos-protocol "
                 + "C ABI). Omit the key to get this module's default (\"${consumerApiStyleDerived_}\").")
        else if consumerApiStyleDeclared_ == "lp" && !packagedAsCdylib_ then
          throw ''
            metadata.json: module '${moduleName_}' sets codegen.consumer_api_style = "lp",
            which is only available to a module packaged as a cdylib provider.

            This module declares interface "${interface_}" with type "${type_}", so its
            generated dependency wrappers are compiled into a Qt PLUGIN object that holds a
            LogosAPI and exports no `logos_module_accept_token`. The lp wrappers call the
            logos-protocol C ABI directly and hold no LogosAPI, so NOTHING would populate the
            TokenManager they read: every outbound call would present an empty auth token,
            capability_module would refuse to mint a per-target token, and the call would
            return a default value with no error surfaced. That is the exact defect
            `logos::qt::LpBridge::syncTokens` exists to prevent — which is why the two
            consumer surfaces are not freely interchangeable.

            Reachable values for this module: "qt" (its default; omit the key).

            To get the Qt-free consumer surface, make the module a cdylib provider —
            `interface: "universal"` (write a plain src/${moduleName_}_impl.h and the contract
            is derived from it) or `interface: "cdylib"`.
          ''
        else consumerApiStyleDeclared_;
    in {
      # Runtime fields
      name        = raw.name        or (throw "metadata.json must specify 'name'");
      version     = raw.version     or "1.0.0";
      type        = type_;
      category    = raw.category    or "general";
      description = raw.description or "A Logos module";
      main        = raw.main        or null;
      icon        = raw.icon        or null;
      view        = raw.view        or null;
      # Concrete module dependencies, as a list of NAME strings. Entries may be
      # bare strings (the common form) or objects `{ name, ... }`; either way we
      # keep just the name here so every existing consumer of `config.dependencies`
      # (the umbrella, collectAllModuleDeps, the header-copy fallback) is unchanged.
      dependencies = map (e:
        if builtins.isString e then e
        else (e.name or (throw "dependencies entry must be a string name or { name, ... }, got: ${builtins.toJSON e}"))
      ) (safeList (raw.dependencies or []));
      include      = safeList (raw.include      or []);

      # Interface dependencies — method/event contracts decoupled from any
      # concrete module. The consumer binds an interface to a module name at
      # runtime (modules().bind_<name>("some_module")). Each entry:
      #   { name, file, input?, impl_class? }
      #   name       — interface identifier → bound wrapper class + bind_<name>
      #   file       — path to the .lidl/.h definition. For a local interface,
      #                relative to this repo root; for a remote one, relative
      #                to the flake input named by `input`.
      #   input      — (optional) flake-input attr name hosting the interface,
      #                mirroring how `dependencies` map to flake inputs. Absent
      #                ⇒ local file in this repo.
      #   impl_class — (required for .h definitions) the C++ class whose public
      #                methods + logos_events: define the interface.
      interface_dependencies = map (e:
        let
          # Reject non-object entries with a clear message rather than the
          # low-level "is not an attribute set" error that `e.file` would
          # otherwise raise on a bare string / list element.
          _ok = if builtins.isAttrs e then true
                else throw "interface_dependencies entries must be objects like { name, file, impl_class?, input? }, got: ${builtins.toJSON e}";
          file = if _ok then (e.file or (throw "interface_dependencies entry '${e.name or "?"}' must specify 'file'")) else null;
          implClass = e.impl_class or null;
          isHeader = lib.hasSuffix ".h" file || lib.hasSuffix ".hpp" file;
        in
          if isHeader && implClass == null
          then throw "interface_dependencies entry '${e.name or file}' is a C++ header (${file}) and must specify 'impl_class'"
          else {
            name       = e.name or (throw "interface_dependencies entry must specify 'name'");
            inherit file;
            input      = e.input or null;
            impl_class = implClass;
          }
      ) (safeList (raw.interface_dependencies or []));

      # Optional per-dependency LIDL-source overrides. Normally a dependency's
      # interface LIDL is auto-resolved from its `packages.<sys>.lidl` flake
      # output (no plugin build); an override forces a specific definition —
      # e.g. a committed `.lidl`, a header in another input, or pinning to the
      # old header-copy path. Keyed by dependency name → { file, input?, impl_class? }:
      #   file       — path to the .lidl/.h. Relative to this repo (no `input`)
      #                or to the named flake input.
      #   input      — (optional) flake-input attr name hosting the file.
      #   impl_class — (required for a .h file) the class whose API defines the dep.
      dependency_overrides = lib.mapAttrs (name: ov:
        let
          file = ov.file or (throw "dependency_overrides.${name} must specify 'file'");
          implClass = ov.impl_class or null;
          isHeader = lib.hasSuffix ".h" file || lib.hasSuffix ".hpp" file;
        in
          if isHeader && implClass == null
          then throw "dependency_overrides.${name} is a C++ header (${file}) and must specify 'impl_class'"
          else { inherit file; input = ov.input or null; impl_class = implClass; }
      ) (if builtins.isAttrs (raw.dependency_overrides or {}) then (raw.dependency_overrides or {}) else {});

      # Nix/build-only fields (nested under "nix" in metadata.json)
      nix_packages = {
        build   = safeList ((nix.packages or {}).build   or []);
        runtime = safeList ((nix.packages or {}).runtime or []);
      };
      external_libraries = safeList (nix.external_libraries or []);
      cmake = {
        find_packages      = safeList ((nix.cmake or {}).find_packages      or []);
        extra_sources      = safeList ((nix.cmake or {}).extra_sources      or []);
        extra_include_dirs = safeList ((nix.cmake or {}).extra_include_dirs or []);
        extra_link_libraries = safeList ((nix.cmake or {}).extra_link_libraries or []);
      };

      # Rust crate build inputs (nested under "nix.rust" in metadata.json). Fed to
      # the buildRustPackage that compiles a cdylib module's crate (mkLogosModule
      # rustStaticLib), NOT the C++ plugin link (that's nix.packages):
      #   packages.build   -> nativeBuildInputs (host tools: pkg-config, protoc,
      #                       perl, rustPlatform.bindgenHook)
      #   packages.runtime -> buildInputs       (link libs: openssl, sqlite, zstd)
      #   env              -> buildRustPackage env (flag-style vars)
      # Names resolve via getPkg (dotted nixpkgs paths). Empty by default, so
      # non-Rust modules and Rust modules without native deps are unaffected.
      nix_rust = {
        packages = {
          build   = safeList (((nix.rust or {}).packages or {}).build   or []);
          runtime = safeList (((nix.rust or {}).packages or {}).runtime or []);
        };
        env = let e = (nix.rust or {}).env or {}; in if builtins.isAttrs e then e else {};
        # Optional stable rustc version (e.g. "1.96.0") for the crate compile.
        # When set, the builder uses a rust-overlay toolchain at that version
        # instead of the pinned nixpkgs rustc — for modules whose deps need a
        # newer rustc than the workspace nixpkgs ships (e.g. the railgun engine's
        # alloy 1.8 / ruint). null (default) = unchanged, uses nixpkgs rustc.
        toolchain = let t = (nix.rust or {}).toolchain or null; in if builtins.isString t then t else null;
      };

      # Module API style: "legacy" (default), "universal" (pure C++ + generated
      # Qt glue), "cdylib" (module-impl C ABI + generated glue).
      # "provider" was removed; autoCodegen throws if a module still declares it.
      interface = interface_;

      # Where this module's generated consumer wrappers get compiled, as a
      # boolean the backends can consult without re-deriving it: true = into
      # the cdylib provider image (tokens arrive over the module-impl C ABI),
      # false = into a Qt plugin object holding a LogosAPI (tokens have to be
      # mirrored). Derived in the `let` above, next to the reasoning.
      packaged_as_cdylib = packagedAsCdylib_;

      # The resolved consumer type surface ("qt" | "lp") — the default derived
      # from `packaged_as_cdylib`, or the validated `codegen.consumer_api_style`
      # override. See the `let` above for the one override that is reachable
      # and why the other is refused there rather than at compile time.
      consumer_api_style = consumerApiStyle_;

      # Privileged host services this module asks the host to grant it, from a
      # CLOSED set. Parsed and validated here, unlike the older decorative
      # `capabilities` field which nothing in this file reads — a security
      # decision must not ride on a key that is never looked at.
      #
      #   "token_registry"  — enumerate the token store (lp_token_keys)
      #   "token_delivery"  — push a token to an arbitrary target
      #                       (lp_inform_module_token_to)
      #
      # Both are TRUST-ROOT services: capability_module's job, and a module
      # holding them can hand out authority. They are additionally restricted to
      # an allowlist of module names below.
      #
      # `dynamic_calls` USED TO BE LISTED HERE and is not a service at all. It
      # gated nothing, and could not: the by-name path (lp_client_create /
      # lp_invoke, and logos::LpClient above it) is ungated at every layer, so a
      # module could always make dynamic calls without asking. What the
      # declaration actually did was BREAK the asking module — hostServiceBit
      # (logos_protocol.cpp:109-111) knows only the two names above, and
      # lp_grant_host_services returns LP_ERR_INVALID_ARG on the first entry it
      # does not recognise (:695-702), failing the WHOLE grant. So a module that
      # asked for dynamic_calls alongside a real service silently lost the real
      # one. Removed rather than made inert, so asking is a build error instead.
      # The supported surface for by-name calls is LogosModules::dynamic(target)
      # plus LpClient::getMethods(), which need no grant.
      #
      # This declaration is ADVISORY. The authority is the host's grant, pushed
      # into the module's own image over the module-impl C ABI; an ungranted
      # module gets LP_ERR_UNSUPPORTED however loudly its metadata asks.
      host_services =
        let
          declared = safeList (raw.host_services or []);
          known = [ "token_registry" "token_delivery" ];
          trustRoot = [ "token_registry" "token_delivery" ];
          # Only capability_module may ask for a trust-root service. Hardcoded
          # rather than configurable: a build-time allowlist that a module could
          # extend from its own metadata would not be an allowlist.
          privilegedModules = [ "capability_module" ];
          checkKnown = svc:
            if !(builtins.isString svc) then
              throw ("host_services entries must be strings, got: ${builtins.toJSON svc}")
            else if !(builtins.elem svc known) then
              throw ("metadata.json: unknown host service '${svc}' in module "
                     + "'${raw.name or "?"}'. Known services: "
                     + builtins.concatStringsSep ", " known
                     + ". An unrecognised name means the module believes it holds a "
                     + "privilege that does not exist, so the whole declaration is refused.")
            else if builtins.elem svc trustRoot
                    && !(builtins.elem (raw.name or "") privilegedModules) then
              throw ("metadata.json: module '${raw.name or "?"}' asks for the trust-root "
                     + "host service '${svc}', which is restricted to: "
                     + builtins.concatStringsSep ", " privilegedModules
                     + ". A module needing to call another module should declare it as a "
                     + "dependency; token_registry/token_delivery hand out authority.")
            else svc;
        in map checkKnown declared;

      # Concurrent dispatch mode (parallel to `interface`):
      #   "single" (default) — today's event-loop semantics: every call to this
      #     module is dispatched serially on one thread, so the author needs no
      #     thread-safety. This stays the default forever (even post-Qt).
      #   "multi" — the generated dispatch runs handlers concurrently on a worker
      #     pool; the author owns thread-safety (interior mutability / mutexes on
      #     their own state). Realized transport-agnostically by the codegen + the
      #     protocol's async dispatch path (a blocking handler no longer stalls
      #     other callers of the same module).
      concurrency = raw.concurrency or "single";
      # Optional worker-pool cap for a "multi" module; null ⇒ the runtime sizes the
      # pool to available parallelism (capped). Ignored for "single".
      max_workers = if raw ? max_workers then raw.max_workers else null;

      # Optional codegen overrides (see docs); read for interface universal/cdylib
      # (and by the ui_qml backend, for codegen.rep). The removed `provider`
      # interface used to be the other consumer.
      codegen = raw.codegen or {};

      # Names of external_libraries entries built with go_build (for CMake whole-archive link flags)
      go_static_lib_names = map (x: x.name) (lib.filter (x: x ? go_build && x.go_build == true)
        (safeList (nix.external_libraries or [])));

      _raw = raw;
    };
}
