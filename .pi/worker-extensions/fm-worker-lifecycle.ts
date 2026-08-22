import { execFile } from "node:child_process";
import {
	closeSync,
	fstatSync,
	lstatSync,
	openSync,
	readSync,
	realpathSync,
} from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Stats } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CONTEXT_ENV = "FM_WORKER_LIFECYCLE_CONTEXT";
const MAX_CONTEXT_BYTES = 64 * 1024;
const TOKEN = /^[A-Za-z0-9._-]+$/;

type WorkerContext = {
	id: string;
	generation: string;
	stateDir: string;
	turnEnded: string;
};

function sameFile(left: Stats, right: Stats): boolean {
	return left.dev === right.dev && left.ino === right.ino;
}

function readStableRegular(path: string): string | undefined {
	let fd: number | undefined;
	try {
		if (!isAbsolute(path) || resolve(path) !== path || realpathSync(path) !== path) return;
		const before = lstatSync(path);
		if (!before.isFile() || before.isSymbolicLink() || before.size > MAX_CONTEXT_BYTES) return;
		fd = openSync(path, "r");
		const opened = fstatSync(fd);
		if (!opened.isFile() || !sameFile(before, opened) || opened.size > MAX_CONTEXT_BYTES) return;
		const bytes = Buffer.alloc(opened.size);
		let offset = 0;
		while (offset < bytes.length) {
			const count = readSync(fd, bytes, offset, bytes.length - offset, offset);
			if (count === 0) return;
			offset += count;
		}
		const afterFd = fstatSync(fd);
		const afterPath = lstatSync(path);
		if (!sameFile(opened, afterFd) || !sameFile(opened, afterPath)) return;
		if (opened.size !== afterFd.size || opened.mtimeMs !== afterFd.mtimeMs) return;
		return bytes.toString("utf8");
	} catch {
		return;
	} finally {
		try {
			if (fd !== undefined) closeSync(fd);
		} catch {}
	}
}

function parseMetadata(raw: string): Map<string, string> | undefined {
	if (!raw.endsWith("\n") || raw.includes("\0") || raw.includes("\r")) return;
	const fields = new Map<string, string>();
	for (const line of raw.slice(0, -1).split("\n")) {
		const separator = line.indexOf("=");
		const key = line.slice(0, separator);
		if (separator < 1 || !TOKEN.test(key) || fields.has(key)) return;
		fields.set(key, line.slice(separator + 1));
	}
	return fields;
}

function loadContext(): WorkerContext | undefined {
	const path = process.env[CONTEXT_ENV];
	if (!path) return;
	const fields = parseMetadata(readStableRegular(path) ?? "");
	if (!fields) return;
	const id = fields.get("endpoint_task_id") ?? "";
	const generation = fields.get("busy_gen") ?? "";
	const worktree = fields.get("worktree") ?? "";
	const recordedRuntime = fields.get("harness");
	if (!TOKEN.test(id) || !TOKEN.test(generation)) return;
	if (recordedRuntime !== undefined && recordedRuntime !== "pi") return;
	if (!new Set(["ship", "scout"]).has(fields.get("kind") ?? "")) return;
	const stateDir = dirname(path);
	if (path !== resolve(stateDir, `${id}.meta`)) return;
	try {
		if (realpathSync(worktree) !== realpathSync(process.cwd())) return;
	} catch {
		return;
	}
	if (readStableRegular(resolve(stateDir, `${id}.busy-gen`)) !== `${generation}\n`) return;
	return { id, generation, stateDir, turnEnded: resolve(stateDir, `${id}.turn-ended`) };
}

export default function workerLifecycle(pi: ExtensionAPI): void {
	const context = loadContext();
	if (!context) return;
	const writer = resolve(dirname(fileURLToPath(import.meta.url)), "../../bin/fm-busy-event.sh");
	const apply = (state: "busy" | "idle", event: string) =>
		new Promise<void>((done) => {
			execFile(writer, [
				"apply", context.stateDir, context.id, state,
				"--gen", context.generation, "--source", "pi-ext", "--event", event,
			], () => done());
		});

	pi.on("agent_start", () => apply("busy", "agent-start"));
	pi.on("agent_settled", (_event, ctx) => {
		if (!ctx.isIdle()) return;
		return apply("idle", "agent-settled");
	});
	pi.on("turn_end", () => {
		execFile("touch", [context.turnEnded]);
	});
}
