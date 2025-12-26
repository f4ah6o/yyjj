import { EditorLayout } from "./components/EditorLayout";

export function App() {
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
			</footer>
		</div>
	);
}
