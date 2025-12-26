import { useRef, useEffect } from "preact/hooks";
import { EditorView, placeholder } from "@codemirror/view";
import { EditorState, type Extension } from "@codemirror/state";
import { basicSetup } from "codemirror";
import type { Signal } from "@preact/signals";

interface EditorProps {
	content: Signal<string>;
	extensions: Extension[];
	placeholder?: string;
	onChange: (value: string) => void;
}

export function Editor({
	content,
	extensions,
	placeholder: placeholderText,
	onChange,
}: EditorProps) {
	const containerRef = useRef<HTMLDivElement>(null);
	const viewRef = useRef<EditorView | null>(null);
	const isExternalUpdate = useRef(false);

	// Create editor on mount
	useEffect(() => {
		if (!containerRef.current) return;

		const updateListener = EditorView.updateListener.of((update) => {
			if (update.docChanged && !isExternalUpdate.current) {
				onChange(update.state.doc.toString());
			}
		});

		const state = EditorState.create({
			doc: content.value,
			extensions: [
				basicSetup,
				...extensions,
				updateListener,
				placeholderText ? placeholder(placeholderText) : [],
				EditorView.theme({
					"&": { height: "100%" },
					".cm-scroller": { overflow: "auto" },
				}),
			],
		});

		viewRef.current = new EditorView({
			state,
			parent: containerRef.current,
		});

		return () => viewRef.current?.destroy();
	}, []);

	// Sync external content changes
	useEffect(() => {
		const view = viewRef.current;
		if (!view) return;

		const currentDoc = view.state.doc.toString();
		if (currentDoc !== content.value) {
			isExternalUpdate.current = true;
			view.dispatch({
				changes: { from: 0, to: currentDoc.length, insert: content.value },
			});
			isExternalUpdate.current = false;
		}
	}, [content.value]);

	return <div ref={containerRef} class="editor-container" />;
}
