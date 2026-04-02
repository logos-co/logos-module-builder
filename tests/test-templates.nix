# Tests for template validity
# Ensures all template metadata.json files parse correctly and have expected fields
{ assertEq, assertBool, assertHasAttr, parseMetadata, builderRoot }:

let
  parse = parseMetadata.parseModuleConfig;

  # Read and parse each template's metadata.json
  minimalMeta = parse (builtins.readFile (builderRoot + "/templates/minimal-module/metadata.json"));
  extLibMeta = parse (builtins.readFile (builderRoot + "/templates/external-lib-module/metadata.json"));
  uiMeta = parse (builtins.readFile (builderRoot + "/templates/ui-qml-backend/metadata.json"));
  uiQmlMeta = parse (builtins.readFile (builderRoot + "/templates/ui-qml/metadata.json"));

in [
  # ---------------------------------------------------------------------------
  # All templates parse without error (implicitly tested by the lets above)
  # ---------------------------------------------------------------------------

  # --- Minimal module template ---
  (assertEq "template minimal: name" minimalMeta.name "minimal")
  (assertEq "template minimal: type" minimalMeta.type "core")
  (assertEq "template minimal: version" minimalMeta.version "1.0.0")
  (assertEq "template minimal: dependencies empty" minimalMeta.dependencies [])
  (assertEq "template minimal: category" minimalMeta.category "example")

  # --- External lib module template ---
  (assertEq "template extlib: name" extLibMeta.name "external_lib")
  (assertEq "template extlib: type" extLibMeta.type "core")
  (assertBool "template extlib: has external libraries"
    (builtins.length extLibMeta.external_libraries > 0) true)
  (assertEq "template extlib: first extlib name"
    (builtins.head extLibMeta.external_libraries).name "example_lib")
  (assertEq "template extlib: cmake extra_include_dirs"
    extLibMeta.cmake.extra_include_dirs [ "lib" ])

  # --- UI module template ---
  (assertEq "template ui: name" uiMeta.name "ui_example")
  (assertEq "template ui: type" uiMeta.type "ui_qml")
  (assertEq "template ui: main" uiMeta.main "ui_example_plugin")
  (assertEq "template ui: icon" uiMeta.icon null)

  # --- UI QML module template ---
  (assertEq "template qml: name" uiQmlMeta.name "ui_qml_example")
  (assertEq "template qml: type" uiQmlMeta.type "ui_qml")
  (assertEq "template qml: view" uiQmlMeta.view "Main.qml")

  # ---------------------------------------------------------------------------
  # Template files exist
  # ---------------------------------------------------------------------------
  (assertBool "minimal template has flake.nix"
    (builtins.pathExists (builderRoot + "/templates/minimal-module/flake.nix")) true)
  (assertBool "minimal template has src dir"
    (builtins.pathExists (builderRoot + "/templates/minimal-module/src")) true)
  (assertBool "extlib template has flake.nix"
    (builtins.pathExists (builderRoot + "/templates/external-lib-module/flake.nix")) true)
  (assertBool "ui template has flake.nix"
    (builtins.pathExists (builderRoot + "/templates/ui-qml-backend/flake.nix")) true)
  (assertBool "ui template has src dir"
    (builtins.pathExists (builderRoot + "/templates/ui-qml-backend/src")) true)
  (assertBool "qml template has flake.nix"
    (builtins.pathExists (builderRoot + "/templates/ui-qml/flake.nix")) true)
  (assertBool "qml template has Main.qml"
    (builtins.pathExists (builderRoot + "/templates/ui-qml/Main.qml")) true)

  # ---------------------------------------------------------------------------
  # All templates have required metadata fields
  # ---------------------------------------------------------------------------
  (assertBool "all templates have name" (
    minimalMeta.name != "" && extLibMeta.name != "" &&
    uiMeta.name != "" && uiQmlMeta.name != ""
  ) true)

  (assertBool "all templates have version" (
    minimalMeta.version != "" && extLibMeta.version != "" &&
    uiMeta.version != "" && uiQmlMeta.version != ""
  ) true)

  (assertBool "all templates have type" (
    minimalMeta.type != "" && extLibMeta.type != "" &&
    uiMeta.type != "" && uiQmlMeta.type != ""
  ) true)

  # ---------------------------------------------------------------------------
  # Type field consistency
  # ---------------------------------------------------------------------------
  (assertBool "core templates are core"
    (minimalMeta.type == "core" && extLibMeta.type == "core") true)
  (assertBool "ui template is ui_qml" (uiMeta.type == "ui_qml") true)
  (assertBool "qml template is ui_qml" (uiQmlMeta.type == "ui_qml") true)

  # ---------------------------------------------------------------------------
  # ui_qml strict contract: view required, main optional
  # ---------------------------------------------------------------------------
  # ui template (with backend): has both main and view
  (assertBool "ui template has view" (uiMeta.view != null) true)
  (assertEq "ui template view" uiMeta.view "qml/Main.qml")
  (assertBool "ui template has main" (uiMeta.main != null) true)

  # qml template (QML-only): has view, no main
  (assertBool "qml template has view" (uiQmlMeta.view != null) true)
  (assertEq "qml template no main" uiQmlMeta.main null)
]
