# The platform table in lib/resolvePlatforms.nix, checked against reality.
#
# `platformTriples` is a hand-written table mapping each entry of
# common.systems to the { os, architecture, abi } triple that
# `pkgs.stdenv.hostPlatform.parsed.{kernel,cpu,abi}.name` actually produces for
# it. It is a table rather than a derivation so that parsing metadata.json does
# not force a package set — but a hand-written table drifts, and drift here is
# invisible: a wrong row does not break the build, it makes every selector for
# that target quietly match nothing.
#
# This file is the only thing standing between that table and the following
# real trap, which is why it instantiates package sets that no other eval test
# needs:
#
#   lib.systems.elaborate "x86_64-windows"  ->  abi = "msvc"
#   (common.mkPkgs "x86_64-windows")…       ->  abi = "gnu"
#
# The mingw-ness of the Windows target lives in logos-nix's mkWindowsPkgs
# crossSystem (x86_64-w64-mingw32), not in the pseudo-system string. Elaborating
# the string — the obvious way to avoid instantiating anything — yields msvc, so
# the headline selector {"os":"windows","architecture":"x86_64","abi":"gnu"}
# would match nothing on the one platform this workspace cross-builds for, and
# every Windows overlay in the tree would be silently inert.
{ assertEq, common, parseMetadata }:

let
  actualFor = system:
    parseMetadata.platformOf (common.mkPkgs system).stdenv.hostPlatform;
in
map (system:
  assertEq "platformTriples row for ${system} matches the real package set"
    (parseMetadata.platformForSystem system)
    (actualFor system)
) common.systems
