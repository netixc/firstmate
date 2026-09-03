# Firstmate test isolation proof

This record owns concurrent isolation evidence for the portable parallel candidate set and admitted runner families.
`bin/fm-test-isolation-proof.sh` is the authoritative harness and `docs/fm-test-isolation-proof.json` is the portable pool's machine-readable result.
`bin/fm-test-run.sh` owns production lane partitioning and family concurrency admission.

## Verification

- Date: 2026-09-03
- Command: `bin/fm-test-isolation-proof.sh --jobs 4 --json docs/fm-test-isolation-proof.json --markdown docs/fm-test-isolation-proof.md`
- Result: `FM_ISOLATION_SUMMARY total=21 failed=0 concurrency=4 duration_ms=245891`

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1788397878476-4830` |
| `started_at` | `2026-09-03T01:11:18Z` |
| `finished_at` | `2026-09-03T01:15:24Z` |
| concurrency | 4 |
| candidates | 21 |
| failed | 0 |
| wall duration | 245891 ms |

## Candidate set

- `tests/fm-arm-pretool-check.test.sh`
- `tests/fm-backend-herdr.test.sh`
- `tests/fm-brief.test.sh`
- `tests/fm-captain-hold-lifecycle.test.sh`
- `tests/fm-cd-pretool-check.test.sh`
- `tests/fm-composer-lib.test.sh`
- `tests/fm-crew-state.test.sh`
- `tests/fm-ensure-agents-md.test.sh`
- `tests/fm-herdr-lab.test.sh`
- `tests/fm-lint.test.sh`
- `tests/fm-pi-primary-types.test.sh`
- `tests/fm-pr-merge.test.sh`
- `tests/fm-review-diff.test.sh`
- `tests/fm-send-popup-settle.test.sh`
- `tests/fm-send-settle.test.sh`
- `tests/fm-send-strict.test.sh`
- `tests/fm-spawn-batch.test.sh`
- `tests/fm-supervision-instructions.test.sh`
- `tests/fm-test-run.test.sh`
- `tests/fm-transition-lib.test.sh`
- `tests/fm-x-mode.test.sh`

## Durations

| duration_ms | exit | worker | script |
|---:|---:|---:|---|
| 180017 | 0 | 12 | `tests/fm-pr-merge.test.sh` |
| 167188 | 0 | 4 | `tests/fm-captain-hold-lifecycle.test.sh` |
| 114779 | 0 | 19 | `tests/fm-test-run.test.sh` |
| 108167 | 0 | 2 | `tests/fm-backend-herdr.test.sh` |
| 94813 | 0 | 21 | `tests/fm-x-mode.test.sh` |
| 70615 | 0 | 7 | `tests/fm-crew-state.test.sh` |
| 27935 | 0 | 10 | `tests/fm-lint.test.sh` |
| 18612 | 0 | 9 | `tests/fm-herdr-lab.test.sh` |
| 14774 | 0 | 16 | `tests/fm-send-strict.test.sh` |
| 14580 | 0 | 17 | `tests/fm-spawn-batch.test.sh` |
| 13351 | 0 | 14 | `tests/fm-send-popup-settle.test.sh` |
| 11033 | 0 | 11 | `tests/fm-pi-primary-types.test.sh` |
| 9858 | 0 | 15 | `tests/fm-send-settle.test.sh` |
| 8404 | 0 | 13 | `tests/fm-review-diff.test.sh` |
| 4992 | 0 | 6 | `tests/fm-composer-lib.test.sh` |
| 4235 | 0 | 3 | `tests/fm-brief.test.sh` |
| 1517 | 0 | 8 | `tests/fm-ensure-agents-md.test.sh` |
| 485 | 0 | 18 | `tests/fm-supervision-instructions.test.sh` |
| 380 | 0 | 20 | `tests/fm-transition-lib.test.sh` |
| 203 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 173 | 0 | 5 | `tests/fm-cd-pretool-check.test.sh` |

## Family concurrency proofs

`bin/fm-test-isolation-proof.sh --pool <family>` runs the same concurrent proof over a whole `bin/fm-test-run.sh` family, for a stateful family that stays serial on CI but can earn bounded local concurrency.
A family is admitted to `list_concurrent_safe_families` in `bin/fm-test-run.sh` only by a passing proof recorded here.

### watcher-wake-lock: admitted

- Date: 2026-08-28
- Command: `bin/fm-test-isolation-proof.sh --pool watcher-wake-lock --jobs 4`
- Archived harness result: two consecutive runs, 18 candidates, 0 failures.

| Run | Summary |
|---|---|
| 1 | `FM_ISOLATION_SUMMARY total=18 failed=0 concurrency=4 duration_ms=394675` |
| 2 | `FM_ISOLATION_SUMMARY total=18 failed=0 concurrency=4 duration_ms=374869` |

Those archived harness runs used alphabetical launch order and oldest-worker reclamation.
They establish the worker isolation result, but they did not reproduce the production scheduler's load profile and are not the sole basis for admission.
The current harness consumes the runner's longest-hint-first schedule and reclaims any completed worker, matching the admitted execution condition.

Admission is also supported by three independent runs of the production scheduler using `bin/fm-test-run.sh --changed --base HEAD`.
Plain `--changed` automatically selected bounded concurrency at four workers; each run used longest-first scheduling, selected 19 scripts, completed with 0 failures, and finished in 208s, 216s, and 226s.
Those runs exercised the production path that the family admission enables.

These scripts assert how quickly a real watcher reaches its next poll, so they are sensitive to CPU oversubscription rather than to shared state.
An earlier attempt on the same host measured three failures (`fm-watch-checkpoint`, `fm-watch-recovery-loop`, `fm-watch-arm`) while six unrelated busy processes were running, at roughly ten runnable processes against fourteen cores.
That is the margin this family has: four workers is proven, and the failures reappear well before the machine is merely busy.
Keep `--jobs` for this family at or below the proven bound rather than raising it to fill a larger machine.

The archived harness runs showed why ordering matters: the candidate sum was 818s and the balanced four-worker target 205s, but alphabetical order finished in 395s because the 193s `fm-watch-triage` started last and ran alone at the tail.
Both `bin/fm-test-run.sh` and the current proof harness therefore order concurrent runs longest-hint-first.

### pure-contract-unit: admitted

- Date: 2026-08-28
- Command: `bin/fm-test-isolation-proof.sh --pool pure-contract-unit --jobs 4`
- Result: two consecutive runs, 32 candidates, 0 failures.

| Run | Summary |
|---|---|
| 1 | `FM_ISOLATION_SUMMARY total=32 failed=0 concurrency=4 duration_ms=161837` |
| 2 | `FM_ISOLATION_SUMMARY total=32 failed=0 concurrency=4 duration_ms=156462` |

This family is what a change to `bin/fm-test-run.sh` itself selects, so it decides that selection's wall clock.
Before admission, 14 of its scripts fell to the serial tail and the 33-script selection measured 327.3s against a 300s budget: the concurrent group was 19 scripts totalling 273.4s while the tail alone was 215.7s, dominated by `fm-calm-pi-extension` (77.5s).
Admitting the family moves that tail into the bounded concurrent group.
Current runner-file selection was verified on 2026-08-28 with the runner and its tests bound to each measured Bash version.
Because the runner uses `#!/usr/bin/env bash` and invokes each test with `bash` from `PATH`, the stock macOS measurement used `PATH=/bin:$PATH bin/fm-test-run.sh --changed --max-wall-ms 300000` so both resolved to `/bin/bash` 3.2.57.
With Bash 5.3.9 on `PATH`, three runs of `bin/fm-test-run.sh --changed --max-wall-ms 300000` selected the same 33 scripts, completed with 0 failures, and reported 163.8s, 172.0s, and 166.9s.
All five runs used plain `--changed` with no `--jobs` flag, exercised the production automatic scheduler, and completed under five minutes.

## Scope

Each worker used a separate mode-`0700` temporary root and private `TMPDIR` and `TMP`.
The harness cleared ambient `FM_HOME` and `FM_*_OVERRIDE` values for every worker and verified that global Git configuration was unchanged.
A candidate failure fails the aggregate run and requires investigation rather than a retry.

## Re-run

```sh
bin/fm-test-isolation-proof.sh --list
bin/fm-test-isolation-proof.sh --jobs 4 --json /tmp/fm-isolation-proof.json
bin/fm-test-run.sh --check-coverage
```

To re-run a family proof:

```sh
bin/fm-test-isolation-proof.sh --pool watcher-wake-lock --jobs 4
```
