# yyjj Implementation Plan

MoonBit JSONC-YAML bidirectional converter with comment preservation.

## Scope Decisions

- **YAML scope**: GitHub Actions workflow level (mappings, sequences, multi-line strings, anchors/aliases, comments)
- **JSONC trailing commas**: Allow on input (lenient parsing), don't emit on output
- **CLI**: Defer to final phase, focus on library first

## Package Structure

```
yyjj/
├── common/           # Shared types (Trivia, Span, Error)
├── jsonc/            # JSONC lexer, parser, printer
├── yaml/             # YAML lexer, parser, printer
├── transform/        # Bidirectional transformation
├── pretty/           # Wadler-Lindig pretty printer
├── cmd/main/         # CLI entry point
└── yyjj.mbt          # Public API facade
```

## Implementation Phases

### Phase 1: Foundation - Common Types & JSONC Parser

1. **Create package structure**
   - Create directories: `common/`, `jsonc/`, `yaml/`, `transform/`, `pretty/`
   - Configure `moon.pkg.json` for each package

2. **Implement common types** (`common/`)
   - `span.mbt`: `Pos`, `Span` for position tracking
   - `trivia.mbt`: `CommentKind`, `Comment`, `Trivia`
   - `error.mbt`: `ParseError`, `ParseErrorKind`

3. **Implement JSONC Lexer** (`jsonc/lexer.mbt`)
   - Tokenize: `{`, `}`, `[`, `]`, `:`, `,`, strings, numbers, `true`, `false`, `null`
   - Preserve: `//` line comments, `/* */` block comments, whitespace
   - Handle escape sequences in strings

4. **Implement JSONC Parser** (`jsonc/parser.mbt`)
   - Build CST with trivia attachment (Leading/Trailing heuristic)
   - CST nodes: `JNull`, `JBool`, `JNumber`, `JString`, `JArray`, `JObject`
   - Accept trailing commas in arrays and objects (lenient parsing)

### Phase 2: YAML Support (GitHub Actions scope)

5. **Implement YAML Lexer** (`yaml/lexer.mbt`)
   - Track indentation with `Indent`/`Dedent` tokens
   - Handle: `-` sequences, `:` mappings, `#` comments
   - Support: `&anchor`, `*alias`, `|` literal, `>` folded blocks
   - **Not in scope**: tags (`!tag`), complex keys, multi-document (`---`)

6. **Implement YAML Parser** (`yaml/parser.mbt`)
   - Build CST with indent-based structure
   - CST nodes: `YNull`, `YBool`, `YNumber`, `YString`, `YSequence`, `YMapping`, `YAlias`, `YAnchor`
   - Focus on patterns common in GitHub Actions workflows

### Phase 3: Transformation Engine

7. **JSONC to YAML** (`transform/jsonc_to_yaml.mbt`)
   - Convert `JsonNode` → `YamlNode`
   - Block comments → multiple line comments
   - Determine scalar styles (quoted vs plain)

8. **YAML to JSONC** (`transform/yaml_to_jsonc.mbt`)
   - Convert `YamlNode` → `JsonNode`
   - Expand anchors/aliases
   - Indentation → braces/brackets

### Phase 4: Pretty Printer

9. **Implement Doc type** (`pretty/doc.mbt`)
   - `Nil`, `Text`, `Line`, `HardLine`, `Concat`, `Nest`, `Group`, `FlatAlt`

10. **Implement Renderer** (`pretty/render.mbt`)
    - Wadler-Lindig width-aware layout algorithm

11. **Format printers** (`jsonc/printer.mbt`, `yaml/printer.mbt`)
    - CST → Doc → String

### Phase 5: Public API & CLI

12. **Public API** (`yyjj.mbt`)
    - `jsonc_to_yaml(input: String) -> Result[String, ParseError]`
    - `yaml_to_jsonc(input: String) -> Result[String, ParseError]`
    - `parse_jsonc`, `parse_yaml` for advanced use

13. **CLI** (`cmd/main/main.mbt`)
    - Auto-detect format, file I/O

## Key Data Structures

```moonbit
// common/trivia.mbt
enum CommentKind { LineComment; BlockComment }
struct Comment { content: String; kind: CommentKind; preceding_newline: Bool }
struct Trivia { leading: Array[Comment]; trailing: Array[Comment] }

// jsonc/cst.mbt
enum JsonNode {
  JNull(Trivia)
  JBool(Bool, Trivia)
  JNumber(String, Trivia)  // String to preserve precision
  JString(String, Trivia)
  JArray(Array[JsonNode], Trivia)
  JObject(Array[JProperty], Trivia)
}
struct JProperty { key: String; key_trivia: Trivia; value: JsonNode }

// yaml/cst.mbt
enum YamlScalarStyle { Plain; SingleQuoted; DoubleQuoted; Literal; Folded }
enum YamlNode {
  YNull(Trivia)
  YBool(Bool, Trivia)
  YNumber(String, Trivia)
  YString(String, YamlScalarStyle, Trivia)
  YSequence(Array[YamlNode], Trivia)
  YMapping(Array[YKeyValue], Trivia)
  YAlias(String, Trivia)
  YAnchor(String, YamlNode)
}
```

## Trivia Attachment Algorithm

```
1. Pending Buffer: Parser keeps unattached comments in a buffer
2. Node Start: Flush buffer → Leading Trivia
3. Node End: Consume same-line comments → Trailing Trivia
4. Newline: Comments after newline → next node's Leading
```

## Critical Files

| File | Purpose |
|------|---------|
| `common/trivia.mbt` | Core trivia types enabling comment preservation |
| `jsonc/parser.mbt` | Trivia attachment algorithm implementation |
| `yaml/lexer.mbt` | Indent tracking (most complex lexer component) |
| `pretty/doc.mbt` | Wadler-Lindig Doc type |
| `transform/jsonc_to_yaml.mbt` | Comment style transformation |

## Testing Strategy

1. **Unit tests**: Per-component verification
2. **Snapshot tests**: Using MoonBit's `inspect`
3. **Round-trip tests**: `JSONC → YAML → JSONC` equivalence
4. **Error tests**: Helpful error messages for invalid input

## Package Dependencies

```
common ← (no deps)
pretty ← (no deps)
jsonc ← common, pretty
yaml ← common, pretty
transform ← common, jsonc, yaml
root ← common, jsonc, yaml, transform
cmd/main ← root
```
