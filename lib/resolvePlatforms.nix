# Platform-keyed metadata.json — the selector, the merge, and the several ways
# this could have gone silently wrong.
#
# A module may declare an ORDERED list of selector-keyed overlays. The selector
# is a structured triple; each of its three components is independently
# optional:
#
#   "nix": {
#     "packages": { "runtime": ["nlohmann_json"] },
#     "platforms": [
#       { "when": { "os": "linux" },
#         "packages": { "runtime": ["krb5"] } },
#       { "when": { "architecture": "arm64" },
#         "cmake": { "extra_link_libraries": ["atomic"] } },
#       { "when": { "os": "windows", "architecture": "x86_64", "abi": "gnu" },
#         "cmake": { "extra_link_libraries": ["ws2_32","bcrypt","ntdll"] } }
#     ]
#   }
#
# EVERY matching entry applies, in DECLARATION ORDER. Lists concatenate (base
# first, then each matching overlay in turn), scalars overwrite, and OBJECTS
# RECURSE — merged key by key, with the keys only the base has surviving.
# There is no removal operator in v1 — restructure the base instead.
#
# WHY OBJECTS RECURSE INSTEAD OF OVERWRITING. The first sketch of this feature
# said "scalars and attrsets overwrite", and that is wrong in a way that is
# worth writing down rather than quietly fixing. Every overlay-able key under
# `nix` is an OBJECT: `packages` is `{build, runtime}`, `cmake` is four lists,
# `rust` is `{packages, env, toolchain}`. Under whole-object overwrite, the
# headline case of the whole feature —
#
#   "packages": { "build": ["pkg-config"], "runtime": ["nlohmann_json"] },
#   "platforms": [ { "when": {"os":"linux"}, "packages": {"runtime":["krb5"]} } ]
#
# — would silently DROP `packages.build` and `packages.runtime`'s base entry on
# Linux, because the overlay's `packages` object would replace the base's
# wholesale. Worse, "lists concatenate" would become unreachable for anything
# under `nix`: no list is ever a direct child of `packages`/`cmake`/`rust`, so
# the merge would never descend far enough to find one, and the single rule
# authors are most likely to rely on would be dead text. Recursion is what
# makes the two rules compose — descend through the objects, and apply the
# list/scalar rule at the leaf where the author actually wrote a value.
#
# WHY AN ORDERED LIST AND NOT A MAP KEYED BY SELECTOR. A map has no order, so
# it cannot express "general first, specific last": `{"os":"windows"}` and
# `{"os":"windows","architecture":"x86_64"}` would both match an x86_64 mingw
# build with nothing to say which one wins. The list makes that expressible —
# but note it does NOT make it automatic. Ordering is DECLARATION order, never
# specificity: put the general entry first yourself, because reversing the two
# entries above genuinely reverses the answer, and no rule here will catch it.
#
# WHY THIS EXISTS AT ALL. Nothing in metadata.json was platform-keyed before,
# so a module that needed a platform-specific anything declared a
# cross-platform SUPERSET by hand and let the build ignore the parts that did
# not apply. `include` names the .so, .dylib AND .dll spellings side by side
# (mkLogosModule.nix documents a name matching nothing as NORMAL), and
# `nix.packages.runtime` cannot express a superset at all: krb5 is an
# EVALUATION-time hard failure for a mingw host (its closure pulls in bash,
# whose meta.badPlatforms excludes a windows/pe host), so eight UI modules
# carry a hand-applied "drop unused krb5" commit and seven of them still have
# it. A superset nobody validates drifts — logos-package-downloader-module
# already forgot its .dll — which is why every rule below prefers a loud throw
# to a silently-skipped overlay.
{ lib }:

let
  # ── The reachable targets, as a TABLE rather than a derivation ────────────
  #
  # The triple is `pkgs.stdenv.hostPlatform.parsed.{kernel,cpu,abi}.name`, and
  # these five rows are that expression's measured output for the five entries
  # of common.systems. tests/test-platform-triples.nix asserts every row
  # against the real package set, because the whole point of the table is that
  # the cheap way to get these values is WRONG:
  #
  #   lib.systems.elaborate "x86_64-windows"           -> abi = "msvc"
  #   (common.mkPkgs "x86_64-windows").stdenv
  #     .hostPlatform.parsed.abi.name                  -> abi = "gnu"
  #
  # The mingw-ness of the Windows target lives in logos-nix's mkWindowsPkgs
  # crossSystem (x86_64-w64-mingw32), not in the pseudo-system string, so
  # elaborating the string alone yields msvc and the headline selector
  # {"os":"windows","architecture":"x86_64","abi":"gnu"} would never match on
  # the one platform this workspace cross-builds for. A table that a test pins
  # to reality is the cheapest way to make that failure impossible; deriving it
  # from a package set here would instead force nixpkgs to be instantiated
  # before a single line of metadata could be parsed.
  #
  # Deliberately NOT filtered by common.systems: whether logos-nix is threaded
  # into this builder decides what can be BUILT, and must not silently change
  # whether {"os":"windows"} is an accepted selector or a typo.
  platformTriples = {
    "x86_64-linux"   = { os = "linux";   architecture = "x86_64";  abi = "gnu"; };
    "aarch64-linux"  = { os = "linux";   architecture = "aarch64"; abi = "gnu"; };
    "x86_64-darwin"  = { os = "darwin";  architecture = "x86_64";  abi = "unknown"; };
    "aarch64-darwin" = { os = "darwin";  architecture = "aarch64"; abi = "unknown"; };
    # PSEUDO-system: a cross derivation's `system` is its BUILD platform, so
    # this row describes x86_64-w64-mingw32, not a native Windows builder.
    "x86_64-windows" = { os = "windows"; architecture = "x86_64";  abi = "gnu"; };
  };

  triples = builtins.attrValues platformTriples;
  reachableValues = field: lib.sort (a: b: a < b) (lib.unique (map (t: t.${field}) triples));
  reachableList = field: builtins.concatStringsSep ", " (reachableValues field);

  # ── Canonical vocabulary ──────────────────────────────────────────────────
  #
  # Both sides of every comparison are canonicalised through the SAME nixpkgs
  # tables that produced the observed values above, so "the author's spelling
  # and the build's spelling drifted apart" is not a state this code can reach.
  # That matters because three vocabularies are already live in this tree —
  # nix system strings (mkExternalLib's vendor_path/<system>/ subdirs), LGX
  # variant names (linux-amd64, darwin-arm64, the Go spelling), and now this —
  # and mkStandaloneApp.nix probes for three spellings of the same variant at
  # once precisely because nobody could say which was authoritative.
  #
  # Going through the tables means the aliases nixpkgs already carries work:
  # "arm64" resolves to "aarch64", "macos" and "win32" to "darwin" and
  # "windows". An author who writes the wrong-but-obvious thing gets the right
  # answer rather than an overlay that silently never fires.
  canonTables = {
    os           = lib.systems.parse.kernels;
    architecture = lib.systems.parse.cpuTypes;
    abi          = lib.systems.parse.abis;
  };

  # Consulted ONLY to improve an error message — never to accept a value. Every
  # entry here is a spelling that is absent from the nixpkgs table above, so
  # without the hint the author gets "not recognised" and a list of 47 cpu
  # names to guess from.
  aliasHints = {
    os = {
      win = "windows"; win64 = "windows"; mingw = "windows"; "mingw32" = "windows";
      osx = "darwin"; mac = "darwin"; macosx = "darwin"; apple = "darwin";
    };
    architecture = {
      amd64 = "x86_64"; x64 = "x86_64"; "x86-64" = "x86_64"; x86 = "x86_64";
      arm64e = "aarch64";
    };
    abi = {
      glibc = "gnu"; ucrt = "gnu"; msvcrt = "gnu"; mingw = "gnu"; none = "unknown";
    };
  };

  # Two-stage validation, and BOTH stages are load-bearing.
  #
  # Stage 1 (spelling) rejects a value the nixpkgs table has never heard of.
  # Stage 2 (reachability) rejects a value that canonicalises perfectly well but
  # that no Logos target has — {"os":"freebsd"} or {"abi":"musl"}. Without
  # stage 2 those are accepted and simply never fire, which is exactly the
  # failure mode this whole feature exists to remove: an overlay that looks
  # right, evaluates green everywhere, and quietly contributes nothing.
  canon = field: value:
    let
      table = canonTables.${field};
      hint = aliasHints.${field}.${value} or null;
    in
      if !(builtins.isString value) then
        throw ("metadata.json: platform selector `${field}` must be a string, got "
               + "${builtins.toJSON value}.")
      else if !(table ? ${value}) then
        throw ("metadata.json: platform selector `${field}: \"${value}\"` is not a "
               + "recognised ${field}."
               + (if hint != null then " Did you mean \"${hint}\"?" else "")
               + " Reachable values: ${reachableList field}.")
      else
        let c = table.${value}.name; in
        if !(builtins.elem c (reachableValues field)) then
          throw ("metadata.json: platform selector `${field}: \"${value}\"` canonicalises "
                 + "to \"${c}\", which no Logos target has, so this overlay could never "
                 + "apply. Reachable values: ${reachableList field}.")
        else c;

  selectorKeys = [ "os" "architecture" "abi" ];

  # ── The selector ──────────────────────────────────────────────────────────
  #
  # Canonicalises every PRESENT component and forces all of them before
  # comparing anything. The obvious `&&` chain is wrong here and the bug is
  # invisible: `{"os":"darwin","architecture":"amd64"}` validated CLEAN on
  # Linux, because the os mismatch short-circuited before "amd64" was ever
  # forced. That ships a typo which only throws on macOS — a green Linux CI run
  # proving nothing at all, which is how most Windows defects in this workspace
  # reached a release.
  canonWhen = { path, index, when }:
    let
      keys = builtins.attrNames when;
      unknown = lib.subtractLists selectorKeys keys;
      out = lib.genAttrs (lib.intersectLists selectorKeys keys) (k: canon k when.${k});
    in
      if !(builtins.isAttrs when) then
        throw ("metadata.json: ${path}[${toString index}].when must be an object like "
               + "{ \"os\": \"linux\" }, got ${builtins.toJSON when}.")
      else if keys == [ ] then
        throw ("metadata.json: ${path}[${toString index}] has an empty `when`. An overlay "
               + "that matches every platform IS the base config — move those values into "
               + "the base instead. `when: {}` is refused because it is indistinguishable "
               + "from a half-written entry, and it would let a module carry a non-empty "
               + "`platforms` list that varies nothing.")
      else if unknown != [ ] then
        throw ("metadata.json: ${path}[${toString index}].when has unknown key(s) "
               + builtins.concatStringsSep ", " (map (k: "`${k}`") unknown)
               + ". A selector may only use: " + builtins.concatStringsSep ", " selectorKeys
               + ". Each is independently optional; all three together name one variant.")
      # deepSeq, not the implicit forcing of `==`: every component must throw
      # its own spelling error even on a platform where an earlier component
      # already decided the answer.
      else builtins.deepSeq out out;

  matches = when: platform:
    (!(when ? os)           || when.os           == platform.os)
    && (!(when ? architecture) || when.architecture == platform.architecture)
    && (!(when ? abi)          || when.abi          == platform.abi);

  # ── What may vary by platform ─────────────────────────────────────────────
  #
  # Everything under `nix` is build-only and safe. Top-level fields cross the
  # build→run boundary, and that boundary is the whole reason this list is one
  # key long: the shipped metadata.json is the RAW SOURCE FILE. mkLogosQmlModule
  # copies ${configFile} into $out/lib/metadata.json verbatim, and the core path
  # embeds the same source file via configure_file + Q_PLUGIN_METADATA. Nothing
  # between the parse and the artifact ever writes the RESOLVED tree back out.
  #
  # So a top-level overlay is resolved for the BUILD and ships UNRESOLVED. That
  # is harmless for `include`, which is purely a build-time staging list read
  # once by mkLogosModule's stageIncludedRuntimeFiles and by nobody at runtime.
  # It is not harmless for anything a reader downstream of the build takes off
  # the installed manifest — see `topDeferred` below, which names the two such
  # fields and what has to land before they can be re-admitted.
  #
  # The refusals are the interesting half of this list:
  #   name / version / type / interface — module IDENTITY and the backend
  #     selection. `type` in particular is read OUTSIDE forAllSystems by both
  #     builders; a per-platform value has no single answer to give them.
  #   codegen / interface_dependencies / dependency_overrides — these decide
  #     the generated contract, hence the interface hash. A Linux consumer
  #     calling a Windows provider whose contract was generated from different
  #     inputs is a mismatch at introspect time, not a build error.
  #   host_services — a SECURITY declaration validated against a hardcoded
  #     allowlist. parseMetadata already argues that "a build-time allowlist a
  #     module could extend from its own metadata would not be an allowlist";
  #     a platform overlay is exactly such an extension vector, and it would
  #     mean auditing the Linux build tells you nothing about the Windows one.
  #   concurrency — the author owns thread-safety for "multi". Code whose
  #     correctness depends on which host built it is not code anyone can review.
  #   icon / view / category / description — pure manifest, resolved on the
  #     install machine, with no motivating case.
  topAllowed = [ "include" ];
  nixAllowed = [ "packages" "external_libraries" "cmake" "rust" ];

  # ── Refused FOR NOW, with the precondition written down ────────────────────
  #
  # These two are not refused on principle the way `type` or `host_services`
  # are — a per-target `main` or `dependencies` is a coherent thing to want.
  # They are refused because resolving them today changes the BUILD and not the
  # ARTIFACT, and the resulting module is wrong in a way that raises nothing
  # anywhere: no throw, no warning, a green evaluation on every platform, and a
  # manifest that names a file that does not exist on the targets the overlay
  # was written for.
  #
  # Kept as DATA rather than as a comment on the allowlist, so the refusal can
  # print the precondition to the author who tripped over it, and so that
  # re-admitting a key is a deliberate edit here rather than a word added to a
  # list. tests/test-parse-metadata.nix pins both the refusal and this map.
  topDeferred = {
    main = ''
      `main` names the plugin file the loader opens, and the manifest that names
      it is the SOURCE metadata.json, copied verbatim — so a per-target `main`
      would build one plugin and ship a manifest naming another on every target
      the overlay matched.

      It is worse than that here, and this is the part that decides the answer:
      mkLogosModule reads `config.main` in exactly ONE place — the
      legacy-interface guard at modulePreConfigure.nix:200, which only ever
      throws — so no BUILDING core module's `main` is read for anything; the
      file name comes from common.getPluginFilename. A core module that
      platform-keys it therefore evaluates green with no diagnostic anywhere. The platform-null poison that
      is supposed to catch this only ever fires on the ui_qml path, where
      mkLogosQmlModule reads `config.main` for `hasBackend`. A guarantee that
      holds for one module type and silently does not for the other is not a
      guarantee.'';
    dependencies = ''
      `dependencies` is resolved for the build and not for the artifact TWICE
      over. lgpm and the liblogos loader read the dependency list off the
      installed manifest, which is the verbatim source file; and the LogosModules
      umbrella is generated at build time by logos-plugin-qt/lib/buildPlugin.nix
      from that same raw array — the generator reads `deps` out of metadata.json
      itself, not out of this config — so the umbrella would carry the BASE list
      while the flake inputs carried the resolved one. A dependency added by an
      overlay would be built and linked, and then have no member on
      `modules()`.'';
  };

  # The one thing that has to be true before either key above can go back into
  # `topAllowed`. Named once, quoted by both refusals.
  deferredPrecondition = ''
    Both are re-admissible once the resolved tree reaches the artifact rather
    than the source file reaching it:

      1. lib/modulePreConfigure.nix's jq stamp (the one that already splices
         `logos_protocol_version` into the build-tree ./metadata.json) also
         splices the RESOLVED values in and does `del(.platforms)`, so the
         embedded and generator-visible copy is the resolved one; and
      2. lib/mkLogosQmlModule.nix copies that stamped build-tree file into
         $out/lib/metadata.json instead of ''${configFile}.

    Until both land, put the value in the base and let the platform-specific
    part be handled where it already is: a plugin's file EXTENSION comes from
    common.getPluginFilename, which is the case a per-target `main` would
    otherwise serve.'';

  # ── One overlay entry ─────────────────────────────────────────────────────
  validateOverlay = { path, allowed, deferred ? { }, index, overlay }:
    let
      body = removeAttrs overlay [ "when" ];
      bodyKeys = builtins.attrNames body;
      offenders = lib.subtractLists allowed bodyKeys;
      # Two kinds of refusal, and they deserve different words. A `type` or a
      # `host_services` overlay is refused because the field must not vary, ever.
      # A `main` or `dependencies` overlay is refused because the plumbing that
      # would make it honest does not exist yet — telling an author "not allowed"
      # when the real answer is "not yet, and here is what is missing" is how a
      # temporary restriction becomes folklore.
      deferredOffenders = lib.filter (k: deferred ? ${k}) offenders;
      hardOffenders = lib.subtractLists (builtins.attrNames deferred) offenders;
      hardText = lib.optionalString (hardOffenders != [ ])
        ("metadata.json: ${path}[${toString index}] may not override "
         + builtins.concatStringsSep ", " (map (k: "`${k}`") hardOffenders)
         + ". Only " + builtins.concatStringsSep ", " allowed
         + " may vary by platform at this level — see lib/resolvePlatforms.nix for "
         + "why each of the others is refused.\n");
      deferredText = lib.optionalString (deferredOffenders != [ ])
        ("metadata.json: ${path}[${toString index}] may not override "
         + builtins.concatStringsSep ", " (map (k: "`${k}`") deferredOffenders)
         + " — not on principle, but because resolving it today would change the BUILD "
         + "and not the SHIPPED MODULE, and nothing anywhere would say so.\n\n"
         + builtins.concatStringsSep "\n\n" (map (k: deferred.${k}) deferredOffenders)
         + "\n\n" + deferredPrecondition);
    in
      if !(builtins.isAttrs overlay) then
        throw ("metadata.json: ${path}[${toString index}] must be an object with a `when` "
               + "selector, got ${builtins.toJSON overlay}.")
      else if !(overlay ? when) then
        throw ("metadata.json: ${path}[${toString index}] has no `when` selector. It is not "
               + "defaulted to match-everything: an overlay that applies unconditionally is "
               + "the base config, so a missing selector is far more likely to be an "
               + "unfinished entry than an intentional one.")
      else if offenders != [ ] then throw (hardText + deferredText)
      else {
        inherit index body;
        when = canonWhen { inherit path index; when = overlay.when; };
      };

  asOverlayList = path: v:
    if builtins.isList v then v
    else throw ("metadata.json: `${path}` must be a LIST of overlays, got "
                + "${builtins.typeOf v}. It is ordered rather than an object keyed by "
                + "selector precisely so a general entry can be written before a specific "
                + "one; an object could not express that.");

  # ── The node merge ────────────────────────────────────────────────────────
  #
  # Deliberately NOT common.recursiveMerge, which is close but wrong twice for
  # this job: it runs the merged lists through lib.unique (dedup that can
  # REORDER a link line, where order is load-bearing), and on a type mismatch it
  # silently takes lib.last instead of refusing. Both would turn an authoring
  # mistake into a build that succeeds and links the wrong thing.
  mergeNode = { path, a, b }:
    builtins.foldl' (acc: k:
      let
        pk = path ++ [ k ];
        here = builtins.concatStringsSep "." pk;
        av = acc.${k} or null;
        bv = b.${k};
      in
        if bv == null then
          throw ("metadata.json: platform overlay sets `${here}` to null. There is no "
                 + "removal operator in v1 — null over a scalar is a blanking operator and "
                 + "null over a list is removal, and both need a semantics that says what "
                 + "happens when two overlays disagree. Restructure the base so the value "
                 + "only appears in the overlays that want it.")
        else if !(acc ? ${k}) then acc // { ${k} = bv; }
        # An explicit null in the BASE means "unset" — `"nix": {"rust":
        # {"toolchain": null}}` is how a module says "the pinned nixpkgs rustc"
        # — so an overlay may fill it. Null is asymmetric on purpose:
        # unset-then-set is a thing an author means, set-then-unset (null in an
        # overlay, above) is the removal operator v1 does not have.
        else if av == null then acc // { ${k} = bv; }
        else if builtins.isList av && builtins.isList bv then acc // { ${k} = av ++ bv; }
        else if builtins.isAttrs av && builtins.isAttrs bv then
          acc // { ${k} = mergeNode { path = pk; a = av; b = bv; }; }
        else if builtins.typeOf av == builtins.typeOf bv then acc // { ${k} = bv; }
        else
          throw ("metadata.json: type mismatch at `${here}`: the base is a "
                 + "${builtins.typeOf av} and a platform overlay supplies a "
                 + "${builtins.typeOf bv}. Lists concatenate and scalars overwrite, but "
                 + "there is no rule that turns one into the other.")
    ) a (builtins.attrNames b);

  applyOverlays = { path, basePath, allowed, deferred ? { }, base, overlays, platform }:
    let
      checked = lib.imap0 (index: overlay:
        validateOverlay { inherit path allowed deferred index overlay; }
      ) (asOverlayList path overlays);
      matching = lib.filter (c: matches c.when platform) checked;
    in {
      # Forced by the caller whether or not anything matched — a typo in an
      # overlay for another platform must fail HERE, not on the machine that
      # happens to build for it.
      validated = map (c: c.when) checked;
      touchedKeys = lib.unique (lib.concatMap (c: builtins.attrNames c.body) checked);
      matchedKeys = lib.unique (lib.concatMap (c: builtins.attrNames c.body) matching);
      merged = builtins.foldl' (acc: c: mergeNode { path = basePath; a = acc; b = c.body; })
                 base matching;
    };

  # ── external_libraries: concatenation alone is silently WRONG here ─────────
  #
  # It is a list of OBJECTS that mkExternalLib folds with lib.listToAttrs keyed
  # on `.name` — and listToAttrs keeps the FIRST entry on a duplicate key
  # (verified: listToAttrs [{name="a";value=1;} {name="a";value=2;}] == {a=1;}).
  # So under base-first concatenation, an overlay refining a library the base
  # already declares is discarded and the BASE wins: the exact inverse of
  # "specific last", with nothing raised. Refuse the ambiguous shape instead of
  # inventing a by-name merge whose precedence would be a second thing to learn.
  #
  # Checked only when a matching overlay actually supplied external_libraries,
  # so a module that already ships a duplicate (a pre-existing bug, but not one
  # this change introduced) keeps building exactly as it did.
  checkExternalLibs = { merged, matchedKeys }:
    let
      libs = merged.external_libraries or [ ];
      names = map (l: l.name or null) (if builtins.isList libs then libs else [ ]);
      dupes = lib.unique (lib.filter (n: n != null
                && builtins.length (lib.filter (m: m == n) names) > 1) names);
    in
      if !(builtins.elem "external_libraries" matchedKeys) || dupes == [ ] then merged
      else throw ("metadata.json: platform overlays leave `nix.external_libraries` with "
                  + "duplicate name(s) " + builtins.concatStringsSep ", " (map (n: "`${n}`") dupes)
                  + ". Entries concatenate, and mkExternalLib folds them by name keeping the "
                  + "FIRST — so the base entry would silently win over the overlay that was "
                  + "meant to refine it. Move the whole entry into the platform overlays "
                  + "that want it rather than declaring it twice.");

  # ── No platform available ─────────────────────────────────────────────────
  #
  # Parsing with `platform = null` is legitimate: both builders need a
  # system-agnostic config for the handful of fields no overlay may vary
  # (`name`, `type`, `version`), and those are read OUTSIDE forAllSystems where
  # no package set and no target exist yet. What must never happen is that such
  # a parse answers a platform-keyed question with the BASE value — a superset
  # that was never meant to be used on its own is how the .so/.dylib/.dll
  # spelling lists drifted in the first place.
  #
  # So instead of failing the whole parse (which would take `config.name` and
  # `config.type` down with it, and with them the backend selection and every
  # cross-flake reader of the module's `config` output), poison exactly the
  # fields an overlay declares. Nix's laziness makes that precise: attrNames,
  # name, type, version all keep working; the fields that no longer have a
  # single answer refuse to produce one, and say where to get the real one.
  poisonField = { path, field }:
    throw ("metadata.json: `${path}${field}` is platform-keyed (some `platforms` overlay "
           + "sets it) but this config was parsed with `platform = null`, so there is no "
           + "single answer to give. Reading it would hand back the BASE value, which is "
           + "the one thing a platform-keyed field must never silently do.\n\n"
           + "Parse with a platform: parseMetadata.parseModuleConfig { json = ...; "
           + "platform = parseMetadata.platformForSystem system; } — inside forAllSystems, "
           + "where the target is known. A builder that reads this field above "
           + "forAllSystems has to move that read down; a flake consumer should read "
           + "`configFor.<system>` instead of the system-agnostic `config`.");

  # ── A `platforms` key that is not in a place overlays are read from ───────
  #
  # `nix.packages.platforms`, `nix.rust.platforms`, `codegen.platforms` — every
  # one of these is a natural thing to write, because the author is thinking
  # "this block varies by platform" and puts the list next to the block. And
  # every one of them is read by NOTHING: resolution looks at exactly two paths,
  # so the overlay is dropped on the floor, the base ships to every target, and
  # the module builds green everywhere while doing none of what it says.
  #
  # That is precisely the failure this whole file is written to make impossible
  # — a superset nobody validates, an overlay that quietly never fires — so the
  # tree gets swept for the key and a misplaced one is a hard error that names
  # the path. The sweep is cheap (metadata.json is a few KB of plain JSON) and
  # it runs on EVERY parse, including the early return for a module that
  # declares no overlays at all: a module with `nix.rust.platforms` and nothing
  # else HAS no legal overlay block, so the early return is exactly the path
  # such a module takes, and leaving the sweep off it would mean the check
  # never fires for the modules that need it most.
  #
  # It descends into lists as well as objects, because `nix.external_libraries`
  # is a list of objects and "put the platforms list inside the library entry it
  # varies" is the same mistake one level down.
  legalPlatformsPaths = [ "platforms" "nix.platforms" ];

  # Spellings that are obviously meant to be `platforms` and would otherwise be
  # ignored in silence.
  platformsNearMisses = [ "platform" "Platforms" "platform_overrides" "platform_overlays" ];

  sweepMisplacedPlatforms = raw:
    let
      walk = path: v:
        if builtins.isAttrs v then
          lib.concatMap (k:
            let here = if path == "" then k else "${path}.${k}"; in
            # Near-misses are swept too. A sweep keyed on the exact spelling
            # leaves `platform` (singular) — ONE character from the mistake this
            # exists to make impossible — silently dropped, which is the original
            # defect wearing a typo. No metadata.json in the tree carries any
            # `platform*` key, so refusing them costs nothing today.
            if (k == "platforms" && !(builtins.elem here legalPlatformsPaths))
               || builtins.elem k platformsNearMisses
            then [ here ]
            else walk here v.${k}
          ) (builtins.attrNames v)
        else if builtins.isList v then
          lib.concatLists (lib.imap0 (i: e: walk "${path}[${toString i}]" e) v)
        else [ ];
      offenders = if builtins.isAttrs raw then walk "" raw else [ ];
      # A MISSPELLING and a MISPLACEMENT need different advice: one is renamed
      # where it stands, the other is moved. Telling an author to "move the list
      # up" when they wrote `platform` sends them off to rewrite a structure
      # that was already correct.
      misspelled = lib.filter (o: builtins.elem (lib.last (lib.splitString "." o))
                                                platformsNearMisses) offenders;
      fixHint =
        if misspelled != [ ] && misspelled == offenders then
          "Rename it to `platforms` (plural) where it stands."
        else
          "Move the list up to whichever of those owns the key you meant to vary, "
          + "and name the key inside the overlay body: "
          + "`\"nix\": { \"platforms\": [ { \"when\": {...}, \"packages\": {...} } ] }`, "
          + "not `\"nix\": { \"packages\": { \"platforms\": [...] } }`.";
    in
      if offenders == [ ] then null
      else throw ("metadata.json: `" + builtins.concatStringsSep "`, `" offenders
                  + "` is not a place platform overlays are read from, so it would have "
                  + "been SILENTLY IGNORED — the base would ship to every target and "
                  + "nothing would have said so. Overlays are declared in exactly two "
                  + "places: `platforms` at the TOP LEVEL (which may vary "
                  + builtins.concatStringsSep ", " topAllowed
                  + ") and `nix.platforms` (which may vary "
                  + builtins.concatStringsSep ", " nixAllowed
                  + "). " + fixHint);

in
rec {
  inherit platformTriples;

  # The one sanctioned way to turn a nix system string into a selector triple.
  platformForSystem = system:
    platformTriples.${system} or (throw
      ("logos-module-builder: no platform triple for system '${system}'. Known: "
       + builtins.concatStringsSep ", " (builtins.attrNames platformTriples)
       + ". Add a row to platformTriples in lib/resolvePlatforms.nix (and to the "
       + "reality assertion in tests/test-platform-triples.nix) when a target is added."));

  # ...and from a package set, for callers that already have one. Kept as the
  # SAME triple the table produces so there is one comparison vocabulary, not
  # two that can disagree.
  platformOf = hostPlatform:
    if !(builtins.isAttrs hostPlatform) || !(hostPlatform ? parsed) then
      throw ("logos-module-builder: platformOf expects pkgs.stdenv.hostPlatform (it reads "
             + "`.parsed.{kernel,cpu,abi}.name`). A hand-rolled stub with only "
             + "isLinux/isDarwin/isWindows will not do: those three booleans cannot express "
             + "`architecture` or `abi`.")
    else validatePlatform {
      os           = hostPlatform.parsed.kernel.name;
      architecture = hostPlatform.parsed.cpu.name;
      abi          = hostPlatform.parsed.abi.name;
    };

  # A platform triple is validated through the SAME canonicalise + reachability
  # check as a `when` value. Symmetric validation on both sides is what makes
  # "a well-spelled selector always matches its own platform" a property of the
  # code rather than a hope — and it stops a test from hand-rolling
  # { os = "win"; } and quietly asserting nothing.
  validatePlatform = platform:
    if platform == null then null
    else if !(builtins.isAttrs platform) then
      throw ("logos-module-builder: `platform` must be null or a triple "
             + "{ os, architecture, abi }, got ${builtins.typeOf platform}. Build one with "
             + "parseMetadata.platformForSystem <system> or parseMetadata.platformOf "
             + "pkgs.stdenv.hostPlatform.")
    else
      let
        keys = builtins.attrNames platform;
        missing = lib.subtractLists keys selectorKeys;
        extra = lib.subtractLists selectorKeys keys;
        out = lib.genAttrs selectorKeys (k: canon k platform.${k});
      in
        if missing != [ ] || extra != [ ] then
          throw ("logos-module-builder: `platform` must have exactly "
                 + builtins.concatStringsSep ", " selectorKeys
                 + (if missing != [ ] then "; missing " + builtins.concatStringsSep ", " missing else "")
                 + (if extra != [ ] then "; unexpected " + builtins.concatStringsSep ", " extra else "")
                 + ". Unlike a `when` selector, a platform is a full triple — a partial one "
                 + "would make `abi`-only selectors match by accident.")
        else builtins.deepSeq out (
          # Every component can be individually reachable while the COMBINATION
          # exists on no target: {os="darwin"; architecture="aarch64"; abi="gnu"}
          # passes a component-wise check, but darwin's abi is "unknown", so every
          # `abi`-bearing selector would silently never fire. That is the same
          # silence the platform guard above exists to prevent, one level down —
          # so it is refused here rather than discovered as a missing library on
          # one target six months later.
          if !(builtins.elem out (builtins.attrValues platformTriples)) then
            throw ("logos-module-builder: `platform` " + builtins.toJSON out
                   + " is not a Logos target. Each component is reachable on its "
                   + "own, but no row of platformTriples carries this combination, "
                   + "so every `abi`-bearing selector would silently never match. "
                   + "Known targets: "
                   + builtins.concatStringsSep ", " (builtins.attrNames platformTriples)
                   + ".")
          else out);

  # Resolve `platforms` overlays into the raw JSON tree, returning a tree of the
  # same shape with both `platforms` keys removed. Everything downstream — the
  # whole 300-line body of parseMetadata.nix, every existing validation, every
  # `config.*` field — then runs unchanged over the RESOLVED answer.
  resolvePlatforms = { platform, raw }:
    let
      plat = validatePlatform platform;
      # See the bottom of this function for why this is a binding and not an
      # inline call: it has to be forced on the early-return path too.
      sweep = sweepMisplacedPlatforms raw;
      # A non-object `nix` is a metadata bug, but it is parseMetadata's to
      # report — it already fails on `(nix.packages or {})`, and substituting an
      # empty set here would turn that error into a config that silently parses
      # with no build inputs at all. `nixIsObject` gates every rewrite below so
      # the malformed value is passed through untouched.
      nixIsObject = raw ? nix && builtins.isAttrs raw.nix;
      nix0 = if nixIsObject then raw.nix else { };
      hasTop = raw ? platforms;
      hasNix = nix0 ? platforms;

      nixRes = applyOverlays {
        path = "nix.platforms";
        basePath = [ "nix" ];
        allowed = nixAllowed;
        base = removeAttrs nix0 [ "platforms" ];
        overlays = nix0.platforms or [ ];
        platform = plat;
      };
      nixMerged = checkExternalLibs {
        merged = nixRes.merged;
        matchedKeys = nixRes.matchedKeys;
      };

      topBase = (removeAttrs raw [ "platforms" ])
                // lib.optionalAttrs nixIsObject { nix = nixMerged; };
      topRes = applyOverlays {
        path = "platforms";
        basePath = [ ];
        allowed = topAllowed;
        deferred = topDeferred;
        base = topBase;
        overlays = raw.platforms or [ ];
        platform = plat;
      };

      # Forced regardless of which branch we take below: a malformed selector is
      # a metadata bug, and metadata is a few KB of plain JSON, so checking it
      # whole costs nothing and turns every rule above into a PARSE-time failure
      # on EVERY platform. Left lazy, a bad selector under `nix.platforms` stays
      # silent on any build that never happens to read `nix.packages`.
      validation = builtins.deepSeq [ nixRes.validated topRes.validated ] null;

      poisoned =
        (removeAttrs raw [ "platforms" ])
        // lib.optionalAttrs nixIsObject {
             nix = (removeAttrs nix0 [ "platforms" ])
                   // lib.genAttrs nixRes.touchedKeys
                        (field: poisonField { path = "nix."; inherit field; });
           }
        // lib.genAttrs topRes.touchedKeys (field: poisonField { path = ""; inherit field; });

      resolved = builtins.deepSeq topRes.merged topRes.merged;
    in
      # ── Both guards are forced on EVERY path, including the early return ────
      #
      # The early return below exists because a module with no `platforms` block
      # anywhere must get back the identical tree it handed in — that is what
      # keeps every module in the tree building byte-for-byte as it did. What it
      # must NOT also do is skip the checks, and it did:
      #
      #   `plat` is only ever forced by the overlay machinery, so a module with
      #   no overlays never forced it. An invalid `platform` argument — a bare
      #   "x86_64-linux" string, `true`, a partial triple, an attrset with the
      #   wrong keys — was therefore ACCEPTED IN SILENCE by every module in the
      #   tree, since none of them declares an overlay yet. It would only start
      #   throwing the day somebody, in a different repo, months later, added
      #   one. That is a guarantee conditional on module CONTENT, and
      #   parseMetadata.nix's own header spends fifteen lines arguing that such
      #   a guarantee is worse than none: the defect is authored at one call
      #   site and discovered at another.
      #
      #   `sweep` has the same shape and a sharper edge, because a module whose
      #   only `platforms` key is a MISPLACED one (`nix.packages.platforms`)
      #   takes exactly this early return — `hasTop` and `hasNix` are both
      #   false for it — so the check that exists to catch that mistake would
      #   never run for the only module that can make it.
      #
      # Forcing both here costs one seq on a path that then returns `raw`
      # unchanged, and makes both guarantees properties of the CALL rather than
      # of what the module happens to contain.
      builtins.seq plat (builtins.seq sweep (
        if !hasTop && !hasNix then raw
        else builtins.seq validation (if plat == null then poisoned else resolved)));

  # The overlay allowlists and the deferred-with-a-reason map, exposed so a test
  # can pin them and so an error message elsewhere can quote them. `deferredTop`
  # in particular is the written-down precondition for re-admitting `main` and
  # `dependencies`; a test asserts it still names both halves of that
  # precondition, so deleting the plumbing note and quietly widening the
  # allowlist is not a one-word edit.
  overlayAllowed = { top = topAllowed; nix = nixAllowed; };
  overlayDeferredTop = topDeferred;
  overlayDeferredPrecondition = deferredPrecondition;
}
