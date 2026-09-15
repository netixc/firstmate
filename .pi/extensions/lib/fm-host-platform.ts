import { spawnSync } from "node:child_process";

export type FirstmateHostPreflight = {
  supported: boolean;
  diagnostic: string;
};

type HostPreflightGlobal = typeof globalThis & {
  __firstmateHostPreflightReports?: Set<string>;
};

export function firstmateHostPreflight(root: string): FirstmateHostPreflight {
  const script = `${root}/bin/fm-host-platform-lib.sh`;
  try {
    const result = spawnSync("bash", [script], {
      encoding: "utf8",
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    if (result.status === 0) return { supported: true, diagnostic: "" };
    const output = `${result.stderr || ""}${result.stdout || ""}`.trim();
    const detail = output || result.error?.message || `exit status ${result.status ?? "unknown"}`;
    return {
      supported: false,
      diagnostic: output || `Firstmate host preflight failed closed: ${script}: ${detail}`,
    };
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return {
      supported: false,
      diagnostic: `Firstmate host preflight failed closed: ${script}: ${detail}`,
    };
  }
}

export function reportFirstmateHostRefusal(result: FirstmateHostPreflight): void {
  if (result.supported || !result.diagnostic) return;
  const shared = globalThis as HostPreflightGlobal;
  const reports = shared.__firstmateHostPreflightReports ??= new Set<string>();
  if (reports.has(result.diagnostic)) return;
  reports.add(result.diagnostic);
  console.error(result.diagnostic);
}
