# Builder for external libraries
# Handles both flake input and vendor submodule approaches
{ lib, common }:

{
  # Build all external libraries defined in config
  buildExternalLibs = {
    pkgs,
    config,
    externalInputs ? {},
  }:
  let
    libExt = common.getLibExtension pkgs;
    
    # Build a single external library
    buildLib = extLib:
      let
        name = extLib.name;
        
        # Check if this is a flake input or vendor submodule
        isFlakeInput = extLib ? flake_input || externalInputs ? ${name};
        isVendor = extLib ? vendor_path;
        
        # Get the source
        source = 
          if externalInputs ? ${name} then externalInputs.${name}
          else if isVendor then null  # Will be handled in build phase
          else throw "External library ${name}: must provide flake input or vendor_path";
        
        buildCommand = extLib.build_command or "make";
        outputPattern = extLib.output_pattern or "build/lib${name}.*";
        buildScript = extLib.build_script or null;
        
      in if isFlakeInput && source != null then
        # Build from flake input
        pkgs.stdenv.mkDerivation {
          pname = "logos-external-${name}";
          version = "1.0.0";
          
          src = source;
          
          nativeBuildInputs = with pkgs; [
            gnumake
            pkg-config
          ] ++ lib.optionals (extLib ? go_build && extLib.go_build) [
            pkgs.go
          ];
          
          buildInputs = [];
          
          # Set up build environment
          preBuild = ''
            export HOME=$TMPDIR
            ${lib.optionalString (extLib ? go_build && extLib.go_build) ''
              export GOCACHE=$TMPDIR/go-cache
              export GOPATH=$TMPDIR/go
              export CGO_ENABLED=1
              mkdir -p $GOCACHE $GOPATH
            ''}
          '';
          
          buildPhase = ''
            runHook preBuild
            
            echo "Building external library ${name}..."
            ${buildCommand}
            
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/lib $out/include
            
            # Find and copy library files
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
            
            # Verify we got something
            if [ -z "$(ls -A $out/lib 2>/dev/null)" ]; then
              echo "Warning: No library files found for ${name}"
              echo "Build directory contents:"
              find . -name "*.so" -o -name "*.dylib" -o -name "*.a" 2>/dev/null || true
            fi
            
            runHook postInstall
          '';
          
          # Fix library paths on macOS
          postFixup = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            for lib in $out/lib/*.dylib; do
              if [ -f "$lib" ]; then
                libname=$(basename "$lib")
                ${pkgs.darwin.cctools}/bin/install_name_tool -id "@rpath/$libname" "$lib" 2>/dev/null || true
              fi
            done
          '';
        }
      else
        # Vendor submodule - return null, will be handled in preConfigure of main build
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
