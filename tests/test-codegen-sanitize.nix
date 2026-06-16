# Regression test for #116: universalCodegen must strip `explicit` from the
# impl ctor so logos-cpp-generator's ctor regex matches it.
{ pkgs, lib }:

let
  modulePreConfigure = import ../lib/modulePreConfigure.nix { inherit lib; };

  fixtureHeader = pkgs.writeText "libp2p_module_impl.h" ''
    #pragma once

    #include <cstddef>

    class Libp2pModuleImpl {
    public:
        explicit Libp2pModuleImpl(int opts);
        ~Libp2pModuleImpl();

        int compute(int x);
        size_t bufferSize() const;

    #if 0
    #ifdef NESTED_BRANCH
        void deadNested();
    #endif
        void deadOldApi();
    #endif

        void liveMethod();
    };
  '';

  unrelatedHeader = pkgs.writeText "unrelated.h" ''
    class OtherThing {
    public:
        explicit OtherThing(int x);
    };
  '';

  sanitize = modulePreConfigure.sanitizeImplHeader "Libp2pModuleImpl";

in pkgs.runCommand "codegen-sanitize-tests" {
  nativeBuildInputs = [ pkgs.gawk pkgs.gnused ];
} ''
  set -euo pipefail
  _stage=$(mktemp -d)
  _h="$_stage/libp2p_module_impl.h"
  _u="$_stage/unrelated.h"
  install -m 644 ${fixtureHeader} "$_h"
  install -m 644 ${unrelatedHeader} "$_u"

  ${sanitize "\"$_h\""}
  ${sanitize "\"$_u\""}

  fail() { echo "FAIL: $1"; echo "--- $2 ---"; cat "$2"; exit 1; }

  # `explicit` stripped from the named class's ctor, but the ctor survives.
  grep -qE '^[[:space:]]*explicit[[:space:]]+Libp2pModuleImpl[[:space:]]*\(' "$_h" \
    && fail "'explicit' was not stripped from Libp2pModuleImpl ctor" "$_h"
  grep -qE '^[[:space:]]*Libp2pModuleImpl[[:space:]]*\(int64_t opts\);' "$_h" \
    || fail "ctor signature was lost or malformed" "$_h"

  # Rewrite is anchored to the named impl class: an unrelated class keeps `explicit`.
  grep -qE '^[[:space:]]*explicit[[:space:]]+OtherThing[[:space:]]*\(' "$_u" \
    || fail "'explicit' was stripped from an unrelated class" "$_u"

  # `#if 0` block is dropped, including nested conditionals; live code after `#endif` stays.
  grep -qE 'deadOldApi|deadNested' "$_h" \
    && fail "code inside '#if 0' block leaked through" "$_h"
  grep -qE '^[[:space:]]*void liveMethod\(\);' "$_h" \
    || fail "method after '#endif' was removed" "$_h"

  # Platform-width int aliases are rewritten in every context the regex catches
  # (signatures AND struct fields AND unrelated class params — documented blast
  # radius of the rewrite; cpp-generator's wire format needs fixed-width types).
  grep -qE '\bsize_t\b' "$_h" && fail "size_t not rewritten" "$_h"
  grep -qE '\bint\b' "$_h" && fail "bare int not rewritten" "$_h"
  grep -qE '\bint\b' "$_u" && fail "bare int not rewritten in unrelated header" "$_u"
  grep -qE '^[[:space:]]*uint64_t bufferSize\(\) const;' "$_h" \
    || fail "size_t -> uint64_t rewrite did not produce expected line" "$_h"
  grep -qE '^[[:space:]]*int64_t compute\(int64_t x\);' "$_h" \
    || fail "int -> int64_t rewrite did not produce expected line" "$_h"

  mkdir -p $out
  echo passed > $out/results.txt
''
