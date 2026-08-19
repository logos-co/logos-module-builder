# Guard: the module-side and host-side declarations of the view plugin
# interfaces must not drift apart.
#
# `LogosViewPlugin` and `LogosViewReplicaFactory` are each declared twice, on
# purpose:
#
#   module side  logos-view-module/cmake/LogosView{PluginBase,ReplicaFactory}.h.in
#                — instantiated into every ui_qml module by logos_module()
#   host side    logos-view-module-runtime/include/LogosView{Plugin,ReplicaFactory}.h
#                — what ui-host qobject_casts a loaded plugin to
#
# They cannot be collapsed into one header. A module plugin must compile
# against Qt alone (the rep-file-plugin fixture is exactly that build), while
# the host side is a runtime that links the Qt host runtime and the protocol;
# and the two repos have no edge between them in either direction —
# logos-view-module is a LEAF (logos-nix only), and logos-view-module-runtime
# does not input it. So an include could not be written even if one were
# wanted. What binds them is the IID string, and a mismatch there is silent
# all the way to a blank view.
#
# This repo is the only one that can see both: it depends on logos-view-module
# (for the templates) and on logos-view-module-runtime (for the host it runs
# ui_qml modules in). So the check lives here, and runs in this repo's CI.
#
# WHAT IT READS — see the script's own header for the reasoning. Briefly: the
# IID `#define`, the RESOLVED Q_DECLARE_INTERFACE argument, the interface's
# base list and ordered pure-virtual list, and — the part that matters most —
# the CONCRETE classes in the templates, where Q_PLUGIN_METADATA and
# Q_INTERFACES declare the actual runtime binding. An earlier version looked
# only at the `#define` and the virtuals, and stayed green through both of the
# mutations that break a running view.
#
# COVERAGE BOUNDARY. Both sides here are pinned INPUTS, so this check sees
# whatever revs flake.lock names, not whatever is on those repos' branches:
#   * logos-view-module has its own CI, and the `rep-file-plugin` check that
#     moved there with the templates covers the module side from the binary
#     end (exact IID + a real QPluginLoader load and qobject_cast).
#   * logos-view-module-runtime's CI builds and runs its test suite, but
#     nothing there compares the host headers against the module-side
#     templates — it cannot, it does not depend on the repo holding them.
#     This check first sees a host-header change when the pin below is bumped.
#     Editing those headers is therefore a two-repo change: land it there,
#     then bump the pin here.
{ pkgs, viewTemplates, viewRuntime }:

pkgs.runCommand "view-interface-abi-guard"
{
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  # Explicit, not inherited: the script reports divergences on stdout but
  # reports a MISSING subject (renamed class, absent #define) via sys.exit on
  # stderr, and `| tee` would otherwise hand the pipeline tee's exit status.
  # A guard that cannot fail is the failure mode this whole check exists for.
  set -o pipefail

  python3 ${./view-interface-abi.py} \
    --pair LogosViewReplicaFactory \
           ${viewTemplates}/LogosViewReplicaFactory.h.in \
           ${viewRuntime}/include/LogosViewReplicaFactory.h \
    --pair LogosViewPlugin \
           ${viewTemplates}/LogosViewPluginBase.h.in \
           ${viewRuntime}/include/LogosViewPlugin.h \
    2>&1 | tee $out
''
