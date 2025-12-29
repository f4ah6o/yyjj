import { useRef } from "preact/hooks";
import { json } from "@codemirror/lang-json";
import { yaml } from "@codemirror/lang-yaml";
import { EditorPane } from "./EditorPane";
import type { EditorRef } from "./Editor";
import {
	jsoncContent,
	yamlContent,
	jsoncError,
	yamlError,
	editSource,
	jsoncFilename,
	yamlFilename,
	scrollSyncEnabled,
} from "../state/store";
import { jsoncToYaml, yamlToJsonc } from "../lib/yyjj-wrapper";
import {
	readFileAsText,
	downloadFile,
	generateFilename,
} from "../utils/fileUtils";

const DEBOUNCE_MS = 300;

let jsoncTimeout: ReturnType<typeof setTimeout> | null = null;
let yamlTimeout: ReturnType<typeof setTimeout> | null = null;

function handleJsoncChange(value: string) {
	jsoncContent.value = value;

	if (jsoncTimeout) clearTimeout(jsoncTimeout);
	jsoncTimeout = setTimeout(() => {
		// Skip if this update was triggered by YAML conversion
		if (editSource.value === "yaml") {
			editSource.value = null;
			return;
		}

		const result = jsoncToYaml(value);
		if (result.tag === "Ok") {
			jsoncError.value = null;
			editSource.value = "jsonc";
			yamlContent.value = result.val;
		} else {
			jsoncError.value = result.val;
		}
	}, DEBOUNCE_MS);
}

function handleYamlChange(value: string) {
	yamlContent.value = value;

	if (yamlTimeout) clearTimeout(yamlTimeout);
	yamlTimeout = setTimeout(() => {
		// Skip if this update was triggered by JSONC conversion
		if (editSource.value === "jsonc") {
			editSource.value = null;
			return;
		}

		const result = yamlToJsonc(value);
		if (result.tag === "Ok") {
			yamlError.value = null;
			editSource.value = "yaml";
			jsoncContent.value = result.val;
		} else {
			yamlError.value = result.val;
		}
	}, DEBOUNCE_MS);
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
		} else {
			jsoncError.value = result.val;
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
		} else {
			yamlError.value = result.val;
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

	return (
		<div class="editor-layout">
			<EditorPane
				title="JSONC"
				content={jsoncContent}
				error={jsoncError}
				extensions={[json()]}
				onChange={handleJsoncChange}
				paneType="jsonc"
				filename={jsoncFilename}
				onImport={handleJsoncImport}
				onDownload={handleJsoncDownload}
				onScroll={handleJsoncScroll}
				editorRef={jsoncEditorRef}
				showSyncToggle={true}
				onToggleSync={toggleScrollSync}
			/>
			<EditorPane
				title="YAML"
				content={yamlContent}
				error={yamlError}
				extensions={[yaml()]}
				onChange={handleYamlChange}
				paneType="yaml"
				filename={yamlFilename}
				onImport={handleYamlImport}
				onDownload={handleYamlDownload}
				onScroll={handleYamlScroll}
				editorRef={yamlEditorRef}
			/>
		</div>
	);
}
