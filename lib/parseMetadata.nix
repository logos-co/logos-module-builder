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
    in {
      # Runtime fields
      name        = raw.name        or (throw "metadata.json must specify 'name'");
      version     = raw.version     or "1.0.0";
      type        = raw.type        or "core";
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

      # Module API style: "legacy" (default), "universal" (pure C++ + generated Qt glue),
      # "provider" (LOGOS_METHOD + logos-cpp-generator --provider-header)
      interface = raw.interface or "legacy";

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

      # Optional codegen overrides (see docs); only used when interface is universal/provider
      codegen = raw.codegen or {};

      # Names of external_libraries entries built with go_build (for CMake whole-archive link flags)
      go_static_lib_names = map (x: x.name) (lib.filter (x: x ? go_build && x.go_build == true)
        (safeList (nix.external_libraries or [])));

      _raw = raw;
    };
}
