# Tests for modulePreConfigure.nix — the codegen selected per `interface`.
#
# The case that matters here is the RETIRED one. `autoCodegen` ends in a
# catch-all `else ""`, so an interface it does not recognise generates no glue
# at all: the module compiles green and is then un-callable from every
# consumer, with nothing in the log to say why. `interface: "provider"` was
# removed (its `logos-cpp-generator --provider-header` dispatch is gone), so it
# has to hit an explicit throw rather than that silent no-op.
{ lib, assertBool, assertThrows, modulePreConfigure }:

let
  auto = modulePreConfigure.autoCodegen;

  contains = needle: hay: lib.hasInfix needle hay;

  universal = auto {
    name = "some_module";
    interface = "universal";
    type = "core";
  };

  cdylib = auto {
    name = "rusty_module";
    interface = "cdylib";
    codegen.lidl = "src/rusty_module.lidl";
  };

  # An unknown-but-not-retired interface keeps the old permissive behaviour:
  # `legacy` (the default) and anything else still mean "no generated glue".
  legacy = auto {
    name = "old_module";
    interface = "legacy";
    type = "core";
  };

in [
  # The retired interface must THROW, not silently emit an empty snippet.
  (assertThrows "autoCodegen rejects the removed interface \"provider\""
    (auto { name = "legacy_provider_mod"; interface = "provider"; }))

  # Live interfaces still emit their generator invocations.
  (assertBool "universal still runs the header->lidl codegen"
    (contains "--header-to-lidl" universal) true)
  (assertBool "universal still emits the cdylib Qt glue"
    (contains "--backend cdylib" universal) true)
  (assertBool "cdylib still emits the uniform Qt glue"
    (contains "--backend cdylib" cdylib) true)

  # The glue MUST come from logos-plugin-qt's logos-qt-host-generator, not from
  # logos-qt-sdk's older copy of the same emitter. Both compile and both emit
  # loadable glue, so calling the wrong one is not a build error — it silently
  # emits STALE glue. That is exactly how the host-services grant went
  # undelivered for a whole phase while every build stayed green.
  (assertBool "universal glue uses the maintained generator"
    (contains "logos-qt-host-generator" universal) true)
  (assertBool "cdylib glue uses the maintained generator"
    (contains "logos-qt-host-generator" cdylib) true)
  # `logos-qt-generator ` with the trailing space so it cannot match
  # `logos-qt-host-generator`; the ui backend still legitimately uses qt-sdk's.
  (assertBool "universal glue does NOT fall back to qt-sdk's copy"
    (contains "logos-qt-generator " universal) false)
  (assertBool "cdylib glue does NOT fall back to qt-sdk's copy"
    (contains "logos-qt-generator " cdylib) false)

  # And nothing anywhere still reaches for the removed generator flag.
  (assertBool "universal codegen does not use --provider-header"
    (contains "--provider-header" universal) false)
  (assertBool "cdylib codegen does not use --provider-header"
    (contains "--provider-header" cdylib) false)

  # The catch-all is unchanged for interfaces that were never retired.
  (assertBool "legacy interface still generates no glue" (legacy == "") true)
]
