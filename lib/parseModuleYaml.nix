# Simple YAML parser for module.yaml files
# Handles the subset of YAML needed for module configuration:
# - Key-value pairs
# - Simple lists
# - Nested objects (one level)
# - Comments (lines starting with #)
# - String values (with or without quotes)
{ lib }:

let
  # Helper to trim whitespace from a string
  trim = s: 
    let
      trimLeft = str: 
        if str == "" then ""
        else if lib.hasPrefix " " str || lib.hasPrefix "\t" str
        then trimLeft (builtins.substring 1 (-1) str)
        else str;
      trimRight = str:
        if str == "" then ""
        else 
          let len = builtins.stringLength str;
              last = builtins.substring (len - 1) 1 str;
          in if last == " " || last == "\t" || last == "\n" || last == "\r"
             then trimRight (builtins.substring 0 (len - 1) str)
             else str;
    in trimRight (trimLeft s);
  
  # Check if a line is a comment or empty
  isCommentOrEmpty = line:
    let trimmed = trim line;
    in trimmed == "" || lib.hasPrefix "#" trimmed;
  
  # Get indentation level (number of leading spaces)
  getIndent = line:
    let
      countSpaces = str: n:
        if str == "" then n
        else if lib.hasPrefix " " str then countSpaces (builtins.substring 1 (-1) str) (n + 1)
        else n;
    in countSpaces line 0;
  
  # Check if a line is a list item (starts with "- ")
  isListItem = line:
    let trimmed = trim line;
    in lib.hasPrefix "- " trimmed || trimmed == "-";
  
  # Extract list item value
  getListItemValue = line:
    let trimmed = trim line;
    in if lib.hasPrefix "- " trimmed
       then trim (builtins.substring 2 (-1) trimmed)
       else "";
  
  # Find position of first colon (simple implementation)
  findColon = str:
    let
      len = builtins.stringLength str;
      find = pos:
        if pos >= len then (-1)
        else if builtins.substring pos 1 str == ":" then pos
        else find (pos + 1);
    in find 0;

  # Parse the YAML content - all parsing functions defined locally to avoid closure issues
  parseYaml = content:
    let
      # Parse a simple value (string, possibly quoted)
      # Defined here to ensure proper scoping within parseYaml
      doParseValue = str:
        let
          trimmed = trim str;
          len = builtins.stringLength trimmed;
        in
          if trimmed == "" then null
          else if trimmed == "[]" then []
          else if trimmed == "{}" then {}
          else if trimmed == "true" then true
          else if trimmed == "false" then false
          else if trimmed == "null" || trimmed == "~" then null
          else if lib.hasPrefix "\"" trimmed && lib.hasSuffix "\"" trimmed
               then builtins.substring 1 (len - 2) trimmed
          else if lib.hasPrefix "'" trimmed && lib.hasSuffix "'" trimmed
               then builtins.substring 1 (len - 2) trimmed
          else if builtins.match "[0-9]+" trimmed != null
               then lib.toInt trimmed
          else trimmed;

      # Wrapper that forces strict evaluation and validates result
      parseValue = str:
        let
          result = doParseValue str;
        in
          # Force evaluation with builtins.seq and check it's not a function
          builtins.seq result (
            if builtins.isFunction result
            then builtins.throw "parseValue unexpectedly returned a function for input: ${str}"
            else result
          );

      # Split into lines
      lines = lib.splitString "\n" content;
      
      # Filter out comments and empty lines, keeping track of indices
      indexedLines = lib.imap0 (i: line: { inherit i line; }) lines;
      nonEmptyLines = lib.filter (x: !isCommentOrEmpty x.line) indexedLines;
      
      # Parse lines recursively
      parseLines = linesToParse: currentIndent: result:
        if linesToParse == [] then { inherit result; remaining = []; }
        else
          let
            first = lib.head linesToParse;
            rest = lib.tail linesToParse;
            line = first.line;
            indent = getIndent line;
            trimmed = trim line;
          in
            if indent < currentIndent then 
              # Dedent - return to parent
              { inherit result; remaining = linesToParse; }
            else if indent > currentIndent && result == {} then
              # First line should set the indent
              parseLines linesToParse indent result
            else if indent > currentIndent then
              # Unexpected indent increase - skip
              parseLines rest currentIndent result
            else if isListItem line then
              # This is a list item - handle specially
              let
                itemValue = getListItemValue line;
                colonIdx = findColon itemValue;
              in
                if colonIdx > 0 then
                  # List item with nested object like "- name: foo"
                  let
                    key = trim (builtins.substring 0 colonIdx itemValue);
                    valueStr = trim (builtins.substring (colonIdx + 1) (-1) itemValue);
                    # Parse the value with strict evaluation
                    parsedValue = parseValue valueStr;
                    # Check if there are more nested lines
                    nextLines = lib.filter (x: getIndent x.line > indent) rest;
                    nestedResult = if nextLines != [] && (lib.head nextLines).line != ""
                                   then parseLines rest (indent + 2) {}
                                   else { result = {}; remaining = rest; };
                    itemObj = { ${key} = parsedValue; } // nestedResult.result;
                  in
                    parseLines nestedResult.remaining currentIndent 
                      (if lib.isList result then result ++ [itemObj] else [itemObj])
                else
                  # Simple list item - parse value with strict evaluation
                  let
                    parsedItem = parseValue itemValue;
                  in
                    parseLines rest currentIndent 
                      (if lib.isList result then result ++ [parsedItem] else [parsedItem])
            else
              # Key-value line
              let
                colonIdx = findColon trimmed;
              in
                if colonIdx < 0 then
                  parseLines rest currentIndent result
                else
                  let
                    key = trim (builtins.substring 0 colonIdx trimmed);
                    valueStr = trim (builtins.substring (colonIdx + 1) (-1) trimmed);
                  in
                    if valueStr == "" then
                      # Key with nested content (object or list)
                      let
                        nested = parseLines rest (indent + 2) {};
                      in
                        parseLines nested.remaining currentIndent (result // { ${key} = nested.result; })
                    else
                      # Simple key-value - parse value with strict evaluation
                      let
                        parsedValue = parseValue valueStr;
                      in
                        parseLines rest currentIndent (result // { ${key} = parsedValue; });
      
      parsed = parseLines nonEmptyLines 0 {};
    in
      parsed.result;

in
{
  # Parse a YAML string
  fromYAML = parseYaml;
  
  # Parse a module.yaml file and return the config with defaults applied
  parseModuleConfig = yamlContent:
    let
      raw = parseYaml yamlContent;
      
      # Helper to safely extract a list, with strict evaluation
      safeList = val:
        let evaluated = builtins.seq val val;
        in if builtins.isList evaluated then evaluated else [];
    in {
      # Required fields
      name = raw.name or (throw "module.yaml must specify 'name'");
      
      # Optional fields with defaults
      version = raw.version or "1.0.0";
      type = raw.type or "core";
      category = raw.category or "general";
      description = raw.description or "A Logos module";
      
      # Dependencies
      dependencies = safeList (raw.dependencies or []);
      
      # Nix packages
      nix_packages = {
        build = safeList ((raw.nix_packages or {}).build or []);
        runtime = safeList ((raw.nix_packages or {}).runtime or []);
      };
      
      # External libraries
      external_libraries = safeList (raw.external_libraries or []);
      
      # CMake configuration
      cmake = {
        find_packages = safeList ((raw.cmake or {}).find_packages or []);
        extra_sources = safeList ((raw.cmake or {}).extra_sources or []);
        extra_include_dirs = safeList ((raw.cmake or {}).extra_include_dirs or []);
        extra_link_libraries = safeList ((raw.cmake or {}).extra_link_libraries or []);
      };
      
      # Include files to bundle with the module
      include = safeList (raw.include or []);
      
      # Source files (auto-detected if not specified)
      sources = raw.sources or null;
      
      # Keep the raw config for custom extensions
      _raw = raw;
    };
    
  # Helper to read and parse a module.yaml file
  # Note: This should be called with builtins.readFile at the call site
  # since we can't access the filesystem directly here
  parseFile = path: parseYaml (builtins.readFile path);
}
