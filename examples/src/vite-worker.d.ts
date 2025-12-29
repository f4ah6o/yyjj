declare module "*?worker" {
	import { Worker } from "worker_threads";
	const workerConstructor: new () => Worker;
	export default workerConstructor;
}

declare module "*?worker&url" {
	const workerUrl: string;
	export default workerUrl;
}

declare module "*?sharedworker" {
	import { SharedWorker } from "worker_threads";
	const sharedWorkerConstructor: new () => SharedWorker;
	export default sharedWorkerConstructor;
}

declare module "*?sharedworker&url" {
	const sharedWorkerUrl: string;
	export default sharedWorkerUrl;
}

export {};
