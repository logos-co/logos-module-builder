{ pkgs
, standalone
, plugin ? null
, qmlSrc ? null
, metadataFile
, iconFiles ? []
, dirName ? "logos-ui-plugin-dir"
, format ? "qt-plugin"
}:

let
  iconInstall = pkgs.lib.concatStringsSep "\n" (map (icon: ''
    mkdir -p $out/icons
    cp ${icon} $out/icons/${builtins.baseNameOf (toString icon)}
  '') iconFiles);

  pluginDir =
    if format == "qml" && qmlSrc != null then
      pkgs.runCommand dirName {} ''
        set -euo pipefail
        cp -r ${qmlSrc}/. $out
        chmod -R u+w $out
        cp ${metadataFile} $out/metadata.json
        ${iconInstall}
      ''
    else if format == "qml" then
      pkgs.runCommand dirName {} ''
        set -euo pipefail
        mkdir -p $out
        cp -r ${plugin}/lib/. $out/
        cp ${metadataFile} $out/metadata.json
        ${iconInstall}
      ''
    else
      pkgs.runCommand dirName {} ''
        set -euo pipefail
        mkdir -p $out
        cp ${plugin}/lib/*_plugin.* $out/
        cp ${metadataFile} $out/metadata.json
        ${iconInstall}
      '';

  run = pkgs.writeShellApplication {
    name = "run-logos-standalone-ui";
    runtimeInputs = [ standalone ];
    text = ''
      exec ${standalone}/bin/logos-standalone-app "${pluginDir}" "$@"
    '';
  };
in {
  type = "app";
  program = "${run}/bin/run-logos-standalone-ui";
}
