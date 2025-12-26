import { jsonc_to_yaml, yaml_to_jsonc } from "yyjj";

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

// MoonBit Result type: { $tag: 1, _0: T } (Ok) or { $tag: 0, _0: E } (Err)
function normalizeResult(result: unknown): ConversionResult {
	const r = result as { $tag: number; _0: unknown };
	if (r.$tag === 1) {
		return { tag: "Ok", val: r._0 as string };
	}
	return { tag: "Err", val: r._0 as ParseError };
}

export function jsoncToYaml(input: string, width?: number): ConversionResult {
	const result = jsonc_to_yaml(input, width);
	return normalizeResult(result);
}

export function yamlToJsonc(input: string, width?: number): ConversionResult {
	const result = yaml_to_jsonc(input, width);
	return normalizeResult(result);
}
