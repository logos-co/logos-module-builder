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
  parsedMetadata = builtins.fromJSON (builtins.readFile metadataFile);
  iconFiles = pkgs.lib.optional
    (parsedMetadata ? icon && parsedMetadata.icon != null && (qmlSrc != null || plugin != null))
    ((dirOf metadataFile) + "/${parsedMetadata.icon}");

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
      # plugin may be a lib/-layout directory (from mkLogosQmlModule combined)
      # or a flat directory; handle both cases.
      pkgs.runCommand dirName {} ''
        set -euo pipefail
        mkdir -p $out
        if [ -d "${plugin}/lib" ]; then
          cp -r ${plugin}/lib/. $out/
        else
          cp -r ${plugin}/. $out/
        fi
        chmod -R u+w $out
        cp ${metadataFile} $out/metadata.json
        ${iconInstall}
      ''
    else
      pkgs.runCommand dirName {} ''
        set -euo pipefail
        mkdir -p $out
        # Copy backend plugin (if present)
        for f in ${plugin}/lib/*_plugin.*; do
          [ -e "$f" ] && cp "$f" $out/
        done
        # Copy typed replica factory plugin (if present)
        for f in ${plugin}/lib/*_replica_factory.*; do
          [ -e "$f" ] && cp "$f" $out/
        done
        cp ${metadataFile} $out/metadata.json
        ${iconInstall}
        # Copy QML view directories and root-level QML files (if present)
        for d in ${plugin}/lib/*/; do
          [ -e "$d" ] || continue
          dirname=$(basename "$d")
          [ "$dirname" != "." ] && cp -r "$d" "$out/$dirname"
        done
        for f in ${plugin}/lib/*.qml; do
          [ -e "$f" ] && cp "$f" $out/
        done
      '';

  hasModuleDeps = moduleDeps != {};

  # Create a merged modules directory containing the standalone app's built-in
  # modules (e.g. capability_module) plus all resolved dependency modules.
  # Each dependency is extracted from its LGX package — the same format used by
  # lgpm and the standalone app's own capability_module bundling — ensuring all
  # files (plugin binary + external libraries) are included.
  modulesDir = pkgs.runCommand "${dirName}-modules" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    mkdir -p $out

    # Copy built-in modules from the standalone app (capability_module, etc.)
    if [ -d "${standalone}/modules" ]; then
      cp -r ${standalone}/modules/* $out/
    fi

    ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList (name: lgxPkg: ''
      # --- Install ${name} from LGX package ---
      lgx_file=$(find ${lgxPkg} -name '*.lgx' | head -1)
      if [ -n "$lgx_file" ]; then
        extract_dir=$(mktemp -d)
        tar -xzf "$lgx_file" -C "$extract_dir"

        # Find the platform variant directory
        variant_dir=""
        for v in darwin-arm64-dev darwin-amd64-dev darwin-x86_64-dev \
                 linux-x86_64-dev linux-amd64-dev linux-arm64-dev \
                 darwin-arm64 darwin-amd64 darwin-x86_64 \
                 linux-x86_64 linux-amd64 linux-arm64; do
          if [ -d "$extract_dir/variants/$v" ]; then
            variant_dir="$extract_dir/variants/$v"
            break
          fi
        done

        if [ -n "$variant_dir" ]; then
          module_name=$(python3 -c "
import json; f=open('$extract_dir/manifest.json'); print(json.load(f).get('name',str())); f.close()
")
          if [ -n "$module_name" ]; then
            mkdir -p "$out/$module_name"
            cp "$extract_dir/manifest.json" "$out/$module_name/"
            cp -r "$variant_dir"/* "$out/$module_name/"
            echo "Bundled $module_name from LGX into $out/$module_name/"
          else
            echo "Warning: could not read module name from LGX manifest for ${name}" >&2
          fi
        else
          echo "Warning: no matching platform variant in LGX package for ${name}" >&2
        fi
        rm -rf "$extract_dir"
      else
        echo "Warning: no .lgx file found for ${name}" >&2
      fi
    '') moduleDeps)}
  '';

  run = pkgs.writeShellApplication {
    name = "run-logos-standalone-ui";
    runtimeInputs = [ standalone ];
    text = if hasModuleDeps then ''
      exec ${standalone}/bin/logos-standalone-app --modules-dir "${modulesDir}" "${pluginDir}" "$@"
    '' else ''
      exec ${standalone}/bin/logos-standalone-app "${pluginDir}" "$@"
    '';
  };
in {
  type = "app";
  program = "${run}/bin/run-logos-standalone-ui";
}
