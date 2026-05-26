# Tests for template validity
# Ensures all template metadata.json files parse correctly and have expected fields
# UI/QML templates have been moved to logos-app-builder.
{ assertEq, assertBool, assertHasAttr, parseMetadata, builderRoot }:

let
  parse = parseMetadata.parseModuleConfig;

  # Read and parse each template's metadata.json
  minimalMeta = parse (builtins.readFile (builderRoot + "/templates/minimal-module/metadata.json"));
  extLibMeta = parse (builtins.readFile (builderRoot + "/templates/external-lib-module/metadata.json"));

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

  # ---------------------------------------------------------------------------
  # Template files exist
  # ---------------------------------------------------------------------------
  (assertBool "minimal template has flake.nix"
    (builtins.pathExists (builderRoot + "/templates/minimal-module/flake.nix")) true)
  (assertBool "minimal template has src dir"
    (builtins.pathExists (builderRoot + "/templates/minimal-module/src")) true)
  (assertBool "extlib template has flake.nix"
    (builtins.pathExists (builderRoot + "/templates/external-lib-module/flake.nix")) true)

  # ---------------------------------------------------------------------------
  # All templates have required metadata fields
  # ---------------------------------------------------------------------------
  (assertBool "all templates have name"
    (minimalMeta.name != "" && extLibMeta.name != "") true)

  (assertBool "all templates have version"
    (minimalMeta.version != "" && extLibMeta.version != "") true)

  (assertBool "all templates have type"
    (minimalMeta.type != "" && extLibMeta.type != "") true)

  # ---------------------------------------------------------------------------
  # Type field consistency
  # ---------------------------------------------------------------------------
  (assertBool "core templates are core"
    (minimalMeta.type == "core" && extLibMeta.type == "core") true)
]
