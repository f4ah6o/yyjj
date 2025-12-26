# WIP - YAML Parser Fixes

## Date
2025-12-26

## Current Status
**All 41 tests passing**

The YAML parser now correctly handles:
- Multi-key mappings at the same level ✓
- YAML 1.1 boolean keywords (`on`, `off`, `yes`, `no`) as mapping keys ✓
- Empty values (implicit null) followed by sibling keys ✓
- Nested mappings with sequences ✓
- Deeply nested structures ✓
- **Sequences followed by sibling keys at the same level ✓** (Fixed!)
- GitHub Actions workflow YAML structure ✓

## Issues Fixed

### Main Issue: Sibling keys after sequences not being parsed
The parser now correctly parses complex YAML structures like:

```yaml
on:
  workflow_dispatch:
  push:
    paths:
      - file.yml
  pull_request:    # Now correctly found as sibling of push
    paths:
      - file.yml
jobs:              # Now correctly found as top-level key
  ...
```

## Fixes Applied

### 1. Lexer: Fix space consumption during multi-level dedent
Fixed `handle_indent()` in `lexer.mbt` to NOT consume spaces until the final dedent token is emitted. Previously, spaces were consumed on the first `handle_indent()` call, causing subsequent calls to see 0 spaces and emit incorrect extra Dedent(0) tokens.

**Key change**: Only consume spaces when `to_level <= spaces` (final dedent).

### 2. Parser: Change dedent exit condition
Changed the exit condition in `parse_indented_mapping` from `n <= base_indent` to `n < base_indent`.

- `n == base_indent`: Same level, sibling keys may exist - continue parsing
- `n < base_indent`: Dedented PAST our level - exit and let parent handle

### 3. Parser: Handle Dedent(0) specially in parse_mapping_with_first_key
When `Dedent(0)` is seen at the top-level mapping, consume it and any remaining dedents, then check for more top-level keys (like `jobs:` after `on:`).

### 4. New tests added
- `yaml_parse_github_actions_on_section`: Tests parsing the `on:` section with workflow_dispatch, push, and pull_request siblings
- `yaml_parse_copilot_setup_steps`: Tests parsing full GitHub Actions workflow structure

## Test Results
- **Total tests**: 41
- **Passing**: 41
- **Failing**: 0

## Validation
Tested against `.github/workflows/copilot-setup-steps.yaml` structure - parser now correctly finds all three `on:` sibling keys and the `jobs:` top-level key.
