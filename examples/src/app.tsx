import { useEffect } from "preact/hooks";
import { EditorLayout } from "./components/EditorLayout";
import { DEFAULT_JSONC, yamlContent, editSource } from "./state/store";
import { jsoncToYaml } from "./lib/yyjj-wrapper";

declare const __YYJJ_VERSION__: string;

export function App() {
	// Initialize YAML from JSONC on first render
	useEffect(() => {
		const result = jsoncToYaml(DEFAULT_JSONC);
		if (result.tag === "Ok") {
			editSource.value = "jsonc";
			yamlContent.value = result.val;
		}
	}, []);

	return (
		<div class="app">
			<header class="app-header">
				<h1>yyjj</h1>
				<p class="app-subtitle">JSONC ⇔ YAML Converter with Comment Preservation</p>
			</header>
			<main class="app-main">
				<EditorLayout />
			</main>
			<footer class="app-footer">
				<a
					href="https://github.com/f4ah6o/yyjj.mbt"
					target="_blank"
					rel="noopener noreferrer"
				>
					GitHub
				</a>
				<span class="separator">|</span>
				<a
					href="https://www.npmjs.com/package/yyjj"
					target="_blank"
					rel="noopener noreferrer"
				>
					npm
				</a>
				<span class="separator">|</span>
				<span class="version">v{__YYJJ_VERSION__}</span>
			</footer>
		</div>
	);
}
