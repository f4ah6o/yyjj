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

// Types
export interface ParseError {
	kind: unknown;
	span: {
		start: { line: number; column: number; offset: number };
		end: { line: number; column: number; offset: number };
	};
	message: string;
}

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

export type ConversionResult =
	| { tag: "Ok"; val: string }
	| { tag: "Err"; val: ParseError };

export type ConversionResultMapping =
	| { tag: "Ok"; val: ConversionResultWithMapping }
	| { tag: "Err"; val: ParseError };

// Worker Message Types
export type WorkerRequest =
	| { type: "jsoncToYaml"; id: string; input: string; width?: number }
	| { type: "yamlToJsonc"; id: string; input: string; width?: number }
	| { type: "jsoncToYamlWithMapping"; id: string; input: string }
	| { type: "yamlToJsoncWithMapping"; id: string; input: string }
	| {
			type: "lookupTargetPosition";
			id: string;
			mappings: SourceMapping[];
			sourceLine: number;
			sourceColumn: number;
			sourceOffset: number;
	  }
	| {
			type: "lookupSourcePosition";
			id: string;
			mappings: SourceMapping[];
			targetLine: number;
			targetColumn: number;
			targetOffset: number;
	  };

export type WorkerResponse =
	| { type: "success"; id: string; result: ConversionResult }
	| { type: "success"; id: string; result: ConversionResultMapping }
	| { type: "success"; id: string; result: Position | null }
	| { type: "error"; id: string; error: string };

// Helper functions
function normalizeResult(result: unknown): ConversionResult {
	const r = result as { $tag: number; _0: unknown };
	if (r.$tag === 1) {
		return { tag: "Ok", val: r._0 as string };
	}
	return { tag: "Err", val: r._0 as ParseError };
}

function normalizeConversionResult(result: unknown): ConversionResultMapping {
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

function toYYSourceMapping(mapping: SourceMapping): YYSourceMapping {
	return {
		source_start: mapping.sourceStart,
		source_end: mapping.sourceEnd,
		target_start: mapping.targetStart,
		target_end: mapping.targetEnd,
	};
}

// Worker entry point
self.onmessage = (e: MessageEvent<WorkerRequest>) => {
	const { type, id } = e.data;

	try {
		switch (type) {
			case "jsoncToYaml": {
				const { input, width } = e.data;
				const result = jsonc_to_yaml(input, width);
				const response: WorkerResponse = {
					type: "success",
					id,
					result: normalizeResult(result),
				};
				self.postMessage(response);
				break;
			}
			case "yamlToJsonc": {
				const { input, width } = e.data;
				const result = yaml_to_jsonc(input, width);
				const response: WorkerResponse = {
					type: "success",
					id,
					result: normalizeResult(result),
				};
				self.postMessage(response);
				break;
			}
			case "jsoncToYamlWithMapping": {
				const { input } = e.data;
				const result = jsonc_to_yaml_with_mapping(input);
				const response: WorkerResponse = {
					type: "success",
					id,
					result: normalizeConversionResult(result),
				};
				self.postMessage(response);
				break;
			}
			case "yamlToJsoncWithMapping": {
				const { input } = e.data;
				const result = yaml_to_jsonc_with_mapping(input);
				const response: WorkerResponse = {
					type: "success",
					id,
					result: normalizeConversionResult(result),
				};
				self.postMessage(response);
				break;
			}
			case "lookupTargetPosition": {
				const { mappings, sourceLine, sourceColumn, sourceOffset } = e.data;
				const result = lookup_target_position(
					mappings.map(toYYSourceMapping),
					sourceLine,
					sourceColumn,
					sourceOffset
				);
				const response: WorkerResponse = {
					type: "success",
					id,
					result: result === null || result === undefined ? null : (result as Position),
				};
				self.postMessage(response);
				break;
			}
			case "lookupSourcePosition": {
				const { mappings, targetLine, targetColumn, targetOffset } = e.data;
				const result = lookup_source_position(
					mappings.map(toYYSourceMapping),
					targetLine,
					targetColumn,
					targetOffset
				);
				const response: WorkerResponse = {
					type: "success",
					id,
					result: result === null || result === undefined ? null : (result as Position),
				};
				self.postMessage(response);
				break;
			}
			default: {
				const _exhaustive: never = e.data;
				const response: WorkerResponse = {
					type: "error",
					id,
					error: `Unknown request type: ${String(_exhaustive)}`,
				};
				self.postMessage(response);
			}
		}
	} catch (error) {
		const response: WorkerResponse = {
			type: "error",
			id,
			error: error instanceof Error ? error.message : String(error),
		};
		self.postMessage(response);
	}
};

export type {};
