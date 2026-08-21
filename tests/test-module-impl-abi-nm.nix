# The module-impl C ABI, asserted against BUILT plugins — one per language
# backend — with nm.
#
# logos-cpp-sdk (#144) and logos-rust-sdk (#46) already check their own
# generators against logos-protocol's declared export list. Those are source
# checks: they prove each EMITTER writes the right names. Three things can still
# be wrong afterwards, and all three land here rather than there.
#
#   * THE CARRIER. Nothing between the emitter and the plugin is checked by
#     either. lib/mkLogosModule.nix parses the protocol version out of the
#     protocol header (protocolVersion, ~line 383) and passes it to the Rust
#     generator through `lib.optionalString (protocolVersion != null)`
#     (~line 483) — so if that regex ever stops matching, the flag does not
#     become wrong, it VANISHES. logos-lidl-gen then falls back to its own
#     default and regenerates every Rust module in the fleet with only the
#     founding exports. Both backend checks still pass, because both are handed
#     the version correctly; the builder is the only thing that got it wrong,
#     and this repo is the only one that sees the builder.
#
#   * "EMITTED BUT DID NOT COMPILE IN." A definition that is cfg-gated out,
#     dropped by --gc-sections, or lost to a link order change is present in the
#     generator's output and absent from the artifact.
#
#   * A BACKEND NOBODY WIRED A CHECK INTO. This check builds whatever it is
#     given, so a new LANGUAGE backend (the Nim cdylib path in flight as #202)
#     is covered by adding an attribute to `backends` below, and needs no source
#     check of its own to be caught here.
#
#     That is true of a language backend, not of every module SHAPE. Both
#     subjects below are `type: core`; the ui / ui_qml backends take a different
#     branch (lib/mkLogosModule.nix, coreBackend vs uiBackend) and are NOT
#     covered. Adding them needs a fixture, not just an attribute —
#     templates/ui-qml-backend ships no impl header and cannot build standalone.
#
# Why nm rather than a load test: on ELF an undefined symbol is legal at link
# time and resolved at load, and nixpkgs hardens with -Wl,-z,now, so the miss is
# fatal at dlopen() — on Linux. macOS links plugins -undefined dynamic_lookup
# and never binds, so the same broken plugin loads fine and the failure is
# INVISIBLE. nm reads the symbol table on BOTH platforms. That makes this the
# only check in the fleet that can catch a Linux-only runtime failure from a
# Darwin build — no source check and no runtime test can.
{ pkgs, mkLogosModule, moduleImplAbi, fixturesRoot, templatesRoot }:

let
  system = pkgs.stdenv.hostPlatform.system;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # ── The backends under test ──────────────────────────────────────────────
  # One entry per language backend that emits the module-impl C ABI. `hint` is
  # handed to logos-module-impl-diff, which prints it as "add the definition
  # here" — the point of the check is that a failure is actionable without
  # anyone having to rediscover which repo owns the emitter.
  #
  # Both subjects are modules this repo ALREADY builds, deliberately: the C++
  # one is the shipped `minimal-module` template (so the thing a new author
  # gets from `nix flake init` is what gets verified), and the Rust one is the
  # fixture checks.rust-native-dep already compiles. Neither adds a fixture.
  #
  # Cost, stated honestly for CI rather than for a warm laptop: locally only the
  # C++ module is new work, because rust-native-dep has usually been built. In
  # CI it is not — rust-native-dep is not currently a CI step — so this adds the
  # whole Rust chain, logos-lidl-gen included. Measured ~40-70s cold on an
  # M-series Mac, ~0 warm; expect a couple of minutes cold on ubuntu-latest.
  backends = {
    cpp = {
      label = "logos-cpp-sdk (C++ universal / Qt plugin)";
      hint = "logos-cpp-sdk: cpp-generator/experimental/lidl_gen_cdylib.cpp";
      src = templatesRoot + "/minimal-module";
    };
    rust = {
      label = "logos-rust-sdk (Rust cdylib)";
      hint = "logos-rust-sdk: lidl-gen/src/rustgen_provider.rs";
      src = fixturesRoot + "/rust-native-dep";
    };
  };

  moduleFor = b:
    (mkLogosModule {
      src = b.src;
      configFile = b.src + "/metadata.json";
    }).packages.${system}.default;

  # ── nm across two object formats ─────────────────────────────────────────
  # GNU nm reads .symtab by default and nixpkgs strips it, so on ELF the
  # DYNAMIC table (-D) is both the only one left and the only one the loader
  # ever binds against. Mach-O has no separate dynamic symbol table — llvm-nm
  # rejects -D on it outright — so there the external symbols (-g) ARE the
  # export table.
  #
  # Getting this wrong does not produce an error, it produces an EMPTY list,
  # which is why the zero-symbol guard below is load-bearing rather than
  # decorative. (Same reason the exports are declared
  # __attribute__((visibility("default"))) in logos_module_impl.h: built
  # -fvisibility=hidden they would be absent from the dynamic table, and a
  # check that shrugged at zero symbols would call that a pass.)
  nmTable = if isDarwin then "-g" else "-D";

  # Mach-O prefixes every C symbol with '_'; ELF does not. Strip it only where
  # it is there — on ELF this stage is a deliberate no-op rather than a
  # sed that might eat a legitimate leading underscore.
  stripUnderscore = if isDarwin then "sed 's/^_//'" else "cat";

  runOne = tag: b: ''
    check_backend ${tag} '${b.label}' '${b.hint}' ${moduleFor b}
  '';

in pkgs.runCommand "module-impl-abi-nm-tests" {
  nativeBuildInputs = [ pkgs.stdenv.cc.bintools.bintools ];
} ''
  set -euo pipefail

  declared=${moduleImplAbi}/exports.txt
  diff_exports=${moduleImplAbi}/bin/logos-module-impl-diff

  echo "=== module-impl C ABI vs BUILT plugins (protocol $(cat ${moduleImplAbi}/version)) ==="
  echo "    declared exports: $(wc -l < "$declared" | tr -d ' ') (from logos-protocol, never hardcoded here)"
  echo

  work=$PWD/work
  mkdir -p "$work"

  check_backend() {
    local tag="$1" label="$2" hint="$3" moduleOut="$4"
    local d="$work/$tag"
    mkdir -p "$d"

    echo "--- [$label] ---"

    # ── 1. FIND THE PLUGIN ────────────────────────────────────────────────
    # mkLogosModule stages the plugin under lib/ (and, on the Windows leg,
    # DLLs under bin/). Match by shared-object extension, not by filename: a
    # hardcoded name rots silently the day the naming changes, and this check
    # would then inspect nothing at all. Zero matches AND more than one are
    # both fatal — a glob that quietly matches nothing is the classic way a
    # check like this goes green over an empty set.
    : > "$d/plugins.txt"
    for sub in lib bin; do
      [ -d "$moduleOut/$sub" ] || continue
      find "$moduleOut/$sub" -type f \
        \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) >> "$d/plugins.txt"
    done
    sort -o "$d/plugins.txt" "$d/plugins.txt"

    local n
    n=$(wc -l < "$d/plugins.txt" | tr -d ' ')
    if [ "$n" -ne 1 ]; then
      {
        echo "FAIL: [$label] expected exactly ONE plugin shared object under"
        echo "      $moduleOut/{lib,bin}, found $n:"
        sed 's/^/        /' "$d/plugins.txt"
        echo
        echo "  Zero means the module output layout moved and this check was"
        echo "  about to verify nothing. More than one means the pattern no"
        echo "  longer identifies the plugin and the wrong file could be read."
      } >&2
      return 1
    fi

    local plugin
    plugin=$(cat "$d/plugins.txt")
    echo "    plugin: ''${plugin#"$moduleOut"/}"

    # ── 2. READ THE SYMBOL TABLE ──────────────────────────────────────────
    # No pipe and no `|| true` here on purpose: nm exits non-zero on a file it
    # cannot parse (including -D against a Mach-O), and under `set -e` that has
    # to kill the build. Swallowed, it would leave an empty file behind and
    # every assertion below would pass over it.
    nm ${nmTable} --defined-only "$plugin" > "$d/defined.raw"
    nm ${nmTable} --undefined-only "$plugin" > "$d/undefined.raw"

    # Anti-vacuity for assertion (2). "No undefined logos_module_*" is the PASS
    # verdict there, so an empty undefined table cannot be distinguished from a
    # good result by that assertion alone. Every real plugin imports SOMETHING
    # (malloc, memcpy, the host runtime), so an empty raw table means nm is not
    # reading what we think it is.
    if [ ! -s "$d/undefined.raw" ]; then
      {
        echo "FAIL: [$label] nm reported ZERO undefined symbols for $plugin."
        echo "      A linked plugin always imports something. This is a broken"
        echo "      nm invocation, not a clean plugin — and it would make the"
        echo "      'no undefined logos_module_*' assertion below vacuous."
      } >&2
      return 1
    fi

    # $NF: "ADDR T name" for defined, "<spaces> U name" for undefined.
    # `sed 's/@.*//'`: GNU nm prints a versioned ELF symbol as `name@@VER`, which
    # would compare as a different — and therefore MISSING — symbol. None of
    # these are versioned today; this keeps that from being load-bearing.
    awk '{ print $NF }' "$d/defined.raw"   | ${stripUnderscore} | sed 's/@.*//' | sort -u > "$d/defined.all"
    awk '{ print $NF }' "$d/undefined.raw" | ${stripUnderscore} | sed 's/@.*//' | sort -u > "$d/undefined.all"

    # grep exits 1 on no match, which is a legitimate outcome for BOTH sides: an
    # empty undefined set is the PASS verdict. So `|| true` is required — but it
    # must swallow only "no match" (1), never a real error (>=2) such as an
    # unreadable file. The defined count is asserted below; the undefined side
    # has no count to assert (empty IS the good answer), which is exactly why
    # its errors have to be distinguished here rather than downstream.
    grep '^logos_module_' "$d/defined.all"   > "$d/defined.txt"   || [ $? -eq 1 ]
    grep '^logos_module_' "$d/undefined.all" > "$d/undefined.txt" || [ $? -eq 1 ]

    local definedN
    definedN=$(wc -l < "$d/defined.txt" | tr -d ' ')
    if [ "$definedN" -eq 0 ]; then
      {
        echo "FAIL: [$label] nm found ZERO logos_module_* symbols DEFINED in"
        echo "      $plugin."
        echo
        echo "  Either the plugin genuinely exports none — in which case it"
        echo "  cannot load at all — or this check's symbol extraction is"
        echo "  broken (wrong symbol table for the object format, or the"
        echo "  underscore stripping is on the wrong platform). Both must be a"
        echo "  hard failure: a zero-length list compares clean against"
        echo "  anything, and the check would report a pass over an unexamined"
        echo "  binary."
        echo
        echo "  First lines of the raw nm output ($(wc -l < "$d/defined.raw" | tr -d ' ') symbols):"
        head -5 "$d/defined.raw" | sed 's/^/      /'
      } >&2
      return 1
    fi
    echo "    defined logos_module_* symbols: $definedN"

    # ── 3. ASSERTION (1): every DECLARED export is DEFINED ────────────────
    # The declared list and the failure explanation both come from
    # logos-protocol's own build output, at the revision this flake pins.
    # Nothing about the ABI is restated here. The helper refuses an empty file
    # on either side, so it cannot pass vacuously either.
    #
    # Extra symbols on the plugin side are allowed by design — the Rust
    # scaffold defines logos_module_install, an extern "Rust" author hook that
    # is not part of this ABI.
    "$diff_exports" "$declared" "$d/defined.txt" "$label" "$hint"

    # ── 4. ASSERTION (2): no logos_module_* symbol is UNDEFINED ───────────
    # This one is literally "will this dlopen()". (1) is strictly stronger in
    # one direction — it catches a module whose glue happens not to CALL the
    # export it failed to define, which leaves nothing undefined to see — and
    # strictly weaker in another: a symbol imported from elsewhere would satisfy
    # (1) and still fail to bind. Hence both.
    if [ -s "$d/undefined.txt" ]; then
      {
        echo "FAIL: [$label] the built plugin IMPORTS module-impl exports it is"
        echo "      supposed to DEFINE:"
        sed 's/^/        - /' "$d/undefined.txt"
        echo
        echo "  $plugin"
        echo
        echo "  On Linux this is fatal at dlopen() — nixpkgs' -Wl,-z,now binds"
        echo "  eagerly — and reports as \"undefined symbol\". On macOS the"
        echo "  plugin links -undefined dynamic_lookup and loads anyway, so"
        echo "  this failure does not reproduce at runtime on Darwin."
        echo
        echo "  Emitter: $hint"
      } >&2
      return 1
    fi

    echo "    PASS: no logos_module_* symbol is undefined"
    echo
  }

  ${pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList runOne backends)}

  echo "All backends define the complete module-impl C ABI."
  mkdir -p $out
  echo "passed" > $out/results.txt
''
