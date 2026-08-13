# Shared C++ plugin build pipeline — encapsulates config parsing, dependency
# resolution, plugin compilation (via backend), header generation, dev shells,
# and LGX bundling.  Callers (mkLogosModule, mkLogosQmlModule) compose final
# `packages` and `apps` outputs differently.
{ nixpkgs, lib, common, parseMetadata, logos-cpp-sdk, logos-protocol ? null, logos-qt-sdk ? null, logos-module, uiBackend, coreBackend, nix-bundle-lgx, nix-bundle-logos-module-install }:

{
  src,
  configFile,
  flakeInputs ? {},
  externalLibInputs ? {},
  extraBuildInputs ? [],
  extraNativeBuildInputs ? [],
  configOverrides ? {},
  preConfigure ? "",
  postInstall ? "",
}:

let
  # Parse the module configuration
  rawConfig = parseMetadata.parseModuleConfig (builtins.readFile configFile);
  config = common.recursiveMerge [ rawConfig configOverrides ];

  # Select backend based on module type: core modules are swappable, UI stays Qt
  selectedBackend =
    if config.type == "core" then coreBackend
    else uiBackend;

  mkExternalLib = import ./mkExternalLib.nix { inherit lib common; };

  getPkg = pkgs: name:
    let evaluatedName = builtins.seq name name;
    in if builtins.isString evaluatedName
       then lib.getAttrFromPath (lib.splitString "." evaluatedName) pkgs
       else builtins.throw "getPkg expected string but got ${builtins.typeOf evaluatedName}";

  forAllSystems = f: lib.genAttrs common.systems (system: f system);

  # Per-system build outputs
  perSystem = forAllSystems (system:
    let
      pkgs = common.mkPkgs system;

      # ── Concrete dependency classification (mirrors mkLogosModule.nix) ──────
      # LIDL-based deps → bindings generated from the dep's published `lidl`
      # output (no dep plugin build). Deps without a `lidl` output take the
      # TRANSITIONAL header-copy fallback below (which builds them).
      # Guard every level so a non-flake / raw-derivation dep input returns
      # null (→ TRANSITIONAL header-copy fallback) rather than throwing.
      depLidlOf = name:
        let i = flakeInputs.${name} or null;
        in if i != null && i ? packages && i.packages ? ${system}
           then (i.packages.${system}.lidl or null)
           else null;
      depIsLidl = name: (config.dependency_overrides ? ${name}) || (depLidlOf name != null);
      staticDeps = map (name:
        let ov = config.dependency_overrides.${name} or null;
        in if ov != null then {
             inherit name;
             impl_class = ov.impl_class;
             path = if ov.input != null
                    then (if flakeInputs ? ${ov.input}
                          then "${flakeInputs.${ov.input}}/${ov.file}"
                          else throw "dependency_overrides.${name}: flake input '${ov.input}' was not passed to mkLogosQmlModule.")
                    else "${src}/${ov.file}";
           } else {
             inherit name;
             impl_class = null;
             path = "${depLidlOf name}/${name}.lidl";
           }
      ) (lib.filter depIsLidl config.dependencies);
      legacyHeaderDepNames = lib.filter (name: !(depIsLidl name)) config.dependencies;

      # Resolve the TRANSITIONAL header-copy deps from inputs. Each entry is a
      # struct exposing the dep's plugin (.lib) plus the header variants
      # (.headers-qt / .headers-lp) so the plugin builder can pick the one
      # matching its own --api-style. See the matching block in mkLogosModule.nix
      # for the full rationale + fallback chain. Remove once all deps publish LIDL.
      # Everything built through here is a view module (type: ui_qml), which
      # buildPlugin.nix always types "qt" — the `headers-lp` entry exists so an
      # lp consumer that ever reaches this path fails with a real message
      # instead of a "cannot coerce a set to a string" from the header copy.
      moduleInputs = lib.filterAttrs (n: _: builtins.elem n legacyHeaderDepNames) flakeInputs;
      resolvedModuleDeps = lib.mapAttrs (depName: input:
        let
          ps = input.packages.${system} or null;
          fallback = if input ? packages.${system}.default
                     then input.packages.${system}.default else input;
          staleLpDep = reason: throw ''
            logos-module-builder: dependency '${depName}' cannot be consumed by an lp (Qt-free) module.

            '${depName}' is taking the transitional header-copy path (it publishes
            no `lidl` output), and
              ${reason}.
            So the only headers it offers are Qt-typed. Copying those into a
            Qt-free translation unit fails deep inside a generated source file
            with a wall of unrelated-looking Qt type errors, so this build stops
            here instead.

            Fix: rebuild / re-pin '${depName}' against a current logos-module-builder.
            Any module built by one publishes a `lidl` contract (preferred — it
            skips the header copy entirely) as well as a `headers-lp` output.
          '';
        in
        if ps != null then {
          default     = ps.default;
          lib         = ps.lib or ps.default;
          headers-qt  = ps.headers-qt or ps.include or ps.default;
          headers-lp  = ps.headers-lp or (staleLpDep "its packages.${system} exposes no `headers-lp`");
        } else {
          default     = fallback;
          lib         = fallback;
          headers-qt  = fallback;
          headers-lp  = staleLpDep "the flake input is a bare derivation with no packages.${system} attrset";
        }
      ) moduleInputs;

      # Resolve interface dependencies (method/event contracts) to concrete
      # definition-file paths — the same resolution mkLogosModule.nix does, for
      # the same reason: the generators must never touch flake inputs, they just
      # receive `<name>=<path>[=<impl_class>]`.
      #
      # This used to be omitted here, and a QML module's interfaces reached the
      # generator only through logos-cpp-generator's own fallback (it re-reads
      # metadata.json and resolves LOCAL entries relative to it). That fallback
      # SKIPS any entry with an `input`, so a cross-repo interface silently lost
      # its `bind_<name>` factory; and it is invisible to logos-plugin-qt, which
      # now emits the Qt-typed wrapper itself and can only do so for the
      # interfaces it was told about.
      resolvedInterfaceDeps = map (e: {
        inherit (e) name impl_class;
        path = if e.input != null
               then (if flakeInputs ? ${e.input}
                     then "${flakeInputs.${e.input}}/${e.file}"
                     else throw "interface_dependencies: interface '${e.name}' references flake input '${e.input}', but no such input was passed to mkLogosQmlModule (declare it in flake.nix and pass it via flakeInputs).")
               else "${src}/${e.file}";
      }) config.interface_dependencies;

      # Resolve a single externalLibInputs entry for a given variant.
      # Supports both simple (bare flake input) and structured ({ input, packages }) formats.
      resolveExtInput = variant: name: value:
        if builtins.isAttrs value && value ? input then
          let
            flakeInput = value.input;
            packages = value.packages or {};
            pkgName = packages.${variant} or packages.default or "default";
          in
            if flakeInput ? packages.${system}.${pkgName}
            then flakeInput.packages.${system}.${pkgName}
            else builtins.throw ''
              External lib "${name}": flake input does not provide packages.${system}.${pkgName}.
              Check the "externalLibInputs" structured entry and ensure the flake input exposes the expected package.
            ''
        else
          if value ? packages.${system}.default then value.packages.${system}.default else value;

      # Whether any external lib input declares per-variant packages
      hasVariants = lib.any (v: builtins.isAttrs v && v ? input && v ? packages)
        (lib.attrValues externalLibInputs);

      # Resolve SDK deps for this system — injected into the backend
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      # Build-platform half of the SDK. logos-cpp-generator is invoked by BARE
      # NAME from a build phase (logos-plugin-qt/lib/buildPlugin.nix:145), so it
      # must run on the builder. Under cross, packages.x86_64-windows.default
      # carries no runnable generator at all -- logos-cpp-sdk/nix/bin.nix:39
      # silently skips the mingw .exe -- hence "command not found".
      #
      # `logosSdk` deliberately stays TARGET-typed: it is ALSO the header and
      # CMake-package root passed to LOGOS_CPP_SDK_ROOT, and those must keep
      # coming from the Windows set. Splitting the two roles is the whole point;
      # pointing the headers at the build system would produce a build that
      # SUCCEEDS while linking the wrong architecture.
      #
      # buildSystemFor is the identity on every native system, so this is a
      # no-op off the Windows target.
      logosSdkBuild = logos-cpp-sdk.packages.${common.buildSystemFor system}.default;
      logosQtSdk = logos-qt-sdk.packages.${system}.default;
      # The Qt glue generator (universal/cdylib/ui backends) — Qt code is
      # the Qt layer's product; logos-cpp-generator keeps Qt-free outputs.
      logosQtGenerator = logos-qt-sdk.packages.${common.buildSystemFor system}.logos-qt-generator;
      logosProtocolPkg = logos-protocol.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;

      # The logos-protocol semver — parsed from the protocol header the
      # whole stack links. Stamped into every module's embedded metadata
      # (see modulePreConfigure.stampProtocolVersion). null (no stamp) only
      # if the input is somehow absent — modules then load as "legacy".
      protocolVersion =
        if logos-protocol == null then null
        else
          let
            header = builtins.readFile "${logos-protocol}/cpp/logos_protocol.h";
            parts = builtins.split "LOGOS_PROTOCOL_VERSION_STRING \"([^\"]*)\"" header;
          in if builtins.length parts < 2 then null
             else builtins.head (builtins.elemAt parts 1);


      modulePreConfigure = import ./modulePreConfigure.nix { inherit lib; };

      buildPkgs   = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.build);
      runtimePkgs = map (getPkg pkgs) (lib.filter builtins.isString config.nix_packages.runtime);

      # Pre-resolve default variant external libs (always needed, avoids
      # duplicate evaluation when hasVariants triggers a second buildVariant).
      defaultResolvedExternalLibs = lib.mapAttrs (resolveExtInput "default") externalLibInputs;
      defaultExternalLibs = mkExternalLib.buildExternalLibs {
        inherit pkgs config src;
        externalInputs = defaultResolvedExternalLibs;
      };

      hasBuilderCmake = builtins.pathExists (src + "/cmake/LogosModule.cmake");

      goCmakeFlags = lib.optionals (config.go_static_lib_names or [] != []) [
        "-DLOGOS_MODULE_GO_STATIC_LIBS=${lib.concatStringsSep ";" config.go_static_lib_names}"
      ];

      # Backend arguments for a given external-lib variant ("default" or
      # "portable"). Shared by buildVariant (compiles) and the generate output
      # (snapshots the post-codegen source tree) so both use identical inputs.
      mkPluginArgs = variant:
        let
          externalLibs =
            if variant == "default" then defaultExternalLibs
            else mkExternalLib.buildExternalLibs {
              inherit pkgs config src;
              externalInputs = lib.mapAttrs (resolveExtInput variant) externalLibInputs;
            };

          userPreConfigure =
            if builtins.isFunction preConfigure
            then preConfigure { inherit externalLibs; }
            else preConfigure;

          preConfigureStr = modulePreConfigure.compose {
            inherit config externalLibs protocolVersion;
            userPre = userPreConfigure;
            fixDarwin = false;
            copyExternals = false;
          };
        in ({
          inherit pkgs src config postInstall logosModule;
          preConfigure = preConfigureStr;
          moduleDeps = resolvedModuleDeps;
          inherit externalLibs;
          # pkgs.jq is target-typed too and jq runs in preConfigure
          # (modulePreConfigure.nix:203). buildPackages == pkgs natively.
          extraNativeBuildInputs = extraNativeBuildInputs ++ buildPkgs ++ [ logosSdkBuild logosQtGenerator pkgs.buildPackages.jq ];
          extraBuildInputs = extraBuildInputs ++ runtimePkgs ++ [ logosQtSdk logosProtocolPkg ];
          # Qt splits each module's TOOLS (repc, moc, qmltyperegistrar) into a
          # SEPARATE package that must run on the BUILD machine. Without these
          # flags find_package(Qt6 COMPONENTS RemoteObjects) fails on a
          # thoroughly misleading message -- it names Qt6RemoteObjects, but the
          # TARGET config is found fine; it is Qt6RemoteObjectsTools that is
          # missing. logos-nix's Windows overlay exposes the flags; the
          # attribute is absent (and so `or []`) on a native build, which is why
          # this needs no isWindows guard.
          extraCmakeFlags = (pkgs.logosQtCrossCmakeFlags or [ ]) ++ [
            "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
            "-DLOGOS_QT_SDK_ROOT=${logosQtSdk}"
            "-DLOGOS_PROTOCOL_ROOT=${logosProtocolPkg}"
          ] ++ goCmakeFlags;
          extraEnv = {
            LOGOS_CPP_SDK_ROOT = "${logosSdk}";
            LOGOS_QT_SDK_ROOT = "${logosQtSdk}";
            LOGOS_PROTOCOL_ROOT = "${logosProtocolPkg}";
          } // lib.optionalAttrs hasBuilderCmake {
            LOGOS_MODULE_BUILDER_ROOT = "${src}";
          };
        }
        # Only pass interfaceDeps when the module declares any — keeps existing
        # modules buildable against a backend that predates the feature.
        // lib.optionalAttrs (config.interface_dependencies != []) {
          interfaceDeps = resolvedInterfaceDeps;
        }
        # LIDL-based concrete deps → `--dep` flags (no dep plugin build).
        // lib.optionalAttrs (staticDeps != []) {
          inherit staticDeps;
        });

      # Compile the plugin for a variant (delegated to the backend).
      buildVariant = variant: selectedBackend.buildPlugin (mkPluginArgs variant);

      moduleLib = buildVariant "default";
      moduleLibPortable = if hasVariants then buildVariant "portable" else null;

      # Ready-to-build source tree: same backend args as the default plugin
      # build, but the backend runs the generators and snapshots the result
      # instead of compiling. Matches a real build.
      moduleGenerate = selectedBackend.generate (mkPluginArgs "default");

      # Delegate header generation to the backend
      moduleInclude = selectedBackend.buildHeaders {
        inherit pkgs src config;
        # buildHeaders uses this ONLY to put the generator on PATH
        # (logos-plugin-qt/lib/buildHeaders.nix:44) -- a pure tool role.
        logosSdk = logosSdkBuild;
        pluginLib = moduleLib;
      };

    in {
      inherit pkgs moduleLib moduleLibPortable moduleInclude hasVariants moduleGenerate;
    }
  );

  # Development shell (delegates to backend for deps)
  devShells = forAllSystems (system:
    let
      pkgs = common.mkPkgs system;
      logosSdk = logos-cpp-sdk.packages.${system}.default;
      # Build-platform half of the SDK. logos-cpp-generator is invoked by BARE
      # NAME from a build phase (logos-plugin-qt/lib/buildPlugin.nix:145), so it
      # must run on the builder. Under cross, packages.x86_64-windows.default
      # carries no runnable generator at all -- logos-cpp-sdk/nix/bin.nix:39
      # silently skips the mingw .exe -- hence "command not found".
      #
      # `logosSdk` deliberately stays TARGET-typed: it is ALSO the header and
      # CMake-package root passed to LOGOS_CPP_SDK_ROOT, and those must keep
      # coming from the Windows set. Splitting the two roles is the whole point;
      # pointing the headers at the build system would produce a build that
      # SUCCEEDS while linking the wrong architecture.
      #
      # buildSystemFor is the identity on every native system, so this is a
      # no-op off the Windows target.
      logosSdkBuild = logos-cpp-sdk.packages.${common.buildSystemFor system}.default;
      logosQtSdk = logos-qt-sdk.packages.${system}.default;
      # The Qt glue generator (universal/cdylib/ui backends) — Qt code is
      # the Qt layer's product; logos-cpp-generator keeps Qt-free outputs.
      logosQtGenerator = logos-qt-sdk.packages.${common.buildSystemFor system}.logos-qt-generator;
      logosProtocolPkg = logos-protocol.packages.${system}.default;
      logosModule = logos-module.packages.${system}.default;

      # The logos-protocol semver — parsed from the protocol header the
      # whole stack links. Stamped into every module's embedded metadata
      # (see modulePreConfigure.stampProtocolVersion). null (no stamp) only
      # if the input is somehow absent — modules then load as "legacy".
      protocolVersion =
        if logos-protocol == null then null
        else
          let
            header = builtins.readFile "${logos-protocol}/cpp/logos_protocol.h";
            parts = builtins.split "LOGOS_PROTOCOL_VERSION_STRING \"([^\"]*)\"" header;
          in if builtins.length parts < 2 then null
             else builtins.head (builtins.elemAt parts 1);

      backendShell = selectedBackend.devShellInputs pkgs { inherit logosModule; };
      buildPkgs = map (getPkg pkgs) config.nix_packages.build;
      runtimePkgs = map (getPkg pkgs) config.nix_packages.runtime;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = backendShell.nativeBuildInputs ++ buildPkgs;
        buildInputs = backendShell.buildInputs ++ runtimePkgs;
        shellHook = ''
          ${backendShell.shellHook}
          echo "Logos ${config.name} module development environment"
          echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
          echo "LOGOS_MODULE_ROOT: $LOGOS_MODULE_ROOT"
          echo "LOGOS_MODULE_BUILDER_ROOT: $LOGOS_MODULE_BUILDER_ROOT"
        '';
      };
    }
  );

  # LGX package outputs (nix-bundle-lgx provided by the builder)
  lgxPackages = forAllSystems (system:
    let
      bundleLgx = nix-bundle-lgx.bundlers.${system}.default;
      bundleLgxPortable = nix-bundle-lgx.bundlers.${system}.portable;
      installDev = nix-bundle-logos-module-install.bundlers.${system}.dev;
      installPortable = nix-bundle-logos-module-install.bundlers.${system}.portable;
      moduleLib = perSystem.${system}.moduleLib;
      # Use the portable-linked plugin for lgx-portable when available
      moduleLibForPortable =
        if perSystem.${system}.moduleLibPortable != null
        then perSystem.${system}.moduleLibPortable
        else moduleLib;
    in {
      lgx = bundleLgx moduleLib;
      install = installDev moduleLib;
      lgx-portable = bundleLgxPortable moduleLibForPortable;
      install-portable = installPortable moduleLibForPortable;
    }
  );

in {
  inherit config perSystem devShells lgxPackages;
}
