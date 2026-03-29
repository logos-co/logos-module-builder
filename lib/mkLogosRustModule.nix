# Builder for Rust CBOR modules.
# Uses rustPlatform.buildRustPackage with logos_runtime as a dependency.
# The generated Rust source (from logos-cpp-generator --backend rust) is
# expected to already be in the module's src/ directory.
{ nixpkgs, logos-cpp-sdk, nix-bundle-lgx, lib, common, parseMetadata }:

{
  # Required: Path to the module source (must contain Cargo.toml)
  src,

  # Required: Path to the metadata.json configuration file
  configFile,

  # Required: Cargo dependency hash (from nix build, or lib.fakeHash for first build)
  cargoHash ? lib.fakeHash,

  # Optional: all flake inputs — dependencies in metadata.json are resolved automatically
  flakeInputs ? {},

  # Optional: Extra build inputs to add
  extraBuildInputs ? [],

  # Optional: Extra native build inputs to add
  extraNativeBuildInputs ? [],

  # Optional: Override any config values
  configOverrides ? {},

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

      buildPkgs   = map (name: lib.getAttrFromPath (lib.splitString "." name) pkgs)
                        (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (name: lib.getAttrFromPath (lib.splitString "." name) pkgs)
                        (lib.filter builtins.isString config.nix_packages.runtime);

      moduleLib = pkgs.rustPlatform.buildRustPackage {
        pname = "logos-${config.name}-rust-module";
        version = config.version;
        inherit src cargoHash;

        nativeBuildInputs = [
          pkgs.pkg-config
        ] ++ extraNativeBuildInputs ++ buildPkgs;

        buildInputs = extraBuildInputs ++ runtimePkgs;

        postInstall = ''
          # Install metadata.json for module discovery
          mkdir -p $out/lib
          if [ -f "${src}/metadata.json" ]; then
            cp "${src}/metadata.json" $out/lib/metadata.json
          fi

          # Move the binary to bin/ (buildRustPackage does this by default)
          # The binary is the module executable for cbor-exe backend
          ${postInstall}
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
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.cargo
          pkgs.rustc
          pkgs.pkg-config
        ];

        shellHook = ''
          echo "Logos ${config.name} Rust module development environment"
        '';
      };
    }
  );

in {
  packages = mergedPackages;
  inherit devShells config;
  metadataJson = builtins.readFile configFile;
}
