# Builder for external libraries
# Handles both flake input and vendor submodule approaches
{ lib, common }:

{
  # Build all external libraries defined in config
  buildExternalLibs = {
    pkgs,
    config,
    externalInputs ? {},
    # Module source root — needed to locate vendored binaries committed in the
    # repo. When the vendor dir holds per-platform subdirectories, we read the
    # one matching this build's system from here.
    src ? null,
  }:
  let
    libExt = common.getLibExtension pkgs;
    # Target system (e.g. "aarch64-darwin"). Keyed off the package set so it is
    # the system we are building FOR, not the eval host — never builtins.currentSystem.
    system = pkgs.stdenv.hostPlatform.system;

    # Build a single external library
    buildLib = extLib:
      let
        name = extLib.name;

        isFlakeInput = extLib ? flake_input || externalInputs ? ${name};
        isVendor = extLib ? vendor_path;
        isGoBuild = extLib.go_build or false;

        # Per-platform vendored binaries: a vendor dir may hold subdirectories
        # named by Nix system (e.g. lib/x86_64-linux/, lib/aarch64-darwin/) so
        # that platforms sharing a library extension (linux x86_64 vs aarch64,
        # both .so) can ship side by side. We pick the subdir matching `system`.
        # Shared headers stay flat in the vendor dir; only the binary is selected.
        platSubdir =
          if src != null && isVendor
          then "${src}/${extLib.vendor_path}/${system}"
          else null;
        hasPlatSubdir = platSubdir != null && builtins.pathExists platSubdir;

        source =
          if externalInputs ? ${name} then externalInputs.${name}
          else if isVendor then null
          else throw "External library ${name}: must provide flake input or vendor_path";

        buildCommand = extLib.build_command or "make";
        outputPattern = extLib.output_pattern or "build/lib${name}.*";
        buildScript = extLib.build_script or null;

        # Shared buildPhase — runs whatever the module asked for.
        sharedBuildPhase = ''
          runHook preBuild
          echo "Building external library ${name}..."
          ${buildCommand}
          runHook postBuild
        '';

        # Shared installPhase — locate lib/header artifacts wherever they
        # landed and copy into $out. Used by both the Go and non-Go paths so
        # output_pattern/conventions stay consistent.
        sharedInstallPhase = ''
          runHook preInstall

          mkdir -p $out/lib $out/include

          echo "Looking for library files matching: ${outputPattern}"

          # Try common patterns
          for pattern in \
            "build/lib${name}.${libExt}" \
            "build/lib${name}.so" \
            "build/lib${name}.dylib" \
            "build/lib${name}.a" \
            "lib${name}.${libExt}" \
            "lib${name}.so" \
            "lib${name}.dylib" \
            "lib${name}.a" \
            ; do
            for f in $pattern; do
              if [ -f "$f" ]; then
                echo "Found: $f"
                cp "$f" $out/lib/
              fi
            done
          done

          # Copy header files if they exist
          for pattern in "build/*.h" "include/*.h" "*.h"; do
            for f in $pattern; do
              if [ -f "$f" ]; then
                cp "$f" $out/include/
              fi
            done
          done

          if [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
            echo "Warning: No library files found for ${name}"
            echo "Build directory contents:"
            find . -name "*.so" -o -name "*.dylib" -o -name "*.a" 2>/dev/null || true
          fi

          runHook postInstall
        '';

        sharedPostFixup = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          for lib in $out/lib/*.dylib; do
            if [ -f "$lib" ]; then
              libname=$(basename "$lib")
              ${pkgs.darwin.cctools}/bin/install_name_tool -id "@rpath/$libname" "$lib" 2>/dev/null || true
            fi
          done
        '';

      in if source != null && lib.isDerivation source then
        # Already a Nix derivation (resolved package output) — use directly
        source
      else if isFlakeInput && source != null && isGoBuild then
        # Go build: delegate to buildGoModule so Go dependencies are vendored
        # via a fixed-output derivation (the only way to get network access in
        # the nix sandbox). The module provides vendor_hash in metadata.json.
        let
          vendorHash = extLib.vendor_hash or (throw ''
            External library "${name}" has go_build = true but no vendor_hash
            set in metadata.json. Add:

              "vendor_hash": "sha256-..."

            to the external_libraries entry. To discover the correct value,
            set it to an empty string and nix will fail with the expected hash.
          '');
          modRoot = extLib.mod_root or "./";
        in pkgs.buildGoModule {
          pname = "logos-external-${name}";
          version = extLib.version or "1.0.0";

          src = source;
          inherit vendorHash modRoot;

          nativeBuildInputs = with pkgs; [ gnumake pkg-config ];

          # buildGoModule defaults to `go build ./...`; we want the module's
          # own build_command (e.g. `make static-library`) to run instead.
          buildPhase = sharedBuildPhase;
          installPhase = sharedInstallPhase;
          postFixup = sharedPostFixup;

          doCheck = false;
        }
      else if isFlakeInput && source != null then
        # Plain build from flake input source (no Go vendoring needed)
        pkgs.stdenv.mkDerivation {
          pname = "logos-external-${name}";
          version = extLib.version or "1.0.0";

          src = source;

          nativeBuildInputs = with pkgs; [ gnumake pkg-config ];
          buildInputs = [];

          preBuild = ''
            export HOME=$TMPDIR
          '';

          buildPhase = sharedBuildPhase;
          installPhase = sharedInstallPhase;
          postFixup = sharedPostFixup;
        }
      else if hasPlatSubdir then
        # Per-platform vendored binary: copy the matching system's library into
        # a derivation so it flows through the same staging path as flake-input
        # libs (logos-plugin-qt buildPlugin copies $out/lib into the module's
        # lib/, where CMake find_library picks it up). Headers stay flat in the
        # vendor dir and are NOT copied here.
        pkgs.runCommand "logos-external-${name}-${system}" {} ''
          mkdir -p $out/lib
          shopt -s nullglob
          for f in ${platSubdir}/lib${name}.* ${platSubdir}/${name}.*; do
            [ -f "$f" ] && cp "$f" $out/lib/
          done
          if [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
            echo "Error: no library matching lib${name}.* found in ${platSubdir}"
            exit 1
          fi
        ''
      else
        # Vendor submodule (flat, single-platform) - return null, staged from
        # src in the main build's preConfigure.
        null;
    
  in lib.listToAttrs (map (extLib: {
    name = extLib.name;
    value = buildLib extLib;
  }) config.external_libraries);
  
  # Generate shell script for building vendor submodule libraries
  # This is used in preConfigure when vendor_path is specified
  generateVendorBuildScript = { config, extLib }:
    let
      name = extLib.name;
      vendorPath = extLib.vendor_path;
      buildScript = extLib.build_script or null;
      buildCommand = extLib.build_command or "make";
    in ''
      echo "Building vendor library ${name} from ${vendorPath}..."
      
      if [ -d "${vendorPath}" ]; then
        pushd "${vendorPath}"
        
        ${if buildScript != null then ''
          # Use custom build script
          if [ -f "../${buildScript}" ]; then
            bash "../${buildScript}"
          elif [ -f "${buildScript}" ]; then
            bash "${buildScript}"
          else
            echo "Error: Build script ${buildScript} not found"
            exit 1
          fi
        '' else ''
          # Use build command
          ${buildCommand}
        ''}
        
        popd
        
        # Copy built libraries to lib/
        mkdir -p lib
        find "${vendorPath}" -name "lib${name}.*" -exec cp {} lib/ \; 2>/dev/null || true
      else
        echo "Warning: Vendor path ${vendorPath} does not exist"
      fi
    '';
  
  # Check if module has any external libraries
  hasExternalLibs = config: (config.external_libraries or []) != [];
  
  # Get list of external library names
  getExternalLibNames = config: map (x: x.name) (config.external_libraries or []);
}
