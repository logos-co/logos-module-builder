# Regression test for #116: universalCodegen must strip `explicit` from the
# impl ctor so logos-cpp-generator's ctor regex matches it.
{ pkgs, lib }:

let
  modulePreConfigure = import ../lib/modulePreConfigure.nix { inherit lib; };

  fixtureHeader = pkgs.writeText "libp2p_module_impl.h" ''
    #pragma once

    #include <cstddef>
    #include <string>

    struct Libp2pModuleOptions { int port; };

    class Libp2pModuleImpl {
    public:
        explicit Libp2pModuleImpl(const Libp2pModuleOptions& opts = {});
        ~Libp2pModuleImpl();

        int compute(int x);
        size_t bufferSize() const;

    #if 0
        void deadOldApi();
    #endif

        void liveMethod();
    };
  '';

  sanitize = modulePreConfigure.sanitizeImplHeader "Libp2pModuleImpl" "$_h";

in pkgs.runCommand "codegen-sanitize-tests" {
  nativeBuildInputs = [ pkgs.gawk pkgs.gnused ];
} ''
  set -euo pipefail

  _h="$(mktemp -d)/libp2p_module_impl.h"
  cp ${fixtureHeader} "$_h"
  chmod +w "$_h"

  # Exact snippet emitted by modulePreConfigure.sanitizeImplHeader.
  ${sanitize}

  # `explicit` stripped from the ctor (primary fix).
  if grep -qE '^[[:space:]]*explicit[[:space:]]+Libp2pModuleImpl[[:space:]]*\(' "$_h"; then
    echo "FAIL: 'explicit' was not stripped from the ctor"
    cat "$_h"; exit 1
  fi
  echo "PASS: 'explicit' stripped from ctor"

  # Ctor itself survives.
  if ! grep -qE '^[[:space:]]*Libp2pModuleImpl[[:space:]]*\(const Libp2pModuleOptions' "$_h"; then
    echo "FAIL: ctor declaration was removed"
    cat "$_h"; exit 1
  fi
  echo "PASS: ctor signature preserved"

  # Anchored to the named class — an unrelated class is untouched.
  _u="$(mktemp -d)/unrelated.h"
  cat > "$_u" <<'EOF'
class OtherThing {
public:
    explicit OtherThing(int x);
};
EOF
  _saved="$_h"; _h="$_u"; ${sanitize}; _h="$_saved"
  if ! grep -q 'explicit OtherThing(int64_t x);' "$_u"; then
    echo "FAIL: unrelated class's 'explicit' was rewritten"
    cat "$_u"; exit 1
  fi
  echo "PASS: sanitizer only touches the named impl class"

  # #if 0 block dropped, method after #endif kept.
  if grep -q 'deadOldApi' "$_h"; then
    echo "FAIL: '#if 0' block leaked through"
    cat "$_h"; exit 1
  fi
  if ! grep -q 'void liveMethod();' "$_h"; then
    echo "FAIL: method after '#endif' was removed"
    cat "$_h"; exit 1
  fi
  echo "PASS: '#if 0' block removed, code after '#endif' preserved"

  # size_t -> uint64_t, int -> int64_t.
  if grep -qE '\bsize_t\b' "$_h" || grep -qE '\bint\b' "$_h"; then
    echo "FAIL: platform-width int aliases not rewritten"
    cat "$_h"; exit 1
  fi
  if ! grep -q 'uint64_t bufferSize() const;' "$_h" \
     || ! grep -q 'int64_t compute(int64_t x);' "$_h"; then
    echo "FAIL: rewritten signatures don't match expected fixed-width forms"
    cat "$_h"; exit 1
  fi
  echo "PASS: size_t -> uint64_t, int -> int64_t"

  mkdir -p $out
  echo "passed" > $out/results.txt
''
