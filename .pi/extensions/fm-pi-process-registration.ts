import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, constants, copyFileSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const extensionFile = fileURLToPath(import.meta.url);
const extensionVersion = `sha256:${createHash("sha256").update(readFileSync(extensionFile)).digest("hex")}`;

function processStartIdentity(): string {
  const result = spawnSync("ps", ["-o", "lstart=", "-p", String(process.pid)], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : "";
}

export function registerPiProcess(state: string): () => void {
  const start = processStartIdentity();
  const cli = process.argv[1] ? realpathSync(process.argv[1]) : "";
  const launchId = `${process.pid}-${createHash("sha256").update(start).digest("hex")}`;
  const launchDir = `${state}/.pi-launches`;
  const imageDir = `${launchDir}/images`;
  const image = `${imageDir}/${extensionVersion.slice(7)}.ts`;
  const launch = `${launchDir}/${launchId}`;
  const launchContents = `${extensionVersion}\n${process.pid}\n${start}\n${image}\n${cli}\n${extensionFile}\n`;
  const markerDir = `${state}/.pi-processes`;
  const marker = `${markerDir}/${process.pid}`;
  const temp = `${marker}.${process.pid}.tmp`;
  mkdirSync(imageDir, { recursive: true });
  try {
    copyFileSync(extensionFile, image, constants.COPYFILE_EXCL);
    chmodSync(image, 0o444);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST" || createHash("sha256").update(readFileSync(image)).digest("hex") !== extensionVersion.slice(7)) throw error;
  }
  try {
    writeFileSync(launch, launchContents, { flag: "wx", mode: 0o444 });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST" || readFileSync(launch, "utf8") !== launchContents) throw error;
  }
  mkdirSync(markerDir, { recursive: true });
  writeFileSync(temp, `${extensionVersion}\n${process.pid}\n${start}\n${extensionFile}\n${cli}\n${launch}\n`);
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
  installPiProcessRegistration(pi, process.env.FM_PI_PROCESS_REGISTRATION_STATE || process.env.FM_STATE_OVERRIDE || `${process.env.FM_HOME || process.cwd()}/state`);
}
