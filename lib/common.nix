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

      direct = lib.mapAttrs (depName: input:
        if input ? packages.${system}.lgx
        then input.packages.${system}.lgx
        else if input ? packages.${system}.lib
        then autoBundleLgx input.packages.${system}.lib
        else if input ? packages.${system}.default
        then autoBundleLgx input.packages.${system}.default
        # A flake that publishes `packages` but nothing usable for THIS system is
        # an error, not a fallback -- the same hazard the autoBundleLgx throws
        # above already guard against, one level out. Falling through to `input`
        # puts the dependency's SOURCE TREE into the app bundle where an LGX
        # package belongs: mkStandaloneApp then ships a directory of .cpp files
        # in place of a module and the failure only shows up at runtime, as a
        # module that never loads.
        #
        # Only a genuinely bare-derivation input (no `packages` attr at all) may
        # take the fallback below.
        else if input ? packages then
          builtins.throw ''
            collectAllModuleDeps: dependency '${depName}' publishes no usable package for ${system}.

            It exposes systems: ${lib.concatStringsSep ", " (builtins.attrNames input.packages)}
            ${lib.optionalString (input.packages ? ${system})
              "and for ${system}: ${lib.concatStringsSep ", " (builtins.attrNames input.packages.${system})} (none of lgx / lib / default)"}

            Fix: give '${depName}' a ${system} target and re-pin it, or publish an
            `lgx`/`lib`/`default` output for it. For a cross target that is usually
            a one-line change to the systems list its flake folds `packages` over.
          ''
        else input
      ) depInputs;

      transitive = builtins.foldl' (acc: name:
        let
          input = depInputs.${name};
          # `configFor.<system>` is the dependency's PLATFORM-RESOLVED config;
          # `config` is its system-agnostic one, which cannot answer for a
          # platform-keyed `dependencies` and throws when asked. Prefer the
          # resolved output when the dependency publishes one, and fall back to
          # `config` for a dependency pinned to a builder that predates it —
          # that fallback is exactly right, because a module built by an older
          # builder cannot have had platform overlays applied either.
          tdeps =
            if input ? configFor && input.configFor ? ${system}
            then input.configFor.${system}.dependencies or []
            else (input.config or {}).dependencies or [];
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
      logos-nix.lib.mkWindowsPkgs { buildSystem = windowsBuildSystem; };

  mkPkgs = mkPkgsWith [ ];

  # The build platform Windows artifacts are produced FROM.
  #
  # Single-sourced from logos-nix, which owns the decision and the reasoning
  # for it (`windowsBuildSystems`: wine does not exist for aarch64-darwin, and
  # upstream only exercises mingw cross from x86_64-linux). It was previously
  # a bare "x86_64-linux" literal repeated here in two places -- a second copy
  # of someone else's constant, free to drift from it.
  #
  # Deliberately NOT the evaluating system. Pinning it keeps
  # `packages.x86_64-windows.*` one well-defined derivation no matter who
  # evaluates it, so a Darwin and a Linux checkout agree and share a cache; a
  # Darwin dev realises it through a Linux remote builder. Widening this is a
  # change to `windowsBuildSystems` in logos-nix, not an edit here.
  windowsBuildSystem =
    if logos-nix == null then "x86_64-linux"
    else lib.head logos-nix.lib.windowsBuildSystems;

  # The system a build for `target` actually RUNS on. Host TOOLS -- the code
  # generators, moc, repc -- must come from here, never from the target set:
  # under cross, `packages.x86_64-windows.logos-qt-generator` is a PE that the
  # Linux builder cannot execute ("logos-cpp-generator: command not found").
  # Identity for every native system, so callers need no isWindows test.
  buildSystemFor = target:
    if target == "x86_64-windows" then windowsBuildSystem else target;

  # Resolve a module's concrete dependencies to `staticDeps` — the typed wrapper
  # generated from each dependency's published LIDL, which builds no dependency.
  #
  # There is no second half any more. A dependency that publishes no contract
  # used to take a header-copy path that compiled the dependency's whole plugin
  # just to read its headers; logos-plugin-qt removed that fallback and refuses
  # such a dependency by name (buildPlugin.nix, `assertNoLegacyHeaderDeps`), so
  # the names were only ever carried this far to be rejected at the far end.
  # Refusing here instead fails before anything is built and names the
  # metadata.json that has to change.
  #
  # Shared by mkLogosModule and buildCppPlugin: the two had byte-identical
  # copies of this, which is how their answers would come to differ.
  classifyConcreteDeps = { system, flakeInputs, src, config, builderName }:
    let
      depLidlOf = name:
        let i = flakeInputs.${name} or null;
        in if i != null && i ? packages && i.packages ? ${system}
           then (i.packages.${system}.lidl or null)
           else null;
      depIsLidl = name: (config.dependency_overrides ? ${name}) || (depLidlOf name != null);

      optional = config.optional_dependencies or [];

      # Identical for both refusals below; only the reason above it differs.
      fixHint = ''
        Fix: pass the flake input for each name above and re-pin it against a current
        logos-module-builder (any module built by one publishes `packages.<system>.lidl`),
        or point at a definition explicitly with a `dependency_overrides` entry. For a
        target whose contract you do not want to pin at all, drop the declaration and
        call it by name through `modules().dynamic("<name>")`.
      '';

      requiredWithoutLidl = lib.filter (name: !(depIsLidl name)) config.dependencies;
      assertRequiredPublishLidl =
        if requiredWithoutLidl == [] then null
        else throw ''
          metadata.json: module '${config.name}' lists dependencies that publish no LIDL
          contract: ${lib.concatStringsSep ", " requiredWithoutLidl}

          These used to be served by copying headers out of the dependency's BUILT
          plugin. That fallback is gone: logos-plugin-qt refuses such a dependency by
          name, so carrying it further only moves the same failure past the point
          where this file can name the fix.

          ${fixHint}
        '';

      optionalWithoutLidl = lib.filter (name: !(depIsLidl name)) optional;
      assertOptionalPublishLidl =
        if optionalWithoutLidl == [] then null
        else throw ''
          metadata.json: module '${config.name}' lists optional dependencies that publish
          no LIDL contract: ${lib.concatStringsSep ", " optionalWithoutLidl}

          The contract is the whole of what an optional dependency contributes: it is
          never loaded, never bundled, and never built. Without one there is nothing
          to generate a wrapper from, and a consumer that built it to get headers
          would have an optional dependency in name only.

          ${fixHint}
        '';

      resolve = name:
        let ov = config.dependency_overrides.${name} or null;
        in if ov != null then {
             inherit name;
             impl_class = ov.impl_class;
             path = if ov.input != null
                    then (if flakeInputs ? ${ov.input}
                          then "${flakeInputs.${ov.input}}/${ov.file}"
                          else throw "dependency_overrides.${name}: flake input '${ov.input}' was not passed to ${builderName}.")
                    else "${src}/${ov.file}";
           } else {
             inherit name;
             impl_class = null;
             path = "${depLidlOf name}/${name}.lidl";
           };
    in {
      staticDeps = map resolve
        (builtins.seq assertRequiredPublishLidl
          (builtins.seq assertOptionalPublishLidl (config.dependencies ++ optional)));
    };

  forAllSystems = _nixpkgs: f:
    lib.genAttrs systems (system: f {
      inherit system;
      pkgs = mkPkgs system;
    });

in {
  inherit systems mkPkgs mkPkgsWith forAllSystems buildSystemFor;
  inherit classifyConcreteDeps;

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
