import type { Signal } from "@preact/signals";
import type { Extension } from "@codemirror/state";
import { useRef, useState } from "preact/hooks";
import { Editor, type EditorRef, type CursorPosition } from "./Editor";
import type { ParseError } from "../lib/yyjj-wrapper";
import type { FileType } from "../utils/fileUtils";
import { getFileType } from "../utils/fileUtils";
import { scrollSyncEnabled } from "../state/store";

interface EditorPaneProps {
	title: string;
	content: Signal<string>;
	error: Signal<ParseError | null>;
	extensions: Extension[];
	onChange: (value: string, cursor?: CursorPosition) => void;
	paneType: FileType;
	filename: Signal<string | null>;
	onImport: (file: File) => Promise<void>;
	onDownload: () => void;
	onScroll?: (ratio: number) => void;
	editorRef?: { current: EditorRef | null };
	showSyncToggle?: boolean;
	onToggleSync?: () => void;
	onCursorChange?: (cursor: CursorPosition) => void;
	converting?: Signal<boolean>;
}

export function EditorPane({
	title,
	content,
	error,
	extensions,
	onChange,
	paneType,
	filename,
	onImport,
	onDownload,
	onScroll,
	editorRef,
	showSyncToggle = false,
	onToggleSync,
	onCursorChange,
	converting,
}: EditorPaneProps) {
	const errorValue = error.value;
	const convertingValue = converting?.value ?? false;
	const fileInputRef = useRef<HTMLInputElement>(null);
	const [isDraggingOver, setIsDraggingOver] = useState(false);

	const handleDragOver = (e: DragEvent): void => {
		e.preventDefault();
		e.stopPropagation();
		setIsDraggingOver(true);
	};

	const handleDragLeave = (e: DragEvent): void => {
		e.preventDefault();
		e.stopPropagation();
		setIsDraggingOver(false);
	};

	const handleDrop = async (e: DragEvent): Promise<void> => {
		e.preventDefault();
		e.stopPropagation();
		setIsDraggingOver(false);

		const files = e.dataTransfer?.files;
		if (!files || files.length === 0) return;

		const file = files[0];
		const fileType = getFileType(file.name);

		if (fileType !== paneType) {
			return;
		}

		await onImport(file);
	};

	const handleFileSelect = async (
		e: Event,
	): Promise<void> => {
		const target = e.target as HTMLInputElement;
		const file = target.files?.[0];
		if (file) {
			await onImport(file);
		}
		// Reset input value to allow selecting the same file again
		target.value = "";
	};

	const acceptedFileExtensions =
		paneType === "jsonc" ? ".json,.jsonc" : ".yaml";

	return (
		<div
			class={`editor-pane ${isDraggingOver ? "drag-over" : ""}`}
			onDragOver={handleDragOver}
			onDragLeave={handleDragLeave}
			onDrop={handleDrop}
		>
			<div class="editor-header">
				<div class="editor-header-left">
					<span class="editor-title">{title}</span>
					{filename.value && (
						<span class="editor-filename" title={filename.value}>
							{filename.value}
						</span>
					)}
					{convertingValue && (
						<span class="editor-converting-badge" title="Converting...">
							 Converting...
						</span>
					)}
					{errorValue && <span class="editor-error-badge">Error</span>}
				</div>
				<div class="editor-header-right">
					{showSyncToggle && onToggleSync && (
						<button
							type="button"
							class={`editor-button sync-toggle ${
								scrollSyncEnabled.value ? "active" : ""
							}`}
							onClick={onToggleSync}
							aria-label="Toggle scroll sync"
						>
							Sync: {scrollSyncEnabled.value ? "ON" : "OFF"}
						</button>
					)}
					<button
						type="button"
						class="editor-button editor-button-import"
						onClick={() => fileInputRef.current?.click()}
						aria-label="Import file"
					>
						Import
					</button>
					<button
						type="button"
						class="editor-button editor-button-download"
						onClick={onDownload}
						aria-label="Download file"
					>
						Download
					</button>
					<input
						type="file"
						ref={fileInputRef}
						class="hidden-file-input"
						onChange={handleFileSelect}
						accept={acceptedFileExtensions}
					/>
				</div>
			</div>
			<Editor
				content={content}
				extensions={extensions}
				onChange={onChange}
				onScroll={onScroll}
				editorRef={editorRef}
				onCursorChange={onCursorChange}
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
