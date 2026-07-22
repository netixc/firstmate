# Firstmate test isolation proof (Phase 2)

This document is the archived concurrent isolation proof for the portable parallel candidate set.
It is the human-readable companion to `bin/fm-test-isolation-proof.sh`.
Phase 4 production portable shards and bounded local `fm-test-run.sh --jobs` for this exact set are owned by `bin/fm-test-run.sh` and documented in [fm-test-portable-shards.md](fm-test-portable-shards.md).
The archived proof JSON below still records the Phase 2 proof-time flags (`production_sharding_enabled` / `fm_test_run_jobs_enabled` false at proof time).

## Owner

- Harness: `bin/fm-test-isolation-proof.sh`
- Contract tests: `tests/fm-test-isolation-proof.test.sh`
- Family labels (Phase 1): `bin/fm-test-run.sh`
- Timing evidence used for planning: CI artifact `fm-test-timing` from Phase 1 PR #825

## Proof posture

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1784734118014-985459` |
| `started_at` | `2026-07-22T15:28:38Z` |
| `finished_at` | `2026-07-22T15:31:43Z` |
| concurrency | **4** |
| candidates | **29** |
| failed | **0** |
| wall duration_ms | **185908** (~185.9s) |
| `production_sharding_enabled` | `False` |
| `fm_test_run_jobs_enabled` | `False` |
| host proof date | 2026-07-22 (UTC day of archive write) |

Isolation checks that passed with this run:

- Distinct mode-`0700` temporary roots per worker under a proof-owned parent
- Per-worker `TMPDIR`/`TMP` so `mktemp` / `fm_test_tmproot` stay private
- Ambient `FM_HOME` / `FM_*_OVERRIDE` cleared for each worker
- `git config --global` snapshot unchanged before/after the matrix
- Aggregate failure reporting (any non-zero candidate fails the harness; no retry-until-green)

## Exact candidate set

Sorted paths as selected by `bin/fm-test-isolation-proof.sh --list` at proof time:

- `tests/fm-arm-pretool-check.test.sh`
- `tests/fm-backend-herdr.test.sh`
- `tests/fm-brief.test.sh`
- `tests/fm-captain-translation-contract.test.sh`
- `tests/fm-cd-pretool-check.test.sh`
- `tests/fm-composer-ghost.test.sh`
- `tests/fm-composer-lib.test.sh`
- `tests/fm-crew-state.test.sh`
- `tests/fm-decision-hold-lifecycle.test.sh`
- `tests/fm-dispatch-select.test.sh`
- `tests/fm-ensure-agents-md.test.sh`
- `tests/fm-grok-harness.test.sh`
- `tests/fm-herdr-lab.test.sh`
- `tests/fm-instruction-owners.test.sh`
- `tests/fm-lint.test.sh`
- `tests/fm-nm-test-contract.test.sh`
- `tests/fm-no-mistakes-ownership.test.sh`
- `tests/fm-pi-primary-types.test.sh`
- `tests/fm-pr-merge.test.sh`
- `tests/fm-review-diff.test.sh`
- `tests/fm-send-popup-settle.test.sh`
- `tests/fm-send-settle.test.sh`
- `tests/fm-send-strict.test.sh`
- `tests/fm-spawn-batch.test.sh`
- `tests/fm-stow-contract.test.sh`
- `tests/fm-supervision-instructions.test.sh`
- `tests/fm-test-run.test.sh`
- `tests/fm-transition-lib.test.sh`
- `tests/fm-x-mode.test.sh`

## Per-candidate durations (concurrent run)

| duration_ms | exit | worker | script |
|---:|---:|---:|---|
| 84432 | 0 | 9 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 40523 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 26807 | 0 | 29 | `tests/fm-x-mode.test.sh` |
| 20588 | 0 | 5 | `tests/fm-cd-pretool-check.test.sh` |
| 11267 | 0 | 2 | `tests/fm-backend-herdr.test.sh` |
| 7329 | 0 | 27 | `tests/fm-test-run.test.sh` |
| 7011 | 0 | 13 | `tests/fm-herdr-lab.test.sh` |
| 6315 | 0 | 8 | `tests/fm-crew-state.test.sh` |
| 4695 | 0 | 19 | `tests/fm-pr-merge.test.sh` |
| 4318 | 0 | 12 | `tests/fm-grok-harness.test.sh` |
| 2548 | 0 | 21 | `tests/fm-send-popup-settle.test.sh` |
| 1427 | 0 | 24 | `tests/fm-spawn-batch.test.sh` |
| 1164 | 0 | 23 | `tests/fm-send-strict.test.sh` |
| 1036 | 0 | 20 | `tests/fm-review-diff.test.sh` |
| 678 | 0 | 3 | `tests/fm-brief.test.sh` |
| 556 | 0 | 22 | `tests/fm-send-settle.test.sh` |
| 379 | 0 | 10 | `tests/fm-dispatch-select.test.sh` |
| 248 | 0 | 11 | `tests/fm-ensure-agents-md.test.sh` |
| 233 | 0 | 26 | `tests/fm-supervision-instructions.test.sh` |
| 164 | 0 | 14 | `tests/fm-instruction-owners.test.sh` |
| 137 | 0 | 16 | `tests/fm-nm-test-contract.test.sh` |
| 82 | 0 | 28 | `tests/fm-transition-lib.test.sh` |
| 73 | 0 | 15 | `tests/fm-lint.test.sh` |
| 71 | 0 | 6 | `tests/fm-composer-ghost.test.sh` |
| 67 | 0 | 4 | `tests/fm-captain-translation-contract.test.sh` |
| 61 | 0 | 7 | `tests/fm-composer-lib.test.sh` |
| 44 | 0 | 25 | `tests/fm-stow-contract.test.sh` |
| 27 | 0 | 17 | `tests/fm-no-mistakes-ownership.test.sh` |
| 22 | 0 | 18 | `tests/fm-pi-primary-types.test.sh` |

## Audit notes (why this set)

Source families from the Phase 1 manifest and scout report §3.1:

1. **pure-contract-unit** candidates audited from the Phase 1 family manifest, minus deliberate serial exclusions
2. **Extra hermetic candidates** after static audit: fake Herdr endpoints, private git fixtures, stubbed network

The harness pins this exact archived set and does not automatically admit later family additions.
A candidate-set change requires a new audit and concurrent proof archive.

### Included extras (beyond pure-contract-unit)

| Script | Why included |
|---|---|
| `tests/fm-backend-herdr.test.sh` | Fake Herdr CLI + private temps; no real Herdr binary |
| `tests/fm-send-strict.test.sh` | Fake Herdr PATH shim; private `FM_HOME` |
| `tests/fm-spawn-batch.test.sh` | Argument routing only; no real windows/worktrees |
| `tests/fm-pr-merge.test.sh` | Fake `gh`/`gh-axi`; private state |
| `tests/fm-review-diff.test.sh` | Local git fixtures via `fm_git_*`; no live forge |
| `tests/fm-x-mode.test.sh` | Fake `curl`; inert without token |

### Deliberately serial (kept out of this pool)

Run `bin/fm-test-isolation-proof.sh --list-exclusions` for the machine-readable list.
High-signal classes:

| Class | Examples | Reason |
|---|---|---|
| Process-holder pure unit | `fm-continuity-pretool-check` | Background `sleep 300` lock-holder process |
| Watcher / wake / locks | `fm-watcher-lock`, `fm-wake-queue`, ... | Intentional process locks and daemon races |
| AFK | `fm-afk-inject-herdr-e2e`, ... | Daemon lifecycle and inject path |
| Real Herdr | `fm-backend-herdr-smoke`, presentation e2e, ... | Named labs, session-global locks; Herdr lane is Phase 3+ |
| Live harness opt-in | `fm-*-live-e2e` | Real interactive agents |
| Gray-zone git/spawn | `fm-backend`, spawn settle/profile, teardown | Heavier worktree or lock-race matrices |
| Watcher-adjacent forge security | `fm-pr-check-security` | `.watch.lock` / poll security surface |
| Self | `fm-test-isolation-proof.test.sh` | Must not re-enter the concurrent matrix |

### Small isolation fix landed with this phase

`tests/fm-arm-pretool-check.test.sh` no longer writes Claude deny stderr to a fixed `/tmp/fm-arm-pretool-check-claude-stderr.$$` path.
It uses `mktemp` under `TMPDIR` so concurrent workers cannot collide on a global temp name pattern.

## Failures

None.
Every candidate exited 0 under concurrency=4.

Policy: a script that fails only under concurrency is **removed** from the candidate set and investigated.
It is never retried into green, skipped more broadly, or weakened in assertions.

## What this phase did not do (Phase 2 scope)

- Did not land production CI Behavior matrix / shard jobs (Phase 4)
- Did not add general `bin/fm-test-run.sh --jobs` (Phase 4 enables it only for this proven set)
- Did not land the Herdr install lane (Phase 3)
- Did not re-run the complete local suite as part of this proof (focused matrix only)

## How to re-run

```sh
bin/fm-test-isolation-proof.sh --list
bin/fm-test-isolation-proof.sh --jobs 4 --json /tmp/fm-isolation-proof.json
bash tests/fm-test-isolation-proof.test.sh
```
