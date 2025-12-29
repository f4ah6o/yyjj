import { useRef } from "preact/hooks";
import { json } from "@codemirror/lang-json";
import { yaml } from "@codemirror/lang-yaml";
import { EditorPane } from "./EditorPane";
import type { EditorRef, CursorPosition } from "./Editor";
import {
	jsoncContent,
	yamlContent,
	jsoncError,
	yamlError,
	editSource,
	jsoncFilename,
	yamlFilename,
	scrollSyncEnabled,
	jsoncToYamlMappings,
	yamlToJsoncMappings,
	jsoncConverting,
	yamlConverting,
} from "../state/store";
import {
	jsoncToYaml,
	yamlToJsonc,
	jsoncToYamlWithMapping,
	yamlToJsoncWithMapping,
	lookupTargetPosition,
	lookupSourcePosition,
} from "../lib/yyjj-wrapper";
import {
	readFileAsText,
	downloadFile,
	generateFilename,
} from "../utils/fileUtils";

const DEBOUNCE_MS = 300;

let jsoncTimeout: ReturnType<typeof setTimeout> | null = null;
let yamlTimeout: ReturnType<typeof setTimeout> | null = null;

async function handleJsoncChange(
	value: string,
	cursor?: CursorPosition,
	yamlEditorRef?: { current: EditorRef | null }
) {
	jsoncContent.value = value;

	if (jsoncTimeout) clearTimeout(jsoncTimeout);
	jsoncTimeout = setTimeout(async () => {
		// Skip if this update was triggered by YAML conversion
		if (editSource.value === "yaml") {
			editSource.value = null;
			return;
		}

		jsoncConverting.value = true;
		try {
			const result = await jsoncToYamlWithMapping(value);
			if (result.tag === "Ok") {
				jsoncError.value = null;
				editSource.value = "jsonc";
				yamlContent.value = result.val.output;
				jsoncToYamlMappings.value = result.val.mappings;

				// Sync cursor position if available
				if (cursor && yamlEditorRef?.current) {
					const targetPos = await lookupTargetPosition(
						result.val.mappings,
						cursor.line,
						cursor.column,
						cursor.offset
					);
					if (targetPos) {
						yamlEditorRef.current.setCursorPosition(targetPos);
					}
				}
			} else {
				jsoncError.value = result.val;
				jsoncToYamlMappings.value = [];
			}
		} catch (error) {
			jsoncError.value = {
				message: error instanceof Error ? error.message : String(error),
				kind: "RuntimeError",
				span: { start: { line: 0, column: 0, offset: 0 }, end: { line: 0, column: 0, offset: 0 } },
			};
			jsoncToYamlMappings.value = [];
		} finally {
			jsoncConverting.value = false;
		}
	}, DEBOUNCE_MS);
}

async function handleYamlChange(
	value: string,
	cursor?: CursorPosition,
	jsoncEditorRef?: { current: EditorRef | null }
) {
	yamlContent.value = value;

	if (yamlTimeout) clearTimeout(yamlTimeout);
	yamlTimeout = setTimeout(async () => {
		// Skip if this update was triggered by JSONC conversion
		if (editSource.value === "jsonc") {
			editSource.value = null;
			return;
		}

		yamlConverting.value = true;
		try {
			const result = await yamlToJsoncWithMapping(value);
			if (result.tag === "Ok") {
				yamlError.value = null;
				editSource.value = "yaml";
				jsoncContent.value = result.val.output;
				yamlToJsoncMappings.value = result.val.mappings;

				// Sync cursor position if available
				if (cursor && jsoncEditorRef?.current) {
					const targetPos = await lookupSourcePosition(
						result.val.mappings,
						cursor.line,
						cursor.column,
						cursor.offset
					);
					if (targetPos) {
						jsoncEditorRef.current.setCursorPosition(targetPos);
					}
				}
			} else {
				yamlError.value = result.val;
				yamlToJsoncMappings.value = [];
			}
		} catch (error) {
			yamlError.value = {
				message: error instanceof Error ? error.message : String(error),
				kind: "RuntimeError",
				span: { start: { line: 0, column: 0, offset: 0 }, end: { line: 0, column: 0, offset: 0 } },
			};
			yamlToJsoncMappings.value = [];
		} finally {
			yamlConverting.value = false;
		}
	}, DEBOUNCE_MS);
}

async function handleJsoncCursorChange(
	cursor: CursorPosition,
	yamlEditorRef?: { current: EditorRef | null }
) {
	// Use the stored mappings to sync cursor position
	if (yamlEditorRef?.current && jsoncToYamlMappings.value.length > 0) {
		const targetPos = await lookupTargetPosition(
			jsoncToYamlMappings.value,
			cursor.line,
			cursor.column,
			cursor.offset
		);
		if (targetPos) {
			yamlEditorRef.current.setCursorPosition(targetPos);
		}
	}
}

async function handleYamlCursorChange(
	cursor: CursorPosition,
	jsoncEditorRef?: { current: EditorRef | null }
) {
	// Use the stored mappings to sync cursor position
	if (jsoncEditorRef?.current && yamlToJsoncMappings.value.length > 0) {
		const targetPos = await lookupSourcePosition(
			yamlToJsoncMappings.value,
			cursor.line,
			cursor.column,
			cursor.offset
		);
		if (targetPos) {
			jsoncEditorRef.current.setCursorPosition(targetPos);
		}
	}
}

async function handleJsoncImport(file: File): Promise<void> {
	try {
		const text = await readFileAsText(file);
		jsoncContent.value = text;
		jsoncFilename.value = file.name;

		jsoncConverting.value = true;
		try {
			const result = await jsoncToYaml(text);
			if (result.tag === "Ok") {
				jsoncError.value = null;
				editSource.value = "jsonc";
				yamlContent.value = result.val;
				yamlFilename.value = null;

				// Update mappings
				const mappingResult = await jsoncToYamlWithMapping(text);
				if (mappingResult.tag === "Ok") {
					jsoncToYamlMappings.value = mappingResult.val.mappings;
				}
			} else {
				jsoncError.value = result.val;
				jsoncToYamlMappings.value = [];
			}
		} catch (error) {
			jsoncError.value = {
				message: error instanceof Error ? error.message : String(error),
				kind: "RuntimeError",
				span: { start: { line: 0, column: 0, offset: 0 }, end: { line: 0, column: 0, offset: 0 } },
			};
			jsoncToYamlMappings.value = [];
		} finally {
			jsoncConverting.value = false;
		}
	} catch {
		jsoncError.value = {
			message: "Failed to read file",
			kind: "RuntimeError",
			span: { start: { line: 0, column: 0, offset: 0 }, end: { line: 0, column: 0, offset: 0 } },
		};
	}
}

async function handleYamlImport(file: File): Promise<void> {
	try {
		const text = await readFileAsText(file);
		yamlContent.value = text;
		yamlFilename.value = file.name;

		yamlConverting.value = true;
		try {
			const result = await yamlToJsonc(text);
			if (result.tag === "Ok") {
				yamlError.value = null;
				editSource.value = "yaml";
				jsoncContent.value = result.val;
				jsoncFilename.value = null;

				// Update mappings
				const mappingResult = await yamlToJsoncWithMapping(text);
				if (mappingResult.tag === "Ok") {
					yamlToJsoncMappings.value = mappingResult.val.mappings;
				}
			} else {
				yamlError.value = result.val;
				yamlToJsoncMappings.value = [];
			}
		} catch (error) {
			yamlError.value = {
				message: error instanceof Error ? error.message : String(error),
				kind: "RuntimeError",
				span: { start: { line: 0, column: 0, offset: 0 }, end: { line: 0, column: 0, offset: 0 } },
			};
			yamlToJsoncMappings.value = [];
		} finally {
			yamlConverting.value = false;
		}
	} catch {
		yamlError.value = {
			message: "Failed to read file",
			kind: "RuntimeError",
			span: { start: { line: 0, column: 0, offset: 0 }, end: { line: 0, column: 0, offset: 0 } },
		};
	}
}

function handleJsoncDownload(): void {
	const filename = jsoncFilename.value || generateFilename("output", ".jsonc");
	downloadFile(jsoncContent.value, filename, "application/json");
}

function handleYamlDownload(): void {
	const filename = yamlFilename.value || generateFilename("output", ".yaml");
	downloadFile(yamlContent.value, filename, "text/yaml");
}

export function EditorLayout() {
	const jsoncEditorRef = useRef<EditorRef | null>(null);
	const yamlEditorRef = useRef<EditorRef | null>(null);
	const isScrolling = useRef(false);

	const handleJsoncScroll = (ratio: number) => {
		if (!scrollSyncEnabled.value || isScrolling.current) return;
		isScrolling.current = true;
		yamlEditorRef.current?.scrollTo(ratio);
		requestAnimationFrame(() => {
			isScrolling.current = false;
		});
	};

	const handleYamlScroll = (ratio: number) => {
		if (!scrollSyncEnabled.value || isScrolling.current) return;
		isScrolling.current = true;
		jsoncEditorRef.current?.scrollTo(ratio);
		requestAnimationFrame(() => {
			isScrolling.current = false;
		});
	};

	const toggleScrollSync = () => {
		scrollSyncEnabled.value = !scrollSyncEnabled.value;
	};

	const wrapJsoncChange = (value: string, cursor?: CursorPosition) => {
		handleJsoncChange(value, cursor, yamlEditorRef);
	};

	const wrapYamlChange = (value: string, cursor?: CursorPosition) => {
		handleYamlChange(value, cursor, jsoncEditorRef);
	};

	const wrapJsoncCursorChange = (cursor: CursorPosition) => {
		handleJsoncCursorChange(cursor, yamlEditorRef);
	};

	const wrapYamlCursorChange = (cursor: CursorPosition) => {
		handleYamlCursorChange(cursor, jsoncEditorRef);
	};

	return (
		<div class="editor-layout">
			<EditorPane
				title="JSONC"
				content={jsoncContent}
				error={jsoncError}
				extensions={[json()]}
				onChange={wrapJsoncChange}
				paneType="jsonc"
				filename={jsoncFilename}
				onImport={handleJsoncImport}
				onDownload={handleJsoncDownload}
				onScroll={handleJsoncScroll}
				editorRef={jsoncEditorRef}
				showSyncToggle={true}
				onToggleSync={toggleScrollSync}
				onCursorChange={wrapJsoncCursorChange}
				converting={jsoncConverting}
			/>
			<EditorPane
				title="YAML"
				content={yamlContent}
				error={yamlError}
				extensions={[yaml()]}
				onChange={wrapYamlChange}
				paneType="yaml"
				filename={yamlFilename}
				onImport={handleYamlImport}
				onDownload={handleYamlDownload}
				onScroll={handleYamlScroll}
				editorRef={yamlEditorRef}
				onCursorChange={wrapYamlCursorChange}
				converting={yamlConverting}
			/>
		</div>
	);
}
