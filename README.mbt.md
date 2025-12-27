# yyjj

> JSONC ⇔ YAML converter library with comment preservation

> Don't turn YAML into .yml, or I'll turn JSON into .jsn!

[![npm version](https://img.shields.io/npm/v/yyjj.svg)](https://www.npmjs.com/package/yyjj)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**yyjj** is a high-performance JSONC ⇔ YAML converter that preserves comments during transformation. Built with [MoonBit](https://www.moonbitlang.com/) and compiled to JavaScript, it provides a reliable way to convert between JSONC and YAML formats while maintaining code documentation.

## Features

- 🔄 **Bidirectional Conversion**: Convert between JSONC and YAML seamlessly
- 💬 **Comment Preservation**: Maintains comments during conversion
- 🚀 **High Performance**: Written in MoonBit and compiled to efficient JavaScript
- 📦 **Tree-shakable**: ES modules with CommonJS support
- 🔧 **TypeScript Support**: Includes type definitions
- 🎯 **CST Parsing**: Access to Concrete Syntax Tree for advanced use cases
- ⚡ **Zero Dependencies**: Lightweight with no runtime dependencies

## Installation

```bash
npm install yyjj
```

```bash
pnpm add yyjj
```

```bash
yarn add yyjj
```

## Quick Start

### Converting JSONC to YAML

```javascript
import { jsonc_to_yaml } from 'yyjj';

const jsonc = `{
  // This is a comment
  "name": "example",
  "version": "1.0.0" // inline comment
}`;

const result = jsonc_to_yaml(jsonc);

if (result.$tag === 1) {  // Ok
  console.log(result._0);
  // Output:
  // # This is a comment
  // name: example
  // version: 1.0.0  # inline comment
} else {  // Err
  console.error('Parse error:', result._0);
}
```

### Converting YAML to JSONC

```javascript
import { yaml_to_jsonc } from 'yyjj';

const yaml = `# Configuration
name: example
version: 1.0.0  # semantic version`;

const result = yaml_to_jsonc(yaml);

if (result.$tag === 1) {  // Ok
  console.log(result._0);
  // Output:
  // {
  //   // Configuration
  //   "name": "example",
  //   "version": "1.0.0" // semantic version
  // }
}
```

## API Reference

### Main Conversion Functions

#### `jsonc_to_yaml(input: string, width?: number): Result<string, ParseError>`

Converts a JSONC string to YAML format while preserving comments.

**Parameters:**
- `input` (string): The JSONC string to convert
- `width` (number, optional): Maximum line width for formatting (default: 80)

**Returns:** MoonBit Result type
- Success: `{ $tag: 1, _0: string }` - The converted YAML string
- Error: `{ $tag: 0, _0: ParseError }` - Parse error details

#### `yaml_to_jsonc(input: string, width?: number): Result<string, ParseError>`

Converts a YAML string to JSONC format while preserving comments.

**Parameters:**
- `input` (string): The YAML string to convert
- `width` (number, optional): Maximum line width for formatting (default: 80)

**Returns:** MoonBit Result type
- Success: `{ $tag: 1, _0: string }` - The converted JSONC string
- Error: `{ $tag: 0, _0: ParseError }` - Parse error details

### Low-Level API

For advanced use cases, yyjj provides access to parsing, transformation, and printing functions:

#### Parsing Functions

```javascript
import { parse_jsonc, parse_yaml } from 'yyjj';

// Parse JSONC to CST
const jsoncResult = parse_jsonc('{"key": "value"}');

// Parse YAML to CST
const yamlResult = parse_yaml('key: value');
```

#### Transformation Functions

```javascript
import { transform_jsonc_to_yaml, transform_yaml_to_jsonc } from 'yyjj';

// Transform JSONC CST to YAML CST
const yamlNode = transform_jsonc_to_yaml(jsoncNode);

// Transform YAML CST to JSONC CST
const jsoncNode = transform_yaml_to_jsonc(yamlNode);
```

#### Printing Functions

```javascript
import { print_jsonc, print_yaml } from 'yyjj';

// Print JSONC CST to string
const jsoncString = print_jsonc(jsoncNode, 100);

// Print YAML CST to string
const yamlString = print_yaml(yamlNode, 100);
```

## TypeScript Support

For better TypeScript integration, you can create a wrapper with normalized Result types:

```typescript
import { jsonc_to_yaml, yaml_to_jsonc } from 'yyjj';

export interface ParseError {
  kind: unknown;
  span: {
    start: { line: number; column: number; offset: number };
    end: { line: number; column: number; offset: number };
  };
  message: string;
}

export type ConversionResult =
  | { tag: "Ok"; val: string }
  | { tag: "Err"; val: ParseError };

function normalizeResult(result: unknown): ConversionResult {
  const r = result as { $tag: number; _0: unknown };
  if (r.$tag === 1) {
    return { tag: "Ok", val: r._0 as string };
  }
  return { tag: "Err", val: r._0 as ParseError };
}

export function jsoncToYaml(input: string, width?: number): ConversionResult {
  return normalizeResult(jsonc_to_yaml(input, width));
}

export function yamlToJsonc(input: string, width?: number): ConversionResult {
  return normalizeResult(yaml_to_jsonc(input, width));
}
```

## Error Handling

Parse errors include detailed information about the error location:

```javascript
import { jsonc_to_yaml } from 'yyjj';

const result = jsonc_to_yaml('{ invalid json }');

if (result.$tag === 0) {  // Error
  const error = result._0;
  console.error('Parse failed at line', error.span.start.line);
  console.error('Message:', error.message);
}
```

## Advanced Usage

### Custom Line Width

Control the formatting width for output:

```javascript
import { jsonc_to_yaml } from 'yyjj';

const jsonc = '{"key": "very long value that might wrap"}';

// Use 120 characters per line
const result = jsonc_to_yaml(jsonc, 120);
```

### Working with CST

Access the Concrete Syntax Tree for custom transformations:

```javascript
import { parse_jsonc, transform_jsonc_to_yaml, print_yaml } from 'yyjj';

const jsoncResult = parse_jsonc('{"key": "value"}');

if (jsoncResult.$tag === 1) {
  const jsoncNode = jsoncResult._0;

  // Transform to YAML CST
  const yamlNode = transform_jsonc_to_yaml(jsoncNode);

  // Custom processing of yamlNode...

  // Print with custom width
  const output = print_yaml(yamlNode, 100);
  console.log(output);
}
```

## Demo

Try the interactive demo at: https://f4ah6o.github.io/yyjj.mbt/

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Apache-2.0 - see [LICENSE](LICENSE) for details.

## Author

[@f4ah6o](https://github.com/f4ah6o)

## Links

- [GitHub Repository](https://github.com/f4ah6o/yyjj.mbt)
- [NPM Package](https://www.npmjs.com/package/yyjj)
- [MoonBit](https://www.moonbitlang.com/)

---

**Note:** "Don't turn YAML into .yml, or I'll turn JSON into .jsn!"
