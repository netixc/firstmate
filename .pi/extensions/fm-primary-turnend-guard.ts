// Firstmate primary turn-end guard, session claim, and operational-turn settle
// owner for Pi.
//
// Session claim: `bin/fm-sessionstart-nudge.sh` remains the single owner of
// "is this a genuine firstmate primary whose current harness session has not
// claimed the home lock". When it prints a nudge, this extension RUNS
// `bin/fm-session-start.sh` itself, exactly once per Pi runtime, and delivers
// the complete digest into model context. Correctness therefore no longer
// depends on a model obeying a hidden, non-triggering instruction. Set
// FM_PI_SESSION_START_AUTORUN=0 to fall back to the advisory nudge.
//
// Settle ownership: this extension owns `agent_settled`, so it is also the
// single place that settles the shared operational-turn latch in
// `lib/fm-operational-turn.ts` - retrying a bounded number of times when an
// operational turn performed no operational action, and escalating compactly
// instead of generating more visible answers. `docs/turnend-guard.md` owns the
// guard contract and `docs/sessionstart-nudge.md` owns the session-start
// transport contract.
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { encodeFirstmateOperationalInput } from "./lib/fm-operational-input.ts";
import {
  FIRSTMATE_ARM_REQUEST_EVENT,
  FIRSTMATE_OPERATIONAL_ESCALATION_TYPE,
  installOperationalTurnCoordinator,
  registerOperationalEscalationPresentation,
  type FirstmateOperationalEscalation,
  type OperationalTurnCoordinator,
  type OperationalTurnSettlement,
} from "./lib/fm-operational-turn.ts";

type LockOwnership = "owned" | "missing" | "other";

type SessionStartResult = {
  ok: boolean;
  digest: string;
  failure: string;
};

const extensionFile = fileURLToPath(import.meta.url);
const extensionDir = dirname(extensionFile);
const root = resolve(extensionDir, "../..");
const fmHome = process.env.FM_HOME || process.env.FM_ROOT_OVERRIDE || root;
const state = process.env.FM_STATE_OVERRIDE || `${fmHome}/state`;
const marker = `${state}/.pi-turnend-extension-loaded`;
const extensionVersion = `sha256:${createHash("sha256").update(readFileSync(extensionFile)).digest("hex")}`;
const sessionStartAutorun = process.env.FM_PI_SESSION_START_AUTORUN !== "0";
const sessionStartTimeoutMs = positiveInteger("FM_PI_SESSION_START_TIMEOUT_MS", 600000);
const sessionStartKillGraceMs = positiveInteger("FM_PI_SESSION_START_KILL_GRACE_MS", 5000);

let sessionStartLifecycle: Promise<void> | null = null;

function positiveInteger(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  if (!Number.isFinite(value) || value <= 0) return fallback;
  return Math.floor(value);
}

function parentPid(pid: string): string {
  const result = spawnSync("ps", ["-o", "ppid=", "-p", pid], { encoding: "utf8" });
  if (result.status !== 0) return "";
  return result.stdout.trim();
}

function pidAlive(pid: string): boolean {
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch {
    return false;
  }
}

function lockOwnership(): LockOwnership {
  let lockPid = "";
  try {
    lockPid = readFileSync(`${state}/.lock`, "utf8").trim();
  } catch {
    return "missing";
  }
  if (!/^[0-9]+$/.test(lockPid) || lockPid === "1") return "other";
  let pid = String(process.pid);
  for (let i = 0; i < 8; i += 1) {
    if (pid === lockPid) return "owned";
    pid = parentPid(pid);
    if (!pid || pid === "1") break;
  }
  return pidAlive(lockPid) ? "other" : "missing";
}

function markLoaded(): void {
  if (!existsSync(state) || lockOwnership() === "other") return;
  writeFileSync(marker, `${extensionVersion}\n${process.pid}\n`);
}

function runSessionstartNudge(): string {
  const result = spawnSync(`${root}/bin/fm-sessionstart-nudge.sh`, [], { encoding: "utf8" });
  if (result.status !== 0) return "";
  return result.stdout.trim();
}

function processGroupAlive(pid: number): boolean {
  try {
    process.kill(-pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

function signalProcessGroup(pid: number, signal: NodeJS.Signals): void {
  try {
    process.kill(-pid, signal);
  } catch {
  }
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolveWait) => setTimeout(resolveWait, milliseconds));
}

// Run the guarded session-start lifecycle exactly as a model-driven turn would:
// one `bin/fm-session-start.sh` subprocess whose ancestry is this Pi process, so
// bin/fm-lock.sh records this harness pid. The script owns lock refusal, so a
// home another live session already holds is reported read-only in the digest
// instead of being claimed a second time.
function runSessionStart(): Promise<SessionStartResult> {
  return new Promise((resolveResult) => {
    const child = spawn(`${root}/bin/fm-session-start.sh`, [], {
      cwd: root,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    let timedOut = false;
    let resolveClosed: () => void = () => {};
    const closed = new Promise<void>((resolveChildClosed) => {
      resolveClosed = resolveChildClosed;
    });
    const finish = (result: SessionStartResult): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolveResult(result);
    };
    const timer = setTimeout(() => {
      timedOut = true;
      const pid = child.pid;
      if (!pid) {
        finish({ ok: false, digest: stdout, failure: `bin/fm-session-start.sh did not finish within ${sessionStartTimeoutMs}ms` });
        return;
      }
      signalProcessGroup(pid, "SIGTERM");
      void (async () => {
        await wait(sessionStartKillGraceMs);
        if (processGroupAlive(pid)) signalProcessGroup(pid, "SIGKILL");
        await closed;
        while (processGroupAlive(pid)) await wait(25);
        finish({
          ok: false,
          digest: stdout,
          failure: `bin/fm-session-start.sh did not finish within ${sessionStartTimeoutMs}ms; its process tree was terminated`,
        });
      })();
    }, sessionStartTimeoutMs);
    timer.unref();
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    child.on("error", (error: Error) => {
      resolveClosed();
      finish({ ok: false, digest: "", failure: `bin/fm-session-start.sh could not start: ${error.message}` });
    });
    child.on("close", (code: number | null) => {
      resolveClosed();
      if (timedOut) return;
      if (code === 0 && stdout.trim()) {
        finish({ ok: true, digest: stdout.replace(/\n+$/, ""), failure: "" });
        return;
      }
      finish({
        ok: false,
        digest: stdout,
        failure: `bin/fm-session-start.sh exited ${code ?? "unknown"}${stderr.trim() ? `: ${stderr.trim()}` : ""}`,
      });
    });
  });
}

function runGuard(): Promise<{ code: number; stderr: string }> {
  return new Promise((resolveResult) => {
    const child = spawn(`${root}/bin/fm-turnend-guard.sh`, {
      stdio: ["pipe", "ignore", "pipe"],
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", () => resolveResult({ code: 0, stderr: "" }));
    child.on("close", (code) => resolveResult({ code: code ?? 0, stderr }));
    child.stdin.end('{"stop_hook_active":false}');
  });
}

// PreToolUse seatbelts (bin/fm-arm-pretool-check.sh, docs/arm-pretool-check.md;
// bin/fm-cd-pretool-check.sh, docs/cd-guard.md). Both piggyback on this same
// extension file rather than separate ones so no extra Pi -e flag is needed at
// launch - the primary already loads this file for the turn-end guard, and
// pi.on("tool_call", ...) can block (verified 2026-07-09 against pi 0.80.5:
// returning {block: true} prevents the bash command from running). Each owner
// script owns its own decision and is inert outside the real primary checkout.
function runChecker(script: string, command: string): Promise<{ code: number; stderr: string }> {
  return new Promise((resolveResult) => {
    const child = spawn(`${root}/bin/${script}`, ["--command", command], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", () => resolveResult({ code: 0, stderr: "" }));
    child.on("close", (code) => resolveResult({ code: code ?? 0, stderr }));
  });
}

function runPretoolCheck(command: string): Promise<{ code: number; stderr: string }> {
  return runChecker("fm-arm-pretool-check.sh", command);
}

function runCdCheck(command: string): Promise<{ code: number; stderr: string }> {
  return runChecker("fm-cd-pretool-check.sh", command);
}

export default function (pi: ExtensionAPI) {
  const coordinator: OperationalTurnCoordinator = installOperationalTurnCoordinator(pi, state);
  registerOperationalEscalationPresentation(pi);
  // Identity of the queued records the last operational follow-up was sent for.
  let lastQueueFingerprint = "";

  async function deliverOperational(
    kind: "watcher" | "turn-end-guard" | "session-start",
    body: string,
  ): Promise<boolean> {
    if (!coordinator.claim(kind)) return false;
    try {
      await pi.sendUserMessage(encodeFirstmateOperationalInput(kind, body), { deliverAs: "followUp" });
      return true;
    } catch {
      coordinator.settle();
      return false;
    }
  }

  function escalate(ctx: ExtensionContext, message: string): void {
    try {
      pi.appendEntry<FirstmateOperationalEscalation>(FIRSTMATE_OPERATIONAL_ESCALATION_TYPE, { message });
    } catch {
    }
    try {
      ctx.ui.notify(message, "warning");
    } catch {
    }
  }

  function escalateFailedDelivery(ctx: ExtensionContext, attempts: number): void {
    escalate(
      ctx,
      `Firstmate supervision stopped retrying after ${attempts} operational deliveries produced no wake drain, ` +
        "session start, or watcher repair. Queued wake records are preserved and remain unhandled. " +
        "Run `bin/fm-wake-drain.sh` and follow the emitted Pi supervision protocol.",
    );
  }

  function escalateStalledQueue(ctx: ExtensionContext): void {
    escalate(
      ctx,
      "Firstmate supervision stopped re-notifying because the same wake records survived a drain. " +
        "The durable queue is unchanged and still unhandled. Inspect `state/.wake-queue` and " +
        "`bin/fm-wake-drain.sh` before relying on monitoring again.",
    );
  }

  // Deliver the session-start digest into model context without starting a turn.
  // Pi documents a display:false custom message as LLM context, and starting a
  // turn from session_start races Pi's own positional prompt.
  function deliverSessionStartContext(content: string): void {
    try {
      pi.sendMessage({
        customType: "firstmate-sessionstart-nudge",
        content,
        display: false,
        details: { kind: "session-start" },
      });
    } catch {
    }
  }

  async function claimSession(nudge: string): Promise<void> {
    const result = await runSessionStart();
    if (!result.ok) {
      deliverSessionStartContext(
        `${nudge}\n\nThe Pi primary extension could not run it for you: ${result.failure}`,
      );
      return;
    }
    let digestContext: string;
    try {
      digestContext = encodeFirstmateOperationalInput(
        "session-start",
        "`bin/fm-session-start.sh` already ran exactly once for this Pi session, started by the Pi primary " +
          "extension before any answer could complete. Do not run it again. Treat the complete digest below as " +
          "this turn's startup and recovery input.\n\n" +
          result.digest,
      );
    } catch {
      // An unencodable digest still has to reach context, so fall back to the
      // marked advisory instruction rather than losing the whole startup input.
      deliverSessionStartContext(`${nudge}\n\nIt already ran; its digest could not be encoded for context.`);
      return;
    }
    deliverSessionStartContext(digestContext);
    // One initial supervision cycle, extension-owned, only when the shared
    // turn-end predicate says supervision is actually missing.
    const guard = await runGuard();
    if (guard.code !== 2) return;
    pi.events?.emit?.(FIRSTMATE_ARM_REQUEST_EVENT, { reason: "session-start" });
  }

  pi.on?.("session_start", async (event) => {
    const reason = String((event as { reason?: unknown }).reason ?? "");
    const nudge = ["startup", "new", "resume"].includes(reason) ? runSessionstartNudge() : "";
    markLoaded();
    if (!nudge) {
      if (sessionStartLifecycle) await sessionStartLifecycle;
      return;
    }
    if (!sessionStartAutorun) {
      deliverSessionStartContext(nudge);
      return;
    }
    // Exactly one lifecycle per Pi runtime: a second session_start in the same
    // process (a replacement or reload) never starts a second claim.
    if (!sessionStartLifecycle) {
      // Never let a claim failure become an unhandled rejection that could take
      // the whole Pi runtime down; a failed claim is reported, not fatal.
      sessionStartLifecycle = claimSession(nudge).catch(() => {});
    }
    await sessionStartLifecycle;
  });

  pi.on("tool_call", async (event) => {
    if (event.type !== "tool_call" || event.toolName !== "bash") return {};
    const command = String((event.input as { command?: unknown })?.command ?? "");
    if (!command) return {};
    const cdResult = await runCdCheck(command);
    if (cdResult.code === 2) {
      return { block: true, reason: cdResult.stderr.trim() || "denied by the cd-guard PreToolUse seatbelt" };
    }
    const result = await runPretoolCheck(command);
    if (result.code !== 2) return {};
    return { block: true, reason: result.stderr.trim() || "denied by the watcher-arm PreToolUse seatbelt" };
  });

  // Returns true when this settlement produced its own follow-up or escalation,
  // so the caller must not also force a turn-end guard continuation.
  async function handleOperationalSettlement(
    settlement: OperationalTurnSettlement,
    ctx: ExtensionContext,
  ): Promise<boolean> {
    const carried = settlement.deferred.length
      ? `${settlement.deferred.join("\n\n")}\n\n`
      : "";
    if (settlement.actionPerformed) {
      coordinator.resetAttempts();
      // The durable queue is the authority on outstanding wakes: coalesced
      // ordinary wakes are already handled by the drain this turn performed, and
      // only records enqueued afterwards need another turn.
      const fingerprint = coordinator.queueFingerprint();
      if (!carried && !fingerprint) {
        lastQueueFingerprint = "";
        return false;
      }
      // A drain that leaves the same records behind will never clear them, so
      // stop re-delivering rather than looping on an unchanging queue.
      if (fingerprint && fingerprint === lastQueueFingerprint) {
        lastQueueFingerprint = "";
        escalateStalledQueue(ctx);
        return true;
      }
      lastQueueFingerprint = fingerprint;
      return await deliverOperational(
        "watcher",
        "FIRSTMATE WATCHER WAKE: more supervision work arrived while the last operational turn ran.\n\n" +
          carried +
          "Run bin/fm-wake-drain.sh first and handle every queued wake. Watcher continuity is extension-owned.",
      );
    }
    const attempts = coordinator.bumpAttempts();
    if (attempts <= coordinator.retryLimit) {
      return await deliverOperational(
        "watcher",
        "FIRSTMATE OPERATIONAL DELIVERY NOT CARRIED OUT: the previous operational turn ran no wake drain, " +
          "session start, or watcher repair, and repeating the previous answer does not handle supervision.\n\n" +
          carried +
          "Run bin/fm-wake-drain.sh now, then follow the emitted Pi supervision protocol.",
      );
    }
    coordinator.resetAttempts();
    escalateFailedDelivery(ctx, attempts);
    return true;
  }

  pi.on("agent_settled", async (_event, ctx) => {
    // No captain-facing turn settles before this Pi runtime has claimed the
    // session, so the claim can never lose a race with the first answer.
    if (sessionStartLifecycle) await sessionStartLifecycle;

    if (coordinator.isActive()) {
      const settlement = coordinator.settle();
      if (await handleOperationalSettlement(settlement, ctx)) return;
      // One forced continuation per guard alarm stays the loop guard.
      if (settlement.kind === "turn-end-guard") return;
    }

    const result = await runGuard();
    if (result.code !== 2) return;
    await deliverOperational(
      "turn-end-guard",
      "TURN WOULD END BLIND - supervision is off. " +
        "The watcher cycle is missing, failed, or unhealthy. Follow the harness recovery instruction below before ending the turn.\n\n" +
        result.stderr,
    );
  });

  markLoaded();
}
