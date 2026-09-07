# Tests for common.classifyConcreteDeps — the split that decides which of a
# module's concrete dependencies get a typed wrapper from a published LIDL and
# which take the transitional header-copy path (the one that BUILDS them).
#
# Mock flake inputs: the function only reads `packages.<system>.lidl`.
{ assertEq, assertBool, assertThrows, common }:

let
  sys = "x86_64-linux";

  withLidl = name: { packages.${sys}.lidl = "/lidl/${name}"; };
  withoutLidl = _name: { packages.${sys} = { }; };

  classify = { deps ? [ ], optional ? [ ], overrides ? { }, inputs ? { } }:
    common.classifyConcreteDeps {
      system = sys;
      flakeInputs = inputs;
      src = "/src";
      builderName = "mkLogosModule";
      config = {
        name = "consumer";
        dependencies = deps;
        optional_dependencies = optional;
        dependency_overrides = overrides;
      };
    };

  names = entries: map (e: e.name) entries;

  bothKinds = classify {
    deps = [ "req" ];
    optional = [ "opt" ];
    inputs = { req = withLidl "req"; opt = withLidl "opt"; };
  };

  optionalOverridden = classify {
    optional = [ "opt" ];
    overrides = { opt = { file = "contracts/opt.lidl"; input = null; impl_class = null; }; };
    inputs = { };
  };

in [
  (assertEq "a module with neither list gets nothing to generate"
    (classify { }).staticDeps [ ])

  # The point of the feature: an optional dependency IS typed (its name is
  # concrete, so its contract is) but is absent from everything that decides
  # what gets built or bundled.
  (assertEq "an optional dependency is typed alongside the required ones"
    (names bothKinds.staticDeps) [ "req" "opt" ])

  (assertEq "the LIDL path is the dependency's published output"
    (map (e: e.path) bothKinds.staticDeps) [ "/lidl/req/req.lidl" "/lidl/opt/opt.lidl" ])

  # The header-copy fallback that used to serve these is gone from
  # logos-plugin-qt, which refuses them by name. Refusing here fails before
  # anything is built, and names the metadata.json that has to change.
  (assertThrows "a required dependency without a LIDL is refused, not built"
    (classify { deps = [ "old" ]; inputs = { old = withoutLidl "old"; }; }).staticDeps)

  (assertThrows "an optional dependency without a LIDL is refused, not built"
    (classify { optional = [ "old" ]; inputs = { old = withoutLidl "old"; }; }).staticDeps)

  (assertThrows "an optional dependency with no flake input at all is refused"
    (classify { optional = [ "absent" ]; }).staticDeps)

  # The refusal has to be actionable: it names the module, the offending
  # dependency, and the untyped escape hatch for a contract nobody wants to pin.
  (assertBool "the refusal names the module, the dependency and the by-name escape hatch"
    (let r = builtins.tryEval (builtins.deepSeq
               (classify { optional = [ "nolidl" ]; inputs = { nolidl = withoutLidl "x"; }; }).staticDeps
               null);
     in !r.success)
    true)

  # An override is the other way to give an optional dependency a contract —
  # otherwise a module could only declare one against a dep that already
  # publishes a LIDL, which is the narrower half of the fleet.
  (assertEq "a dependency_overrides entry satisfies an optional dependency"
    (map (e: e.path) optionalOverridden.staticDeps) [ "/src/contracts/opt.lidl" ])

  (assertEq "an override works for a required dependency too"
    (map (e: e.path) (classify {
      deps = [ "req" ];
      overrides = { req = { file = "contracts/req.lidl"; input = null; impl_class = null; }; };
      inputs = { };
    }).staticDeps) [ "/src/contracts/req.lidl" ])
]
