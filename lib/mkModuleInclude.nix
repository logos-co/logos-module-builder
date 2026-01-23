# Builder for module headers (generated from the built plugin)
{ lib, common }:

{
  # Build the include package (generated headers from plugin)
  build = {
    pkgs,
    src,
    config,
    commonArgs,
    logosSdk,
    lib,  # The built module library
  }:
  let
    pluginFilename = common.getPluginFilename pkgs config.name;
    libExt = common.getLibExtension pkgs;
    
  in pkgs.stdenv.mkDerivation {
    pname = "${commonArgs.pname}-headers";
    version = commonArgs.version;
    
    inherit src;
    inherit (commonArgs) meta;
    
    # We need the generator and the built plugin
    nativeBuildInputs = [ logosSdk ];
    
    # No configure phase needed
    dontConfigure = true;
    
    buildPhase = ''
      runHook preBuild
      
      # Create output directory for generated headers
      mkdir -p ./generated_headers
      
      # Determine platform-specific library extension and find plugin
      PLUGIN_FILE=""
      if [ -f "${lib}/lib/${config.name}_plugin.dylib" ]; then
        PLUGIN_FILE="${lib}/lib/${config.name}_plugin.dylib"
      elif [ -f "${lib}/lib/${config.name}_plugin.so" ]; then
        PLUGIN_FILE="${lib}/lib/${config.name}_plugin.so"
      else
        echo "Error: No ${config.name}_plugin library file found in ${lib}/lib/"
        echo "Contents of ${lib}/lib/:"
        ls -la "${lib}/lib/" 2>/dev/null || echo "Directory does not exist"
        exit 1
      fi
      
      # Set library path so the plugin can find dependencies when loaded
      ${if pkgs.stdenv.hostPlatform.isDarwin then ''
        export DYLD_LIBRARY_PATH="${lib}/lib:''${DYLD_LIBRARY_PATH:-}"
      '' else ''
        export LD_LIBRARY_PATH="${lib}/lib:''${LD_LIBRARY_PATH:-}"
      ''}
      
      # Run logos-cpp-generator on the built plugin with --module-only flag
      echo "Running logos-cpp-generator on $PLUGIN_FILE"
      echo "Library path: ${lib}/lib"
      ls -la "${lib}/lib" 2>/dev/null || echo "No lib directory"
      
      logos-cpp-generator "$PLUGIN_FILE" --output-dir ./generated_headers --module-only || {
        echo "Warning: logos-cpp-generator failed, this may be expected if the module has no public API"
        # Create a marker file to indicate attempt was made
        touch ./generated_headers/.no-api
      }
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      # Install generated headers
      mkdir -p $out/include
      
      # Copy all generated files to include/ if they exist
      if [ -d ./generated_headers ] && [ "$(ls -A ./generated_headers 2>/dev/null)" ]; then
        echo "Copying generated headers..."
        ls -la ./generated_headers
        cp -r ./generated_headers/* $out/include/
      else
        echo "Warning: No generated headers found, creating empty include directory"
        # Create a placeholder file to indicate headers should be generated from metadata
        echo "# Generated headers from metadata.json" > $out/include/.generated
      fi
      
      runHook postInstall
    '';
  };
}
