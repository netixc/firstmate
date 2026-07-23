// Firstmate's single-flight coordinator for Pi operational follow-up turns.
//
// Every operational wake Firstmate delivers to a Pi primary - a watcher wake, a
// turn-end guard repair, a session-start digest - arrives as a queued follow-up,
// and Pi documents that each queued follow-up starts another agent turn. Without
// coordination, N wakes produce N turns, and a model that answers an operational
// turn by repeating its previous captain-facing final turns those extra turns
// into consecutive duplicate answers.
//
// This coordinator makes two guarantees:
//
//   1. Single flight. While one operational follow-up is queued or in progress,
//      further wakes coalesce instead of queueing another turn. The DURABLE wake
//      queue is never touched, so one operational turn may drain many records and
//      no signal, stale, check, heartbeat, or X-mode record is dropped. Only an
//      extension-generated message that the durable queue cannot carry (a typed
//      `watcher: FAILED` continuity report) is retained for re-delivery.
//   2. Action accounting. An operational turn that never runs the required
//      action - `bin/fm-wake-drain.sh`, `bin/fm-session-start.sh`, or the named
//      `fm_watch_arm_pi` repair - is a failed delivery, not a successful answer.
//      The settle owner retries a bounded number of times and then escalates
//      compactly instead of recursively generating more visible answers.
//
// Pi loads every extension through its own jiti instance with `moduleCache:
// false`, so two extensions importing this file get two module instances. State
// is therefore mirrored over the shared `pi.events` bus, which dispatches
// synchronously through a Node EventEmitter, so a claim taken in one extension
// is visible in the other before the claiming call returns.
//
// The latch is time-bounded (FM_PI_OPERATIONAL_LATCH_MAX_MS) so a Pi session
// that somehow loses its settle owner resumes delivering wakes instead of going
// permanently quiet.
import { readFileSync } from "node:fs";
import {
  getMarkdownTheme,
  type ExtensionAPI,
  UserMessageComponent,
} from "@earendil-works/pi-coding-agent";
import type { FirstmateCurrentOperationalKind } from "./fm-operational-input.ts";

export const FIRSTMATE_OPERATIONAL_TURN_EVENT = "firstmate:operational-turn";
export const FIRSTMATE_ARM_REQUEST_EVENT = "firstmate:arm-request";
export const FIRSTMATE_OPERATIONAL_ESCALATION_TYPE = "firstmate-operational-escalation";

export type OperationalTurnState = {
  active: boolean;
  kind: FirstmateCurrentOperationalKind;
  claimedAtMs: number;
  deferred: string[];
  attempts: number;
  actionPerformed: boolean;
};

export type OperationalTurnSettlement = {
  kind: FirstmateCurrentOperationalKind;
  deferred: string[];
  attempts: number;
  actionPerformed: boolean;
};

export type OperationalTurnCoordinator = {
  isActive(): boolean;
  claim(kind: FirstmateCurrentOperationalKind): boolean;
  defer(message: string): void;
  settle(): OperationalTurnSettlement;
  bumpAttempts(): number;
  resetAttempts(): void;
  queuePending(): boolean;
  queueFingerprint(): string;
  retryLimit: number;
};

const OPERATIONAL_ACTION_COMMANDS = new Set([
  "fm-wake-drain.sh",
  "fm-session-start.sh",
  "fm-watch-arm.sh",
]);
export const OPERATIONAL_ACTION_TOOL = "fm_watch_arm_pi";

function shellCommandSegments(command: string): string[][] {
  const segments: string[][] = [];
  let words: string[] = [];
  let word = "";
  let quote = "";
  let escaped = false;
  const finishWord = (): void => {
    if (!word) return;
    words.push(word);
    word = "";
  };
  const finishSegment = (): void => {
    finishWord();
    if (words.length) segments.push(words);
    words = [];
  };
  for (let index = 0; index < command.length; index += 1) {
    const character = command[index];
    if (escaped) {
      word += character;
      escaped = false;
      continue;
    }
    if (quote) {
      if (character === quote) {
        quote = "";
      } else if (character === "\\" && quote === "\"") {
        escaped = true;
      } else {
        word += character;
      }
      continue;
    }
    if (character === "'" || character === "\"") {
      quote = character;
      continue;
    }
    if (character === "\\") {
      escaped = true;
      continue;
    }
    if (character === "#" && !word) {
      while (index < command.length && command[index] !== "\n") index += 1;
      finishSegment();
      continue;
    }
    if (/\s/.test(character)) {
      finishWord();
      if (character === "\n") finishSegment();
      continue;
    }
    if (";&|()".includes(character)) {
      finishSegment();
      continue;
    }
    word += character;
  }
  finishSegment();
  return segments;
}

function commandBasename(command: string): string {
  return command.slice(command.lastIndexOf("/") + 1);
}

function segmentInvokesOperationalAction(words: string[]): boolean {
  let index = 0;
  while (index < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[index])) index += 1;
  while (["!", "if", "then", "elif", "else", "do", "while", "until", "command", "exec"].includes(words[index] ?? "")) {
    index += 1;
  }
  if (words[index] === "env") {
    index += 1;
    while (index < words.length && (/^-/.test(words[index]) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[index]))) {
      index += 1;
    }
  }
  const executable = commandBasename(words[index] ?? "");
  if (OPERATIONAL_ACTION_COMMANDS.has(executable)) return true;
  if (!["bash", "sh"].includes(executable)) return false;
  index += 1;
  while (index < words.length && /^-/.test(words[index])) index += 1;
  return OPERATIONAL_ACTION_COMMANDS.has(commandBasename(words[index] ?? ""));
}

export function commandInvokesOperationalAction(command: string): boolean {
  return shellCommandSegments(command).some(segmentInvokesOperationalAction);
}

function positiveInteger(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  if (!Number.isFinite(value) || value <= 0) return fallback;
  return Math.floor(value);
}

function nonNegativeInteger(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  if (!Number.isFinite(value) || value < 0) return fallback;
  return Math.floor(value);
}

export type FirstmateOperationalEscalation = {
  message: string;
};

/**
 * Register the compact escalation row.
 *
 * An escalation reports that repeated operational deliveries did not produce the
 * required action, so it stays visible in every presentation mode; calm hides
 * noisy operational payloads, never the reason supervision stopped retrying.
 */
export function registerOperationalEscalationPresentation(pi: ExtensionAPI): void {
  pi.registerEntryRenderer<FirstmateOperationalEscalation>(
    FIRSTMATE_OPERATIONAL_ESCALATION_TYPE,
    (entry) => {
      const data = entry.data;
      if (!data || typeof data.message !== "string") return undefined;
      return new UserMessageComponent(data.message, getMarkdownTheme());
    },
  );
}

/** True when the message carries extension-only text the durable queue cannot replay. */
export function operationalMessageMustSurvive(message: string): boolean {
  return /watcher: FAILED/.test(message);
}

/**
 * Install the coordinator for one extension instance.
 *
 * `stateDir` is the effective firstmate state directory, used only to read the
 * durable wake queue; the coordinator never writes fleet state.
 */
export function installOperationalTurnCoordinator(
  pi: ExtensionAPI,
  stateDir: string,
): OperationalTurnCoordinator {
  const latchMaxMs = positiveInteger("FM_PI_OPERATIONAL_LATCH_MAX_MS", 300000);
  const retryLimit = nonNegativeInteger("FM_PI_OPERATIONAL_RETRY_LIMIT", 1);
  let state: OperationalTurnState = {
    active: false,
    kind: "watcher",
    claimedAtMs: 0,
    deferred: [],
    attempts: 0,
    actionPerformed: false,
  };

  const publish = (): void => {
    pi.events?.emit?.(FIRSTMATE_OPERATIONAL_TURN_EVENT, { ...state, deferred: [...state.deferred] });
  };

  pi.events?.on?.(FIRSTMATE_OPERATIONAL_TURN_EVENT, (data) => {
    const next = data as Partial<OperationalTurnState>;
    state = {
      active: next.active === true,
      kind: (next.kind ?? state.kind) as FirstmateCurrentOperationalKind,
      claimedAtMs: typeof next.claimedAtMs === "number" ? next.claimedAtMs : 0,
      deferred: Array.isArray(next.deferred) ? [...next.deferred] : [],
      attempts: typeof next.attempts === "number" ? next.attempts : 0,
      actionPerformed: next.actionPerformed === true,
    };
  });

  pi.on("tool_result", (event) => {
    if (!state.active || state.actionPerformed) return;
    if (event.isError) return;
    if (event.toolName === OPERATIONAL_ACTION_TOOL) {
      state.actionPerformed = true;
      publish();
      return;
    }
    if (event.toolName !== "bash") return;
    const command = String((event.input as { command?: unknown })?.command ?? "");
    if (!commandInvokesOperationalAction(command)) return;
    state.actionPerformed = true;
    publish();
  });

  return {
    retryLimit,
    isActive(): boolean {
      return state.active;
    },
    claim(kind: FirstmateCurrentOperationalKind): boolean {
      if (state.active && Date.now() - state.claimedAtMs < latchMaxMs) return false;
      state = {
        ...state,
        active: true,
        kind,
        claimedAtMs: Date.now(),
        actionPerformed: false,
      };
      publish();
      return true;
    },
    defer(message: string): void {
      if (!message || state.deferred.includes(message)) return;
      state = { ...state, deferred: [...state.deferred, message] };
      publish();
    },
    settle(): OperationalTurnSettlement {
      const settlement: OperationalTurnSettlement = {
        kind: state.kind,
        deferred: [...state.deferred],
        attempts: state.attempts,
        actionPerformed: state.actionPerformed,
      };
      state = { ...state, active: false, deferred: [], actionPerformed: false };
      publish();
      return settlement;
    },
    bumpAttempts(): number {
      state = { ...state, attempts: state.attempts + 1 };
      publish();
      return state.attempts;
    },
    resetAttempts(): void {
      state = { ...state, attempts: 0 };
      publish();
    },
    queuePending(): boolean {
      return this.queueFingerprint() !== "";
    },
    // Identity of the currently queued records, so the settle owner can tell a
    // genuinely new wake from a drain that is not consuming what is already
    // there. Empty string means nothing is queued.
    queueFingerprint(): string {
      let contents: string;
      try {
        contents = readFileSync(`${stateDir}/.wake-queue`, "utf8");
      } catch {
        return "";
      }
      if (!/\S/.test(contents)) return "";
      const lines = contents.split("\n").filter((line) => line.trim());
      return `${lines.length}:${lines[0]}:${lines[lines.length - 1]}`;
    },
  };
}
