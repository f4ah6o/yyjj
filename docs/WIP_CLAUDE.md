# WIP - YAML Parser Fixes

## Date
2025-12-26

## Context
The YAML parser was not correctly parsing multi-key mappings and nested structures. When parsing a GitHub Actions YAML file, only the first key (`name`) was being parsed, resulting in output like `{ "name": "Copilot Setup Steps" }` instead of the full structure.

## Root Causes Identified

### 1. Lexer: `at_line_start` flag not reset
- `handle_indent()` in `lexer.mbt` was not resetting `at_line_start = false` after processing indentation
- This caused `Indent(2)` to be immediately followed by `Dedent(0)` in the token stream

### 2. Parser: `skip_trivia()` consuming newlines
- `parse_scalar_or_mapping()` was using `skip_trivia()` which consumed newlines
- This caused the parser to lose track of sibling keys at the same indentation level

### 3. YAML 1.1 keywords as mapping keys
- `on`, `off`, `yes`, `no` are boolean keywords in YAML 1.1
- These were tokenized as `TrueValue`/`FalseValue` and not recognized as potential mapping keys
- GitHub Actions uses `on:` as a top-level key, which was being parsed incorrectly

### 4. Empty values (implicit null)
- When a key has no value before the next sibling key (e.g., `workflow_dispatch:` followed by `push:`)
- Parser couldn't distinguish between empty value + sibling key vs nested mapping

## Fixes Applied

### lexer.mbt
```moonbit
fn Lexer::handle_indent(self : Lexer) -> Token? {
  // ...
  for i = 0; i < spaces; i = i + 1 {
    let _ = self.advance()
  }
  // Mark that we're no longer at line start after processing indentation
  self.at_line_start = false  // <-- ADDED
  // ...
}
```

### parser.mbt
1. Changed `parse_scalar_or_mapping()` to only skip whitespace, not newlines
2. Added handling for TrueValue/FalseValue/NullValue as potential mapping keys
3. Added `is_sibling_key_ahead()` helper to detect empty values
4. Modified `parse_mapping_with_first_key()` to use look-ahead for implicit null detection

### parser_test.mbt
Added three new tests:
- `yaml_parse_multi_key_mapping` - tests multiple keys at same level
- `yaml_parse_nested_mapping` - tests nested structure
- `yaml_parse_sibling_keys_with_empty_values` - tests implicit null values

## Current Status
- All 39 tests pass
- Multi-key mappings at same level now parse correctly
- YAML 1.1 boolean keywords can be used as mapping keys
- Empty values (implicit null) followed by sibling keys work correctly

## Known Issues
Complex deeply nested structures still have some nesting issues. For example, in the GitHub Actions file, `push`, `pull_request`, and `jobs` may not be correctly nested at their proper levels.

## Next Steps
1. Further investigation into indentation level tracking for complex nested structures
2. Consider explicit indentation tracking in the parser state
