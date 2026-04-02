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
