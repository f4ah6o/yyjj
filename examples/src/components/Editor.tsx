import { useRef, useEffect, useImperativeHandle, useLayoutEffect } from "preact/hooks";
import { EditorView, placeholder } from "@codemirror/view";
import { EditorState, type Extension } from "@codemirror/state";
import { basicSetup } from "codemirror";
import type { Signal } from "@preact/signals";

export interface CursorPosition {
	line: number;
	column: number;
	offset: number;
}

export interface EditorRef {
	scrollTo(ratio: number): void;
	getCursorPosition(): CursorPosition;
	setCursorPosition(position: CursorPosition): void;
}

interface EditorProps {
	content: Signal<string>;
	extensions: Extension[];
	placeholder?: string;
	onChange: (value: string, cursor?: CursorPosition) => void;
	onScroll?: (ratio: number) => void;
	editorRef?: { current: EditorRef | null };
	onCursorChange?: (cursor: CursorPosition) => void;
}

export function Editor({
	content,
	extensions,
	placeholder: placeholderText,
	onChange,
	onScroll,
	editorRef,
	onCursorChange,
}: EditorProps) {
	const containerRef = useRef<HTMLDivElement>(null);
	const viewRef = useRef<EditorView | null>(null);
	const isExternalUpdate = useRef(false);
	const isScrollingFromOutside = useRef(false);

	// Expose scrollTo method to parent
	useImperativeHandle(
		editorRef,
		() => ({
			scrollTo(ratio: number) {
				const view = viewRef.current;
				if (!view) return;
				const scroller = view.dom.querySelector(".cm-scroller") as HTMLElement;
				if (!scroller) return;

				const scrollHeight = scroller.scrollHeight - scroller.clientHeight;
				const targetScrollTop = scrollHeight * ratio;

				isScrollingFromOutside.current = true;
				scroller.scrollTop = targetScrollTop;
				requestAnimationFrame(() => {
					isScrollingFromOutside.current = false;
				});
			},
			getCursorPosition(): CursorPosition {
				const view = viewRef.current;
				if (!view) return { line: 0, column: 0, offset: 0 };

				const pos = view.state.selection.main.head;
				const line = view.state.doc.lineAt(pos);
				const lineNumber = view.state.doc.lineAt(pos).number - 1; // 0-indexed
				const column = pos - line.from; // 0-indexed column within line

				return { line: lineNumber, column, offset: pos };
			},
			setCursorPosition(position: CursorPosition) {
				const view = viewRef.current;
				if (!view) return;

				// Find the position for the given line and column
				const lineIndex = position.line + 1; // CodeMirror lines are 1-indexed
				if (lineIndex < 1 || lineIndex > view.state.doc.lines) return;

				const line = view.state.doc.line(lineIndex);
				const targetPos = Math.min(line.from + position.column, line.to);

				view.dispatch({
					selection: { anchor: targetPos, head: targetPos },
					scrollIntoView: true,
				});
			},
		}),
		[],
	);

	// Create editor on mount
	useEffect(() => {
		if (!containerRef.current) return;

		const updateListener = EditorView.updateListener.of((update) => {
			if (update.docChanged && !isExternalUpdate.current) {
				const pos = update.state.selection.main.head;
				const line = update.state.doc.lineAt(pos);
				const lineNumber = update.state.doc.lineAt(pos).number - 1;
				const column = pos - line.from;

				onChange(update.state.doc.toString(), {
					line: lineNumber,
					column,
					offset: pos,
				});
			}
			// Notify on cursor movement (even without doc change)
			if (onCursorChange && (update.selectionSet || update.docChanged)) {
				const pos = update.state.selection.main.head;
				const line = update.state.doc.lineAt(pos);
				const lineNumber = update.state.doc.lineAt(pos).number - 1;
				const column = pos - line.from;

				onCursorChange({
					line: lineNumber,
					column,
					offset: pos,
				});
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

	// Setup scroll listener after view is created
	useLayoutEffect(() => {
		const view = viewRef.current;
		if (!view || !onScroll) return;

		const scroller = view.dom.querySelector(".cm-scroller") as HTMLElement;
		if (!scroller) return;

		const handleScroll = () => {
			if (isScrollingFromOutside.current) return;

			const scrollHeight = scroller.scrollHeight - scroller.clientHeight;
			const ratio = scrollHeight > 0 ? scroller.scrollTop / scrollHeight : 0;
			onScroll(ratio);
		};

		scroller.addEventListener("scroll", handleScroll, { passive: true });
		return () => scroller.removeEventListener("scroll", handleScroll);
	}, [onScroll]);

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
