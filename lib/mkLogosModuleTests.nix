# mkLogosModuleTests — build and run unit tests for a Logos module
#
# This integrates with logos-test-framework and the module build system.
# Tests are built as a standalone executable using LogosTest.cmake,
# with the SDK in mock mode and optional C library mocking.
#
# Usage in a module's flake.nix:
#
#   checks.${system}.unit-tests = logos-module-builder.lib.mkLogosModuleTests {
#     src = ./.;
#     testDir = ./tests;
#     configFile = ./metadata.json;
#     flakeInputs = inputs;
#     mockCLibs = ["gowalletsdk"];  # optional
#   };
{ nixpkgs, lib, common, parseMetadata, logos-cpp-sdk, logos-test-framework }:

{
  # Required: Path to the module source
  src,

  # Required: Path to the tests directory
  testDir,

  # Optional: Path to metadata.json
  configFile ? null,

  # Optional: All flake inputs — module dependencies resolved from metadata
  flakeInputs ? {},

  # Optional: Additional flake inputs for external libraries (same format as mkLogosModule)
  externalLibInputs ? {},

  # Optional: C libraries to mock (won't link the real lib)
  mockCLibs ? [],

  # Optional: Custom preConfigure hook
  preConfigure ? "",

  # Optional: Extra build inputs
  extraBuildInputs ? [],

  # Optional: Extra CMake flags
  extraCmakeFlags ? [],
}:

let
  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  # Parse config if available
  config = if configFile != null
    then parseMetadata.parseModuleConfig (builtins.readFile configFile)
    else { name = "unknown"; version = "0.0.0"; dependencies = []; };

  checks = forAllSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      testFramework = logos-test-framework.packages.${system}.default;

      # Resolve runtime packages from metadata (e.g. nlohmann_json)
      runtimePkgNames = config.nix_packages.runtime or [];
      runtimePkgs = builtins.filter (p: p != null) (map (name:
        pkgs.${name} or null
      ) runtimePkgNames);

      # Resolve module dependencies
      moduleInputs = lib.filterAttrs (n: _: builtins.elem n config.dependencies) flakeInputs;
      resolvedModuleDeps = lib.mapAttrs (_: input:
        if input ? packages.${system}.default then input.packages.${system}.default else input
      ) moduleInputs;

      # Copy include files from module deps
      depIncludeSetup = lib.concatMapStringsSep "\n" (name:
        let dep = resolvedModuleDeps.${name} or null;
        in if dep != null then ''
          if [ -d "${dep}/include" ]; then
            echo "Copying include files from ${name}..."
            cp -r "${dep}/include"/* ./generated_code/ 2>/dev/null || true
          fi
        '' else ""
      ) config.dependencies;

      # Resolve testDir to a relative path within the source tree.
      # testDir is typically a nix path like ./tests; we need to find
      # which subdirectory name it corresponds to.
      testDirName = builtins.baseNameOf (builtins.toString testDir);

      resolvedExternalLibs = lib.mapAttrs (name: value:
        if builtins.isAttrs value && value ? input
        then value.input.packages.${system}.${value.packages.default or "default"}
        else value
      ) externalLibInputs;

      externalLibRpath = lib.concatMapStringsSep ":" (name:
        "${resolvedExternalLibs.${name}}/lib"
      ) (builtins.attrNames resolvedExternalLibs);

      preConfigureStr =
        if builtins.isFunction preConfigure
        then preConfigure { externalLibs = resolvedExternalLibs; }
        else preConfigure;

    in {
      unit-tests = pkgs.stdenv.mkDerivation {
        pname = "logos-${config.name}-tests";
        version = config.version;

        src = src;

        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          pkg-config
          qt6.wrapQtAppsNoGuiHook
          logosSdk
        ] ++ extraBuildInputs;

        buildInputs = with pkgs; [
          qt6.qtbase
          qt6.qtremoteobjects
          logosSdk
          testFramework
        ] ++ runtimePkgs;

        dontUseCmakeConfigure = true;

        buildPhase = ''
          runHook preBuild

          # Set up generated code directory
          mkdir -p ./generated_code

          # Copy dependency includes
          ${depIncludeSetup}

          # Run logos-cpp-generator if metadata available
          ${lib.optionalString (configFile != null) ''
            if command -v logos-cpp-generator &>/dev/null; then
              echo "Running logos-cpp-generator..."
              logos-cpp-generator --metadata "${configFile}" --general-only --output-dir ./generated_code || true
            fi
          ''}

          # Custom preConfigure hook
          ${preConfigureStr}

          # CMake configure + build from within the source tree
          mkdir -p build && cd build
          cmake ../${testDirName} \
            -DLOGOS_CPP_SDK_ROOT=${logosSdk} \
            -DLOGOS_TEST_FRAMEWORK_ROOT=${testFramework} \
            -DCMAKE_MODULE_PATH=${testFramework}/cmake \
            ${lib.optionalString (externalLibRpath != "") "-DCMAKE_INSTALL_RPATH=${externalLibRpath} -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"} \
            ${lib.concatMapStringsSep " " (f: f) extraCmakeFlags}
          cmake --build . --parallel $NIX_BUILD_CORES

          # Run all test binaries (unit tests first, integration tests last)
          echo "Running ${config.name} tests..."
          {
            find . -maxdepth 1 -type f -executable \( -name "*_tests" -o -name "*_test" \) ! -name "*integration*"
            find . -maxdepth 1 -type f -executable \( -name "*_tests" -o -name "*_test" \) -name "*integration*"
          } | while read bin; do
            echo "Executing: $bin"
            "$bin"
          done

          # Save build directory location for installPhase
          echo "$(pwd)" > /tmp/logos-test-build-dir

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin

          BUILD_DIR="$(cat /tmp/logos-test-build-dir 2>/dev/null || echo build)"
          find "$BUILD_DIR" -maxdepth 1 -type f -executable \( -name "*_tests" -o -name "*_test" \) | while read bin; do
            cp "$bin" $out/bin/
          done
          runHook postInstall
        '';

        doCheck = false;
      };
    }
  );

in checks
