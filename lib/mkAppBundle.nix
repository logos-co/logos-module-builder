# Redistributable binaries for a ui_qml module: the standalone host, the module's
# plugin directory and its dependency modules, laid out so every path resolves
# relative to the executable. nix-bundle-dir turns that tree into a directory that
# runs without Nix; the AppImage and .app wrappers are built from it.
#
# The desktop entry, Info.plist and entitlements are derived from metadata.json,
# so a module only has to supply artwork.
{ pkgs
, lib
, system
, config
, standalone
, layout
, icons
, nix-bundle-dir
, nix-bundle-appimage
, nix-bundle-macos-app
}:

let
  binName = builtins.replaceStrings [ "_" ] [ "-" ] config.name;
  bundleId = "co.logos.${binName}";

  app = pkgs.runCommand "logos-${config.name}-app" {
    version = config.version;
    passthru = {
      extraDirs = [ "modules" "plugin" ];
      # The host declares the Qt modules it only reaches by dlopen; staging its
      # files here would otherwise drop them from the closure a bundler traces.
      extraClosurePaths = standalone.extraClosurePaths or [];
    };
    meta.mainProgram = binName;
  } ''
    mkdir -p $out/bin $out/lib
    cp -aL ${standalone}/bin/. $out/bin/
    cp -aL ${standalone}/lib/. $out/lib/
    cp -aL ${layout.modulesDir} $out/modules
    cp -aL ${layout.pluginDir} $out/plugin
    chmod -R u+w $out

    # Both paths are resolved from the launcher's own location, so the tree
    # keeps working wherever the bundle is unpacked.
    cat > $out/bin/${binName} <<'LAUNCHER'
#!/bin/sh
DIR=$(cd "$(dirname "$0")" && pwd)
exec "$DIR/logos-standalone-app" --modules-dir "$DIR/../modules" "$DIR/../plugin" "$@"
LAUNCHER
    chmod +x $out/bin/${binName}
  '';

  bundle = nix-bundle-dir.bundlers.${system}.qtApp app;

  # builtins.toFile rather than writeText: mkAppImage reads the desktop entry at
  # evaluation time, which would otherwise need import-from-derivation.
  desktopFile = builtins.toFile "${binName}.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=${config.display_name}
    Comment=${config.description}
    Exec=${binName}
    Icon=${binName}
    Categories=Utility;
  '';

  # @VERSION@ and @BUILD_NUMBER@ are substituted by mkMacOSApp.
  infoPlist = builtins.toFile "Info.plist.in" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleDisplayName</key>
        <string>${config.display_name}</string>
        <key>CFBundleExecutable</key>
        <string>${binName}</string>
        <key>CFBundleIconFile</key>
        <string>${builtins.baseNameOf (toString (icons.icns or ""))}</string>
        <key>CFBundleIdentifier</key>
        <string>${bundleId}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>${config.display_name}</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>@VERSION@</string>
        <key>CFBundleVersion</key>
        <string>@BUILD_NUMBER@</string>
        <key>LSMinimumSystemVersion</key>
        <string>12.0</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>NSPrincipalClass</key>
        <string>NSApplication</string>
        <key>NSSupportsAutomaticGraphicsSwitching</key>
        <true/>
        <key>LSApplicationCategoryType</key>
        <string>public.app-category.utilities</string>
    </dict>
    </plist>
  '';

  # The host dlopens bundled Qt plugins and module libraries that the ad-hoc
  # signature does not cover.
  entitlements = builtins.toFile "${binName}.entitlements" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>com.apple.security.cs.disable-library-validation</key>
        <true/>
    </dict>
    </plist>
  '';
in
{
  bin-bundle-dir = bundle;
}
// lib.optionalAttrs (pkgs.stdenv.isLinux && icons ? png) {
  bin-appimage = nix-bundle-appimage.lib.${system}.mkAppImage {
    drv = app;
    name = binName;
    inherit bundle desktopFile;
    icon = icons.png;
  };
}
// lib.optionalAttrs (pkgs.stdenv.isDarwin && icons ? icns) {
  bin-macos-app = nix-bundle-macos-app.lib.${system}.mkMacOSApp {
    drv = app;
    name = binName;
    inherit bundle infoPlist entitlements;
    icon = icons.icns;
  };
}
