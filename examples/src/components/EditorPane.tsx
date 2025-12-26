import type { Signal } from "@preact/signals";
import type { Extension } from "@codemirror/state";
import { Editor } from "./Editor";
import type { ParseError } from "../lib/yyjj-wrapper";

interface EditorPaneProps {
	title: string;
	content: Signal<string>;
	error: Signal<ParseError | null>;
	extensions: Extension[];
	onChange: (value: string) => void;
}

export function EditorPane({
	title,
	content,
	error,
	extensions,
	onChange,
}: EditorPaneProps) {
	const errorValue = error.value;

	return (
		<div class="editor-pane">
			<div class="editor-header">
				<span class="editor-title">{title}</span>
				{errorValue && <span class="editor-error-badge">Error</span>}
			</div>
			<Editor
				content={content}
				extensions={extensions}
				onChange={onChange}
				placeholder={`Enter ${title} here...`}
			/>
			{errorValue && (
				<div class="editor-error">
					<span class="error-location">
						Line {errorValue.span.start.line + 1}, Column{" "}
						{errorValue.span.start.column + 1}
					</span>
					<span class="error-message">{errorValue.message}</span>
				</div>
			)}
		</div>
	);
}
