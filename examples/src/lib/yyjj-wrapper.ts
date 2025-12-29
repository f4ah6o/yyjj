// Re-export all types from yyjj-client
export type {
	ParseError,
	Position,
	SourceMapping,
	ConversionResult,
	ConversionResultWithMapping,
	ConversionResultMapping,
} from "./yyjj-client.ts";

import { yyjjClient } from "./yyjj-client.ts";

/**
 * Convert JSONC to YAML.
 * @param input - JSONC string
 * @param width - Optional line width for formatting
 * @returns Promise resolving to conversion result
 */
export async function jsoncToYaml(
	input: string,
	width?: number
): Promise<ConversionResult> {
	return yyjjClient.jsoncToYaml(input, width);
}

/**
 * Convert YAML to JSONC.
 * @param input - YAML string
 * @param width - Optional line width for formatting
 * @returns Promise resolving to conversion result
 */
export async function yamlToJsonc(
	input: string,
	width?: number
): Promise<ConversionResult> {
	return yyjjClient.yamlToJsonc(input, width);
}

/**
 * Convert JSONC to YAML with source mapping.
 * @param input - JSONC string
 * @returns Promise resolving to conversion result with mappings
 */
export async function jsoncToYamlWithMapping(
	input: string
): Promise<ConversionResultMapping> {
	return yyjjClient.jsoncToYamlWithMapping(input);
}

/**
 * Convert YAML to JSONC with source mapping.
 * @param input - YAML string
 * @returns Promise resolving to conversion result with mappings
 */
export async function yamlToJsoncWithMapping(
	input: string
): Promise<ConversionResultMapping> {
	return yyjjClient.yamlToJsoncWithMapping(input);
}

/**
 * Look up target position from source position using mappings.
 * @param mappings - Source mappings
 * @param sourceLine - Source line number (0-indexed)
 * @param sourceColumn - Source column number (0-indexed)
 * @param sourceOffset - Source character offset
 * @returns Promise resolving to target position or null
 */
export async function lookupTargetPosition(
	mappings: SourceMapping[],
	sourceLine: number,
	sourceColumn: number,
	sourceOffset: number
): Promise<Position | null> {
	return yyjjClient.lookupTargetPosition(
		mappings,
		sourceLine,
		sourceColumn,
		sourceOffset
	);
}

/**
 * Look up source position from target position using mappings.
 * @param mappings - Source mappings
 * @param targetLine - Target line number (0-indexed)
 * @param targetColumn - Target column number (0-indexed)
 * @param targetOffset - Target character offset
 * @returns Promise resolving to source position or null
 */
export async function lookupSourcePosition(
	mappings: SourceMapping[],
	targetLine: number,
	targetColumn: number,
	targetOffset: number
): Promise<Position | null> {
	return yyjjClient.lookupSourcePosition(
		mappings,
		targetLine,
		targetColumn,
		targetOffset
	);
}
