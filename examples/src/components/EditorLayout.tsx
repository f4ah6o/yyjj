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

function handleJsoncChange(
	value: string,
	cursor?: CursorPosition,
	yamlEditorRef?: { current: EditorRef | null }
) {
	jsoncContent.value = value;

	if (jsoncTimeout) clearTimeout(jsoncTimeout);
	jsoncTimeout = setTimeout(() => {
		// Skip if this update was triggered by YAML conversion
		if (editSource.value === "yaml") {
			editSource.value = null;
			return;
		}

		const result = jsoncToYamlWithMapping(value);
		if (result.tag === "Ok") {
			jsoncError.value = null;
			editSource.value = "jsonc";
			yamlContent.value = result.val.output;
			jsoncToYamlMappings.value = result.val.mappings;

			// Sync cursor position if available
			if (cursor && yamlEditorRef?.current) {
				const targetPos = lookupTargetPosition(
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
	}, DEBOUNCE_MS);
}

function handleYamlChange(
	value: string,
	cursor?: CursorPosition,
	jsoncEditorRef?: { current: EditorRef | null }
) {
	yamlContent.value = value;

	if (yamlTimeout) clearTimeout(yamlTimeout);
	yamlTimeout = setTimeout(() => {
		// Skip if this update was triggered by JSONC conversion
		if (editSource.value === "jsonc") {
			editSource.value = null;
			return;
		}

		const result = yamlToJsoncWithMapping(value);
		if (result.tag === "Ok") {
			yamlError.value = null;
			editSource.value = "yaml";
			jsoncContent.value = result.val.output;
			yamlToJsoncMappings.value = result.val.mappings;

			// Sync cursor position if available
			if (cursor && jsoncEditorRef?.current) {
				const targetPos = lookupSourcePosition(
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
	}, DEBOUNCE_MS);
}

function handleJsoncCursorChange(
	cursor: CursorPosition,
	yamlEditorRef?: { current: EditorRef | null }
) {
	// Use the stored mappings to sync cursor position
	if (yamlEditorRef?.current && jsoncToYamlMappings.value.length > 0) {
		const targetPos = lookupTargetPosition(
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

function handleYamlCursorChange(
	cursor: CursorPosition,
	jsoncEditorRef?: { current: EditorRef | null }
) {
	// Use the stored mappings to sync cursor position
	if (jsoncEditorRef?.current && yamlToJsoncMappings.value.length > 0) {
		const targetPos = lookupSourcePosition(
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

		const result = jsoncToYaml(text);
		if (result.tag === "Ok") {
			jsoncError.value = null;
			editSource.value = "jsonc";
			yamlContent.value = result.val;
			yamlFilename.value = null;

			// Update mappings
			const mappingResult = jsoncToYamlWithMapping(text);
			if (mappingResult.tag === "Ok") {
				jsoncToYamlMappings.value = mappingResult.val.mappings;
			}
		} else {
			jsoncError.value = result.val;
			jsoncToYamlMappings.value = [];
		}
	} catch {
		jsoncError.value = {
			message: "Failed to read file",
			span: { start: { line: 0, column: 0 }, end: { line: 0, column: 0 } },
		};
	}
}

async function handleYamlImport(file: File): Promise<void> {
	try {
		const text = await readFileAsText(file);
		yamlContent.value = text;
		yamlFilename.value = file.name;

		const result = yamlToJsonc(text);
		if (result.tag === "Ok") {
			yamlError.value = null;
			editSource.value = "yaml";
			jsoncContent.value = result.val;
			jsoncFilename.value = null;

			// Update mappings
			const mappingResult = yamlToJsoncWithMapping(text);
			if (mappingResult.tag === "Ok") {
				yamlToJsoncMappings.value = mappingResult.val.mappings;
			}
		} else {
			yamlError.value = result.val;
			yamlToJsoncMappings.value = [];
		}
	} catch {
		yamlError.value = {
			message: "Failed to read file",
			span: { start: { line: 0, column: 0 }, end: { line: 0, column: 0 } },
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
			/>
		</div>
	);
}
