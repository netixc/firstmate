import {
  getMarkdownTheme,
  type ExtensionAPI,
  UserMessageComponent,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import {
  classifyFirstmateOperationalText,
  encodeFirstmateOperationalInput,
} from "./fm-operational-input.ts";

export { encodeFirstmateOperationalInput } from "./fm-operational-input.ts";

export const CALM_TRANSCRIPT_CLASSES = [
  "genuine-user-prompt",
  "genuine-agent-response",
  "assistant-thinking",
  "assistant-tool-call",
  "tool-result",
  "tool-image",
  "user-bash",
  "skill-invocation",
  "custom-message",
  "custom-entry",
  "compaction-summary",
  "branch-summary",
  "working-status",
  "command-status",
  "system-notice",
  "cache-notice",
  "project-trust-warning",
  "synthetic-user",
  "synthetic-assistant",
  "operational-boundary",
  "unknown",
] as const;

export type CalmTranscriptClass = (typeof CALM_TRANSCRIPT_CLASSES)[number];

// Calm hides the noisy operational payload but keeps its boundary. Without that
// boundary, a model turn started by a hidden operational input renders as a
// second consecutive assistant answer with no visible cause.
const CALM_VISIBLE_CLASSES = new Set<CalmTranscriptClass>([
  "genuine-user-prompt",
  "genuine-agent-response",
  "operational-boundary",
]);

export const FIRSTMATE_SYNTHETIC_CONTEXT_TYPE = "firstmate-synthetic-input";
export const FIRSTMATE_SYNTHETIC_PRESENTATION_TYPE = "firstmate-synthetic-input-presentation";
export const FIRSTMATE_OPERATIONAL_BOUNDARY_TYPE = "firstmate-operational-boundary";
export const FIRSTMATE_CALM_PRESENTATION_EVENT = "firstmate:calm-presentation";
export const FIRSTMATE_PI_LAUNCH_BRIEF_ENV = "FM_FIRSTMATE_PI_LAUNCH_BRIEF";

export type CalmPresentationState = {
  active: boolean;
  stockExportRendering: boolean;
};

export const FIRSTMATE_SYNTHETIC_KINDS = [
  "session-start",
  "watcher",
  "turn-end-guard",
  "away-supervisor",
  "from-firstmate",
  "launch-brief",
  "legacy-operational",
] as const;

export type FirstmateSyntheticKind = (typeof FIRSTMATE_SYNTHETIC_KINDS)[number];
export type FirstmateInputSource = "interactive" | "rpc" | "extension";

type SyntheticDeliveryOptions = {
  deliverAs?: "steer" | "followUp" | "nextTurn";
  redrawPresentation?: () => void;
  triggerTurn?: boolean;
};

type FirstmateSyntheticPresentation = {
  content: string;
  kind: FirstmateSyntheticKind;
};

type FirstmateOperationalBoundary = {
  kind: FirstmateSyntheticKind;
};

const OPERATIONAL_BOUNDARY_LABELS: Record<FirstmateSyntheticKind, string> = {
  "session-start": "session start",
  watcher: "watcher follow-up",
  "turn-end-guard": "supervision check",
  "away-supervisor": "away-mode escalation",
  "from-firstmate": "firstmate message",
  "launch-brief": "launch brief",
  "legacy-operational": "operational follow-up",
};

let calm = false;
let mountingSyntheticPresentation = false;
let stockExportRendering = false;

export function calmTranscriptClassIsVisible(itemClass: CalmTranscriptClass): boolean {
  return CALM_VISIBLE_CLASSES.has(itemClass);
}

export function setCalmPresentation(active: boolean): void {
  calm = active;
}

export function setCalmStockExportRendering(active: boolean): void {
  stockExportRendering = active;
}

export function calmPresentationIsActive(): boolean {
  return calm;
}

export function calmPresentationHides(itemClass: CalmTranscriptClass): boolean {
  return calm && !stockExportRendering && !calmTranscriptClassIsVisible(itemClass);
}

function isFirstmateSyntheticKind(value: string): value is FirstmateSyntheticKind {
  return (FIRSTMATE_SYNTHETIC_KINDS as readonly string[]).includes(value);
}

export function classifyFirstmateSyntheticInput(
  content: string,
  source: FirstmateInputSource,
  launchBriefContent?: string,
): FirstmateSyntheticKind | undefined {
  const classified = classifyFirstmateOperationalText(content);
  if (classified !== undefined && isFirstmateSyntheticKind(classified)) return classified;

  // Keep the exact per-process origin fallback only for positional launch
  // commands created before the typed protocol.
  if (
    source === "interactive" &&
    launchBriefContent !== undefined &&
    content === launchBriefContent
  ) {
    return "launch-brief";
  }
  return undefined;
}

export function registerFirstmateSyntheticPresentation(pi: ExtensionAPI): void {
  pi.registerEntryRenderer<FirstmateSyntheticPresentation>(
    FIRSTMATE_SYNTHETIC_PRESENTATION_TYPE,
    (entry) => {
      if (
        calmPresentationHides("synthetic-user") &&
        !mountingSyntheticPresentation
      ) {
        return undefined;
      }
      const data = entry.data;
      if (!data || typeof data.content !== "string") return undefined;
      return new UserMessageComponent(data.content, getMarkdownTheme());
    },
  );
}

export function registerFirstmateOperationalBoundary(pi: ExtensionAPI): void {
  pi.registerEntryRenderer<FirstmateOperationalBoundary>(
    FIRSTMATE_OPERATIONAL_BOUNDARY_TYPE,
    (entry) => {
      // Outside calm the full operational row is already on screen, so the
      // compact boundary would duplicate it.
      if (!calmPresentationHides("synthetic-user")) return undefined;
      const kind = entry.data?.kind;
      const label = (kind && OPERATIONAL_BOUNDARY_LABELS[kind]) || "operational follow-up";
      return new Text(`- firstmate ${label} -`, 0, 0);
    },
  );
}

export function deliverFirstmateSyntheticInput(
  pi: ExtensionAPI,
  content: string,
  kind: FirstmateSyntheticKind,
  options: SyntheticDeliveryOptions = {},
): void {
  const mountForRedraw =
    calmPresentationHides("synthetic-user") &&
    options.redrawPresentation !== undefined;
  mountingSyntheticPresentation = mountForRedraw;
  try {
    pi.appendEntry<FirstmateSyntheticPresentation>(FIRSTMATE_SYNTHETIC_PRESENTATION_TYPE, {
      content,
      kind,
    });
  } finally {
    mountingSyntheticPresentation = false;
  }
  // One visible row either way: calm hides the payload row above and shows this
  // compact boundary, plain presentation shows the payload and hides this.
  pi.appendEntry<FirstmateOperationalBoundary>(FIRSTMATE_OPERATIONAL_BOUNDARY_TYPE, { kind });
  if (mountForRedraw) options.redrawPresentation?.();
  pi.sendMessage(
    {
      customType: FIRSTMATE_SYNTHETIC_CONTEXT_TYPE,
      content,
      display: false,
      details: { kind },
    },
    options,
  );
}
