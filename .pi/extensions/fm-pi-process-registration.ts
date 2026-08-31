import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const extensionFile = fileURLToPath(import.meta.url);
const extensionVersion = `sha256:${createHash("sha256").update(readFileSync(extensionFile)).digest("hex")}`;

function processStartIdentity(): string {
  const result = spawnSync("ps", ["-o", "lstart=", "-p", String(process.pid)], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : "";
}

export function registerPiProcess(state: string): () => void {
  const markerDir = `${state}/.pi-processes`;
  const marker = `${markerDir}/${process.pid}`;
  const temp = `${marker}.${process.pid}.tmp`;
  mkdirSync(markerDir, { recursive: true });
  writeFileSync(temp, `${extensionVersion}\n${process.pid}\n${processStartIdentity()}\n${extensionFile}\n${process.argv[1] ? realpathSync(process.argv[1]) : ""}\n`);
  renameSync(temp, marker);
  return () => {
    rmSync(marker, { force: true });
    rmSync(temp, { force: true });
  };
}

export function installPiProcessRegistration(pi: ExtensionAPI, state: string): void {
  let clear = registerPiProcess(state);
  pi.on?.("session_start", () => {
    clear();
    clear = registerPiProcess(state);
  });
  pi.on?.("session_shutdown", () => clear());
}

export default function (pi: ExtensionAPI): void {
  installPiProcessRegistration(pi, process.env.FM_STATE_OVERRIDE || `${process.env.FM_HOME || process.cwd()}/state`);
}
