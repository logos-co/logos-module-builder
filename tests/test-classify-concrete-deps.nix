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
  (assertEq "a module with neither list gets two empty halves"
    (let c = classify { }; in { s = c.staticDeps; l = c.legacyHeaderDepNames; })
    { s = [ ]; l = [ ]; })

  # The point of the feature: an optional dependency IS typed (its name is
  # concrete, so its contract is) but is absent from everything that decides
  # what gets built or bundled.
  (assertEq "an optional dependency is typed alongside the required ones"
    (names bothKinds.staticDeps) [ "req" "opt" ])

  (assertEq "an optional dependency never enters the header-copy (build) half"
    bothKinds.legacyHeaderDepNames [ ])

  (assertEq "the LIDL path is the dependency's published output"
    (map (e: e.path) bothKinds.staticDeps) [ "/lidl/req/req.lidl" "/lidl/opt/opt.lidl" ])

  # A required dependency with no LIDL falls back to being built. That fallback
  # is the one thing an optional dependency must not reach, so it refuses.
  (assertEq "a required dependency without a LIDL takes the header-copy path"
    (let c = classify { deps = [ "old" ]; inputs = { old = withoutLidl "old"; }; };
     in { s = names c.staticDeps; l = c.legacyHeaderDepNames; })
    { s = [ ]; l = [ "old" ]; })

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

  (assertEq "an overridden optional dependency still skips the header-copy half"
    optionalOverridden.legacyHeaderDepNames [ ])
]
