# Common utilities shared across all builder functions (backend-agnostic)
# Qt-specific build deps and cmake flags now live in the plugin backend.
{ lib, nix-bundle-lgx ? null, nixpkgs ? null, logos-nix ? null }:

let
  # Recursively collect all module dependencies (direct + transitive) from flake
  # inputs, using each module's exported config.dependencies to walk the tree.
  # Returns a flat attrset: { moduleName = lgxDerivation; ... }
  # Uses the LGX package output (packages.lgx) which bundles the plugin plus
  # any external libraries it depends on.  When a dependency lacks packages.lgx,
  # it is automatically bundled into an LGX package using nix-bundle-lgx.
  #
  # system:   target system string (e.g. "x86_64-linux")
  # inputs:   flake inputs attrset to search for dependency modules
  # depNames: list of dependency name strings to resolve
  collectAllModuleDeps = system: inputs: depNames:
    let
      depInputs = lib.filterAttrs (n: _: builtins.elem n depNames) inputs;

      # Bundle a derivation into LGX on the fly using nix-bundle-lgx.
      # Fails fast if nix-bundle-lgx is unavailable — a silent fallback would
      # cause mkStandaloneApp to silently omit the dependency at runtime.
      autoBundleLgx = drv:
        if nix-bundle-lgx == null then
          builtins.throw "collectAllModuleDeps: dependency lacks packages.${system}.lgx and nix-bundle-lgx is not available to auto-bundle it. Either add an lgx output to the dependency or ensure nix-bundle-lgx is passed to common.nix."
        else if !(nix-bundle-lgx ? bundlers.${system}.default) then
          builtins.throw "collectAllModuleDeps: nix-bundle-lgx does not provide a bundler for system ${system}."
        else
          nix-bundle-lgx.bundlers.${system}.default drv;

      direct = lib.mapAttrs (_: input:
        if input ? packages.${system}.lgx
        then input.packages.${system}.lgx
        else if input ? packages.${system}.lib
        then autoBundleLgx input.packages.${system}.lib
        else if input ? packages.${system}.default
        then autoBundleLgx input.packages.${system}.default
        else input
      ) depInputs;

      transitive = builtins.foldl' (acc: name:
        let
          input = depInputs.${name};
          tdeps = (input.config or {}).dependencies or [];
          tinputs = input.inputs or {};
        in
          if tdeps == [] then acc
          else acc // (collectAllModuleDeps system tinputs tdeps)
      ) {} (builtins.attrNames depInputs);
    in
      # direct overrides transitive so the closest (most specific) dep wins
      transitive // direct;

  # Supported target systems. "x86_64-windows" is a PSEUDO-system: a cross
  # derivation's `system` attribute is its BUILD platform, so this evaluates
  # anywhere but only realises on x86_64-linux.
  systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
    ++ lib.optional (logos-nix != null) "x86_64-windows";

  # THE package-set constructor. Every module's pkgs comes from here, which is
  # what lets ~40 modules target Windows without each re-deriving the cross
  # plumbing.
  #
  # x86_64-windows cannot be produced by `import nixpkgs { system = ...; }` --
  # it needs localSystem/crossSystem plus logos-nix's mingw overlays, which is
  # exactly what logos-nix.lib.mkWindowsPkgs wraps.
  mkPkgsWith = extraOverlays: system:
    if system != "x86_64-windows" then
      import nixpkgs { inherit system; overlays = extraOverlays; }
    else if logos-nix == null then
      throw ("logos-module-builder: targeting x86_64-windows requires the "
             + "logos-nix input to be threaded into the builder lib.")
    else if extraOverlays != [ ] then
      # Rather than silently drop them and hand back a package set that is not
      # what the caller asked for. mkWindowsPkgs owns its overlay list (the
      # mingw cross fixes); teach it to merge before removing this.
      throw ("logos-module-builder: overlays are not yet supported for the "
             + "x86_64-windows target (requested "
             + toString (builtins.length extraOverlays) + ").")
    else
      logos-nix.lib.mkWindowsPkgs { buildSystem = "x86_64-linux"; };

  mkPkgs = mkPkgsWith [ ];

  # The system a build for `target` actually RUNS on. Host TOOLS -- the code
  # generators, moc, repc -- must come from here, never from the target set:
  # under cross, `packages.x86_64-windows.logos-qt-generator` is a PE that the
  # Linux builder cannot execute ("logos-cpp-generator: command not found").
  # Identity for every native system, so callers need no isWindows test.
  buildSystemFor = target:
    if target == "x86_64-windows" then "x86_64-linux" else target;

  # Helper to run a function for all systems
  forAllSystems = _nixpkgs: f:
    lib.genAttrs systems (system: f {
      inherit system;
      pkgs = mkPkgs system;
    });

in {
  inherit systems mkPkgs mkPkgsWith forAllSystems buildSystemFor;

  inherit collectAllModuleDeps;



  # Determine library extension based on platform
  getLibExtension = pkgs:
    if pkgs.stdenv.hostPlatform.isDarwin then "dylib"
    else if pkgs.stdenv.hostPlatform.isWindows then "dll"
    else "so";

  # Get the library filename for a module
  getPluginFilename = pkgs: name:
    "${name}_plugin.${if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so"}";

  # Convert module name to various formats
  nameFormats = name: {
    # my_module -> my_module
    snake = name;
    # my_module -> MyModule
    pascal = lib.concatMapStrings (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s)
             (lib.splitString "_" name);
    # my_module -> myModule
    camel = let
      parts = lib.splitString "_" name;
      first = lib.head parts;
      rest = lib.tail parts;
    in first + lib.concatMapStrings (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) rest;
    # my_module -> MY_MODULE
    upper = lib.toUpper (lib.replaceStrings ["-"] ["_"] name);
  };

  # Merge two attribute sets recursively
  recursiveMerge = attrList:
    let
      f = attrPath:
        lib.zipAttrsWith (n: values:
          if lib.tail values == []
          then lib.head values
          else if lib.all lib.isList values
          then lib.unique (lib.concatLists values)
          else if lib.all lib.isAttrs values
          then f (attrPath ++ [n]) values
          else lib.last values
        );
    in f [] attrList;
}
