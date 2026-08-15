# Guard: the module-side and host-side declarations of the view plugin
# interfaces must not drift apart.
#
# `LogosViewPlugin` and `LogosViewReplicaFactory` are each declared twice, on
# purpose:
#
#   module side  logos-plugin-qt/cmake/LogosView{PluginBase,ReplicaFactory}.h.in
#                — instantiated into every ui_qml module by logos_module()
#   host side    logos-view-module-runtime/include/LogosView{Plugin,ReplicaFactory}.h
#                — what ui-host qobject_casts a loaded plugin to
#
# They cannot be collapsed into one header. A module plugin must compile
# against Qt alone (the rep-file-plugin fixture is exactly that build), and
# logos-view-module-runtime depends on logos-plugin-qt, so an include between
# them could only ever point the wrong way. What binds them is the IID string,
# and a mismatch there is silent all the way to a blank view.
#
# This repo is the only one that can see both: it depends on logos-plugin-qt
# (for the templates) and on logos-view-module-runtime (for the host it runs
# ui_qml modules in). So the check lives here, and runs in this repo's CI.
{ pkgs, viewTemplates, viewRuntime }:

pkgs.runCommand "view-interface-abi-guard"
{
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  python3 ${./view-interface-abi.py} \
    --pair LogosViewReplicaFactory \
           ${viewTemplates}/LogosViewReplicaFactory.h.in \
           ${viewRuntime}/include/LogosViewReplicaFactory.h \
    --pair LogosViewPlugin \
           ${viewTemplates}/LogosViewPluginBase.h.in \
           ${viewRuntime}/include/LogosViewPlugin.h \
    | tee $out
''
