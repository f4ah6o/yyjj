import YYjjWorker from "../workers/yyjj.worker.ts?worker";

export type {
	ParseError,
	Position,
	SourceMapping,
	ConversionResult,
	ConversionResultWithMapping,
	ConversionResultMapping,
} from "../workers/yyjj.worker.ts";

type WorkerRequest = import("../workers/yyjj.worker.ts").WorkerRequest;
type WorkerResponse = import("../workers/yyjj.worker.ts").WorkerResponse;

interface PendingRequest {
	resolve: (value: any) => void;
	reject: (error: Error) => void;
	timestamp: number;
}

export class YyjjClient {
	private worker: Worker;
	private pending = new Map<string, PendingRequest>();
	private requestId = 0;
	private messageIdPrefix = "yyjj-";

	constructor() {
		this.worker = new YYjjWorker();
		this.worker.onmessage = this.handleMessage;
		this.worker.onerror = this.handleError;
	}

	async jsoncToYaml(
		input: string,
		width?: number
	): Promise<ConversionResult> {
		return this.sendRequest({
			type: "jsoncToYaml",
			id: this.getNextId(),
			input,
			width,
		});
	}

	async yamlToJsonc(
		input: string,
		width?: number
	): Promise<ConversionResult> {
		return this.sendRequest({
			type: "yamlToJsonc",
			id: this.getNextId(),
			input,
			width,
		});
	}

	async jsoncToYamlWithMapping(
		input: string
	): Promise<ConversionResultMapping> {
		return this.sendRequest({
			type: "jsoncToYamlWithMapping",
			id: this.getNextId(),
			input,
		});
	}

	async yamlToJsoncWithMapping(
		input: string
	): Promise<ConversionResultMapping> {
		return this.sendRequest({
			type: "yamlToJsoncWithMapping",
			id: this.getNextId(),
			input,
		});
	}

	async lookupTargetPosition(
		mappings: SourceMapping[],
		sourceLine: number,
		sourceColumn: number,
		sourceOffset: number
	): Promise<Position | null> {
		return this.sendRequest({
			type: "lookupTargetPosition",
			id: this.getNextId(),
			mappings,
			sourceLine,
			sourceColumn,
			sourceOffset,
		});
	}

	async lookupSourcePosition(
		mappings: SourceMapping[],
		targetLine: number,
		targetColumn: number,
		targetOffset: number
	): Promise<Position | null> {
		return this.sendRequest({
			type: "lookupSourcePosition",
			id: this.getNextId(),
			mappings,
			targetLine,
			targetColumn,
			targetOffset,
		});
	}

	private sendRequest<T>(request: WorkerRequest): Promise<T> {
		return new Promise((resolve, reject) => {
			this.pending.set(request.id, {
				resolve,
				reject,
				timestamp: Date.now(),
			});
			this.worker.postMessage(request);
		});
	}

	private handleMessage = (e: MessageEvent<WorkerResponse>) => {
		const { id, type, result, error } = e.data;
		const pending = this.pending.get(id);

		if (!pending) return;

		this.pending.delete(id);

		if (type === "error") {
			pending.reject(new Error(error));
		} else {
			pending.resolve(result);
		}
	};

	private handleError = (e: ErrorEvent) => {
		console.error("Worker error:", e.error);
	};

	private getNextId(): string {
		return `${this.messageIdPrefix}${this.requestId++}`;
	}

	terminate(): void {
		this.worker.terminate();
		this.pending.clear();
	}
}

// Singleton instance
export const yyjjClient = new YyjjClient();
