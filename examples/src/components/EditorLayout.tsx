import { json } from "@codemirror/lang-json";
import { yaml } from "@codemirror/lang-yaml";
import { EditorPane } from "./EditorPane";
import {
	jsoncContent,
	yamlContent,
	jsoncError,
	yamlError,
	editSource,
} from "../state/store";
import { jsoncToYaml, yamlToJsonc } from "../lib/yyjj-wrapper";

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

export function EditorLayout() {
	return (
		<div class="editor-layout">
			<EditorPane
				title="JSONC"
				content={jsoncContent}
				error={jsoncError}
				extensions={[json()]}
				onChange={handleJsoncChange}
			/>
			<EditorPane
				title="YAML"
				content={yamlContent}
				error={yamlError}
				extensions={[yaml()]}
				onChange={handleYamlChange}
			/>
		</div>
	);
}
