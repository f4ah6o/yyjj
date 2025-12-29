import {
	jsonc_to_yaml,
	yaml_to_jsonc,
	jsonc_to_yaml_with_mapping,
	yaml_to_jsonc_with_mapping,
} from "yyjj";
import {
	SourceMapping as YYSourceMapping,
	ConversionResult as YYConversionResult,
	lookup_target_position,
	lookup_source_position,
} from "yyjj/common";

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

// Position types
export interface Position {
	line: number;
	column: number;
	offset: number;
}

export interface SourceMapping {
	sourceStart: Position;
	sourceEnd: Position;
	targetStart: Position;
	targetEnd: Position;
}

export interface ConversionResultWithMapping {
	output: string;
	mappings: SourceMapping[];
}

export type ConversionResultMapping =
	| { tag: "Ok"; val: ConversionResultWithMapping }
	| { tag: "Err"; val: ParseError };

function normalizeConversionResult(
	result: unknown
): ConversionResultMapping {
	const r = result as { $tag: number; _0: unknown };
	if (r.$tag === 1) {
		const yyResult = r._0 as YYConversionResult;
		return {
			tag: "Ok",
			val: {
				output: yyResult.output,
				mappings: yyResult.mappings.map(toSourceMapping),
			},
		};
	}
	return { tag: "Err", val: r._0 as ParseError };
}

function toSourceMapping(yy: YYSourceMapping): SourceMapping {
	return {
		sourceStart: yy.source_start,
		sourceEnd: yy.source_end,
		targetStart: yy.target_start,
		targetEnd: yy.target_end,
	};
}

export function jsoncToYamlWithMapping(
	input: string
): ConversionResultMapping {
	const result = jsonc_to_yaml_with_mapping(input);
	return normalizeConversionResult(result);
}

export function yamlToJsoncWithMapping(
	input: string
): ConversionResultMapping {
	const result = yaml_to_jsonc_with_mapping(input);
	return normalizeConversionResult(result);
}

export function lookupTargetPosition(
	mappings: SourceMapping[],
	sourceLine: number,
	sourceColumn: number,
	sourceOffset: number
): Position | null {
	const result = lookup_target_position(
		mappings.map(toYYSourceMapping),
		sourceLine,
		sourceColumn,
		sourceOffset
	);
	if (result === null || result === undefined) return null;
	return result as Position;
}

export function lookupSourcePosition(
	mappings: SourceMapping[],
	targetLine: number,
	targetColumn: number,
	targetOffset: number
): Position | null {
	const result = lookup_source_position(
		mappings.map(toYYSourceMapping),
		targetLine,
		targetColumn,
		targetOffset
	);
	if (result === null || result === undefined) return null;
	return result as Position;
}

function toYYSourceMapping(mapping: SourceMapping): YYSourceMapping {
	return {
		source_start: mapping.sourceStart,
		source_end: mapping.sourceEnd,
		target_start: mapping.targetStart,
		target_end: mapping.targetEnd,
	};
}
