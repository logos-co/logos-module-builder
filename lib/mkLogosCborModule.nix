# Builder for CBOR C++ modules (cbor-exe and cbor-plugin backends).
# These modules are built WITHOUT Qt, linking only against
# logos_value + logos_cbor_server from the Qt-free SDK subset.
{ nixpkgs, logos-cpp-sdk, nix-bundle-lgx, lib, common, parseMetadata, builderRoot }:

{
  # Required: Path to the module source
  src,

  # Required: Path to the metadata.json configuration file
  configFile,

  # Optional: all flake inputs — dependencies in metadata.json are resolved automatically
  flakeInputs ? {},

  # Optional: Extra build inputs to add
  extraBuildInputs ? [],

  # Optional: Extra native build inputs to add
  extraNativeBuildInputs ? [],

  # Optional: Override any config values
  configOverrides ? {},

  # Optional: Custom preConfigure hook
  preConfigure ? "",

  # Optional: Custom postInstall hook
  postInstall ? "",
}:

let
  # Parse the module configuration
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  packages = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdkCbor = logos-cpp-sdk.packages.${system}.logos-cpp-sdk-cbor;
      logosSdkBin = logos-cpp-sdk.packages.${system}.logos-cpp-bin;

      buildPkgs   = map (name: lib.getAttrFromPath (lib.splitString "." name) pkgs)
                        (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (name: lib.getAttrFromPath (lib.splitString "." name) pkgs)
                        (lib.filter builtins.isString config.nix_packages.runtime);

      # Determine build mode from backend
      mode = if config.backend == "cbor-exe" then "exe" else "plugin";

      moduleLib = pkgs.stdenv.mkDerivation {
        pname = "logos-${config.name}-cbor-module";
        version = config.version;
        inherit src;

        nativeBuildInputs = [
          pkgs.cmake
          pkgs.ninja
          pkgs.pkg-config
          logosSdkBin      # for logos-cpp-generator
        ] ++ extraNativeBuildInputs ++ buildPkgs;

        buildInputs = [
          logosSdkCbor     # Qt-free logos_value + logos_cbor_server
        ] ++ extraBuildInputs ++ runtimePkgs;

        # No Qt hooks — this is intentionally Qt-free.

        cmakeFlags = [
          "-GNinja"
          "-DLOGOS_CPP_SDK_CBOR_ROOT=${logosSdkCbor}"
          "-DLOGOS_MODULE_BUILDER_ROOT=${builderRoot}"
        ];

        env = {
          LOGOS_CPP_SDK_CBOR_ROOT = "${logosSdkCbor}";
          LOGOS_MODULE_BUILDER_ROOT = "${builderRoot}";
        };

        preConfigure = ''
          runHook prePreConfigure

          # Create generated_code directory for generated files
          mkdir -p ./generated_code

          # Run logos-cpp-generator for CBOR backend
          echo "Running logos-cpp-generator for ${config.backend} backend..."
          if [ -f metadata.json ]; then
            logos-cpp-generator --metadata metadata.json --general-only --output-dir ./generated_code || true
          fi

          # Run any custom preConfigure hook
          ${preConfigure}

          runHook postPreConfigure
        '';

        installPhase = ''
          runHook preInstall

          ${if mode == "exe" then ''
            # cbor-exe: install the standalone executable
            mkdir -p $out/bin $out/lib
            if [ -f bin/${config.name} ]; then
              cp bin/${config.name} $out/bin/
            elif [ -f ${config.name} ]; then
              cp ${config.name} $out/bin/
            else
              echo "Error: No executable found for ${config.name}"
              find . -type f -executable 2>/dev/null || true
              exit 1
            fi
            # Copy metadata.json alongside the binary
            if [ -f "${src}/metadata.json" ]; then
              cp "${src}/metadata.json" $out/lib/
            fi
          '' else ''
            # cbor-plugin: install the shared library
            mkdir -p $out/lib
            if [ -f modules/${config.name}_plugin.so ]; then
              cp modules/${config.name}_plugin.so $out/lib/
            elif [ -f modules/${config.name}_plugin.dylib ]; then
              cp modules/${config.name}_plugin.dylib $out/lib/
            elif [ -f ${config.name}_plugin.so ]; then
              cp ${config.name}_plugin.so $out/lib/
            elif [ -f ${config.name}_plugin.dylib ]; then
              cp ${config.name}_plugin.dylib $out/lib/
            else
              echo "Error: No plugin library found for ${config.name}"
              find . -name "*_plugin.*" -type f 2>/dev/null || true
              exit 1
            fi
          ''}

          # Copy metadata.json for module discovery
          if [ -f "${src}/metadata.json" ]; then
            cp "${src}/metadata.json" $out/lib/metadata.json 2>/dev/null || true
          fi

          # Install generated include files
          if [ -d "./generated_code/include" ]; then
            mkdir -p $out/include
            cp -r ./generated_code/include/* $out/include/
          fi

          # Platform-specific library path fixes
          ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            for dylib in $out/lib/*.dylib; do
              if [ -f "$dylib" ]; then
                libname=$(basename "$dylib")
                ${pkgs.darwin.cctools}/bin/install_name_tool -id "@rpath/$libname" "$dylib" 2>/dev/null || true
              fi
            done
          ''}

          # Run any custom postInstall hook
          ${postInstall}

          runHook postInstall
        '';

        meta = with lib; {
          description = config.description;
          platforms = platforms.unix;
        };
      };

    in {
      default = moduleLib;
      lib = moduleLib;
    }
  );

  # LGX package outputs
  nixBundleLgx = nix-bundle-lgx;

  optionalLgx = {
    packages = forAllSystems (system:
      let
        bundleLgx = nixBundleLgx.bundlers.${system}.default;
        bundleLgxPortable = nixBundleLgx.bundlers.${system}.portable;
        moduleLib = packages.${system}.lib;
      in {
        lgx = bundleLgx moduleLib;
        lgx-portable = bundleLgxPortable moduleLib;
      }
    );
  };

  mergedPackages = lib.mapAttrs (system: sysPkgs:
    sysPkgs // (optionalLgx.packages.${system} or {})
  ) packages;

  devShells = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdkCbor = logos-cpp-sdk.packages.${system}.logos-cpp-sdk-cbor;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config ];
        buildInputs = [ logosSdkCbor ];

        shellHook = ''
          export LOGOS_CPP_SDK_CBOR_ROOT="${logosSdkCbor}"
          export LOGOS_MODULE_BUILDER_ROOT="${builderRoot}"
          echo "Logos ${config.name} CBOR module development environment"
        '';
      };
    }
  );

in {
  packages = mergedPackages;
  inherit devShells config;
  metadataJson = builtins.readFile configFile;
}
