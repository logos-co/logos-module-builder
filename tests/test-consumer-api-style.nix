# The CONSUMER axis: `codegen.consumer_api_style`, and the gate on it.
#
# What is being pinned here is not "the key parses". It is the boundary the key
# is allowed to cross, which is a SAFETY boundary rather than a typing one:
#
#   A generated consumer wrapper that holds no LogosAPI (the lp wrappers, and
#   the Qt wrappers emitted under `--binding origin`) can only authenticate its
#   outbound calls if something else populates the TokenManager its lp client
#   reads. In a cdylib provider image that happens over the module-impl C ABI
#   (`logos_module_accept_token` -> `lp_token_save`). In a Qt PLUGIN image it
#   does not: the host writes tokens to the TokenManager in its OWN image, and
#   the only thing that mirrors them across is logos::qt::LpBridge::syncTokens,
#   installed exclusively by `forTarget(api, ...)`.
#
#   So the same "no LogosAPI" wrapper is correct in one image and silently
#   unauthenticated in the other — calls come back as default values with no
#   error raised. `packaged_as_cdylib` is the predicate that separates them, and
#   these cases are the record of where it falls.
#
# Every default below must equal what logos-plugin-qt buildPlugin.nix derived
# before this key existed, or every module in the tree rebuilds.
{ assertEq, assertBool, assertThrows, parseMetadata }:

let
  parse = parseMetadata.parseModuleConfig;

  mk = attrs: parse (builtins.toJSON ({ name = "m"; } // attrs));

  # The four shapes, with no key set.
  legacyCore   = mk { };                                             # handcrafted Qt plugin
  legacyUi     = mk { type = "ui"; };
  universalCore = mk { interface = "universal"; type = "core"; };    # header-first cdylib
  universalUi   = mk { interface = "universal"; type = "ui_qml"; };  # view backend, NOT a module
  cdylibCore    = mk { interface = "cdylib"; type = "core"; };

  # Overridden.
  cdylibQt      = mk { interface = "cdylib"; type = "core";
                       codegen = { consumer_api_style = "qt"; }; };
  universalQt   = mk { interface = "universal"; type = "core";
                       codegen = { consumer_api_style = "qt"; }; };
  cdylibLpExplicit = mk { interface = "cdylib"; type = "core";
                          codegen = { consumer_api_style = "lp"; }; };
  legacyQtExplicit = mk { codegen = { consumer_api_style = "qt"; }; };

in [
  # ── packaged_as_cdylib: the predicate itself ───────────────────────────────
  # Same expression modulePreConfigure.autoCodegen branches on when it decides
  # to emit the module-impl C ABI export surface. If these two ever disagree, a
  # module gets an origin-bound wrapper in an image with no accept_token.
  (assertBool "legacy core is NOT cdylib-packaged" legacyCore.packaged_as_cdylib false)
  (assertBool "legacy ui is NOT cdylib-packaged" legacyUi.packaged_as_cdylib false)
  (assertBool "universal core IS cdylib-packaged" universalCore.packaged_as_cdylib true)
  (assertBool "universal ui_qml is NOT cdylib-packaged" universalUi.packaged_as_cdylib false)
  (assertBool "cdylib IS cdylib-packaged" cdylibCore.packaged_as_cdylib true)

  # ── Defaults: byte-identity with the pre-key derivation ────────────────────
  (assertEq "legacy core defaults to qt" legacyCore.consumer_api_style "qt")
  (assertEq "legacy ui defaults to qt" legacyUi.consumer_api_style "qt")
  (assertEq "universal core defaults to lp" universalCore.consumer_api_style "lp")
  (assertEq "universal ui_qml defaults to qt" universalUi.consumer_api_style "qt")
  (assertEq "cdylib defaults to lp" cdylibCore.consumer_api_style "lp")

  # ── The one override the key exists for ────────────────────────────────────
  # A cdylib provider consuming its dependencies through Qt-typed wrappers.
  # Its image has no LogosAPI and takes tokens over the C ABI, so the
  # origin-bound wrapper is correct there.
  (assertEq "cdylib may ask for the Qt consumer surface" cdylibQt.consumer_api_style "qt")
  (assertEq "universal core may ask for the Qt consumer surface" universalQt.consumer_api_style "qt")

  # Restating a default is a no-op, not an error.
  (assertEq "cdylib may restate lp" cdylibLpExplicit.consumer_api_style "lp")
  (assertEq "legacy may restate qt" legacyQtExplicit.consumer_api_style "qt")

  # ── THE GATE ───────────────────────────────────────────────────────────────
  # A Qt plugin image must not get LogosAPI-free consumer wrappers. Refused at
  # EVAL, naming `codegen.consumer_api_style`, because the alternatives are a
  # compile error deep inside generated code (the umbrella shapes disagree) or —
  # worse, where they happen to agree — a module that builds green and then
  # cannot authenticate a single outbound call.
  (assertThrows "a legacy Qt plugin cannot ask for the lp consumer surface"
    (mk { codegen = { consumer_api_style = "lp"; }; }).consumer_api_style)
  (assertThrows "a legacy ui plugin cannot ask for the lp consumer surface"
    (mk { type = "ui"; codegen = { consumer_api_style = "lp"; }; }).consumer_api_style)
  # The one that is easy to get wrong: `interface: "universal"` looks
  # cdylib-shaped, but a ui_qml backend is a Qt view object holding a LogosAPI.
  (assertThrows "a universal ui_qml backend cannot ask for the lp consumer surface"
    (mk { interface = "universal"; type = "ui_qml";
          codegen = { consumer_api_style = "lp"; }; }).consumer_api_style)

  # ── Value validation ───────────────────────────────────────────────────────
  # An unrecognised value is refused rather than defaulted: defaulting a
  # misspelling back to the derived surface is how a module silently keeps the
  # binding its author was trying to change.
  (assertThrows "an unknown consumer_api_style is refused"
    (mk { interface = "cdylib"; codegen = { consumer_api_style = "Qt"; }; }).consumer_api_style)
  (assertThrows "the --binding value is not a consumer_api_style value"
    (mk { interface = "cdylib"; codegen = { consumer_api_style = "origin"; }; }).consumer_api_style)
  (assertThrows "a non-string consumer_api_style is refused"
    (mk { interface = "cdylib"; codegen = { consumer_api_style = true; }; }).consumer_api_style)
]
