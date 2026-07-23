{ pkgs
, standalone
, plugin ? null
, qmlSrc ? null
, metadataFile
, dirName ? "logos-ui-plugin-dir"
, format ? "qt-plugin"
, moduleDeps ? {}
}:

let
  layout = import ./appRuntimeLayout.nix {
    inherit pkgs standalone plugin qmlSrc metadataFile dirName format moduleDeps;
  };

  run = pkgs.writeShellApplication {
    name = "run-logos-standalone-ui";
    runtimeInputs = [ standalone ];
    text = if layout.hasModuleDeps then ''
      exec ${standalone}/bin/logos-standalone-app --modules-dir "${layout.modulesDir}" "${layout.pluginDir}" "$@"
    '' else ''
      exec ${standalone}/bin/logos-standalone-app "${layout.pluginDir}" "$@"
    '';
  };
in {
  type = "app";
  program = "${run}/bin/run-logos-standalone-ui";
}
