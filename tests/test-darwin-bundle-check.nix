# Integration test: the darwin dylib-closure validator accepts a bundle whose
# loads are all in the closure it is given, and rejects one whose loads are not.
#
# openssl stands in for a bundled module here: libssl loads libcrypto from an
# absolute store path, which is exactly the shape that goes wrong when a module
# ships a prebuilt library.
{ pkgs, darwinBundleCheck }:

pkgs.runCommand "darwin-bundle-check-test" {
  nativeBuildInputs = [ (darwinBundleCheck.validator pkgs) ];
} ''
  printf '%s\n' ${pkgs.openssl.out} > complete-paths
  logos-check-dylib-closure complete-paths ${pkgs.openssl.out}/lib

  : > empty-paths
  if logos-check-dylib-closure empty-paths ${pkgs.openssl.out}/lib 2> rejection; then
    echo "FAIL: a load outside the closure was accepted" >&2
    exit 1
  fi
  if ! grep -q libcrypto rejection; then
    echo "FAIL: the rejection does not name the library that is missing" >&2
    cat rejection >&2
    exit 1
  fi

  touch $out
''
