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
      dependencies = safeList (raw.dependencies or []);
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

      # Module API style: "legacy" (default), "universal" (pure C++ + generated Qt glue),
      # "provider" (LOGOS_METHOD + logos-cpp-generator --provider-header)
      interface = raw.interface or "legacy";

      # Optional codegen overrides (see docs); only used when interface is universal/provider
      codegen = raw.codegen or {};

      # Names of external_libraries entries built with go_build (for CMake whole-archive link flags)
      go_static_lib_names = map (x: x.name) (lib.filter (x: x ? go_build && x.go_build == true)
        (safeList (nix.external_libraries or [])));

      _raw = raw;
    };
}
