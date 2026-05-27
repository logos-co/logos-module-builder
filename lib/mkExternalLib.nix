# Builder for external libraries
# Handles both flake input and vendor submodule approaches
{ lib, common }:

{
  # Build all external libraries defined in config.
  #
  # `moduleSrc` is the consumer module's `src` (a path or store path). It's
  # only needed when an external_libraries entry uses `vendor_path` together
  # with `build_command`/`build_script` — the vendor build runs as its own
  # derivation with `${moduleSrc}/${vendor_path}` as its src, so it appears
  # in the resulting attrset the same way a flake_input lib does. Pure
  # prebuilt vendor entries (vendor_path with no build_command) still resolve
  # to `null` here; the buildPlugin (or copyExternalLibsToLib) fallback
  # stages them from the module's source tree.
  buildExternalLibs = {
    pkgs,
    config,
    externalInputs ? {},
    moduleSrc ? null,
  }:
  let
    libExt = common.getLibExtension pkgs;

    # Build a single external library
    buildLib = extLib:
      let
        name = extLib.name;

        isFlakeInput = extLib ? flake_input || externalInputs ? ${name};
        isVendor = extLib ? vendor_path;
        isGoBuild = extLib.go_build or false;
        hasBuildStep = (extLib ? build_command) || (extLib ? build_script);

        source =
          if externalInputs ? ${name} then externalInputs.${name}
          else if isVendor && hasBuildStep && moduleSrc != null then
            moduleSrc + "/${extLib.vendor_path}"
          else if isVendor then null
          else throw "External library ${name}: must provide flake input or vendor_path";

        buildCommand = extLib.build_command or "make";
        outputPattern = extLib.output_pattern or "build/lib${name}.*";
        buildScript = extLib.build_script or null;

        # Shared preBuild — exports the env-var contract documented for
        # build_command/build_script (LIB_NAME, LIB_EXT, LIB_BASENAME) so
        # simple one-liners stay portable across darwin/linux.
        sharedPreBuild = ''
          export HOME=$TMPDIR
          export LIB_NAME="${name}"
          if [ "$(uname -s)" = Darwin ]; then
            export LIB_EXT=dylib
          else
            export LIB_EXT=so
          fi
          export LIB_BASENAME="lib${name}.$LIB_EXT"
        '';

        # Build phase dispatcher: a build_script (if specified) takes
        # precedence over build_command. Both run from the unpacked source
        # root with the LIB_* env vars from sharedPreBuild in scope.
        sharedBuildPhase = ''
          runHook preBuild
          echo "Building external library ${name}..."
          ${if buildScript != null then ''
            if [ -f "${buildScript}" ]; then
              bash "${buildScript}"
            else
              echo "Error: Build script ${buildScript} not found"
              exit 1
            fi
          '' else ''
            ${buildCommand}
          ''}
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
          preBuild = sharedPreBuild;
          buildPhase = sharedBuildPhase;
          installPhase = sharedInstallPhase;
          postFixup = sharedPostFixup;

          doCheck = false;
        }
      else if source != null then
        # Plain build from a source path — covers both flake_input libs and
        # vendor_path libs that declared a build_command/build_script. The
        # result lands in $out/lib so downstream copy stages (buildPlugin's
        # externalLibCopies and modulePreConfigure.copyExternalLibsToLib)
        # treat it uniformly with any other built external lib.
        pkgs.stdenv.mkDerivation {
          pname = "logos-external-${name}";
          version = extLib.version or "1.0.0";

          src = source;

          nativeBuildInputs = with pkgs; [ gnumake pkg-config ];
          buildInputs = [];

          preBuild = sharedPreBuild;
          buildPhase = sharedBuildPhase;
          installPhase = sharedInstallPhase;
          postFixup = sharedPostFixup;
        }
      else
        # Pure prebuilt vendor lib (no build_command/build_script) — the
        # binary is expected to live committed in vendor_path. buildPlugin's
        # externalLibCopies stages it from ${src}/${vendor_path} directly.
        null;
    
  in lib.listToAttrs (map (extLib: {
    name = extLib.name;
    value = buildLib extLib;
  }) config.external_libraries);
  
  # Check if module has any external libraries
  hasExternalLibs = config: (config.external_libraries or []) != [];
  
  # Get list of external library names
  getExternalLibNames = config: map (x: x.name) (config.external_libraries or []);
}
