# Firstmate test isolation proof

This record is the concurrent isolation proof for the portable parallel candidate set.
`bin/fm-test-isolation-proof.sh` is the authoritative harness and `docs/fm-test-isolation-proof.json` is the machine-readable result.
`bin/fm-test-run.sh` owns the production lane partition.

## Verification

- Date: 2026-08-08
- Command: `bin/fm-test-isolation-proof.sh --jobs 4 --json /tmp/fm-pi-only-runtime-isolation.json`
- Result: `FM_ISOLATION_SUMMARY total=23 failed=0 concurrency=4 duration_ms=105857`

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1786185763768-7846` |
| `started_at` | `2026-08-08T10:42:43Z` |
| `finished_at` | `2026-08-08T10:44:29Z` |
| concurrency | 4 |
| candidates | 23 |
| failed | 0 |
| wall duration | 105857 ms |

## Candidate set

- `tests/fm-arm-pretool-check.test.sh`
- `tests/fm-backend-herdr.test.sh`
- `tests/fm-brief.test.sh`
- `tests/fm-cd-pretool-check.test.sh`
- `tests/fm-composer-ghost.test.sh`
- `tests/fm-composer-lib.test.sh`
- `tests/fm-crew-state.test.sh`
- `tests/fm-decision-hold-lifecycle.test.sh`
- `tests/fm-ensure-agents-md.test.sh`
- `tests/fm-harness-pi.test.sh`
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
| 50185 | 0 | 23 | `tests/fm-x-mode.test.sh` |
| 27513 | 0 | 8 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 25817 | 0 | 21 | `tests/fm-test-run.test.sh` |
| 20066 | 0 | 2 | `tests/fm-backend-herdr.test.sh` |
| 12655 | 0 | 7 | `tests/fm-crew-state.test.sh` |
| 10364 | 0 | 11 | `tests/fm-herdr-lab.test.sh` |
| 5832 | 0 | 14 | `tests/fm-pr-merge.test.sh` |
| 5317 | 0 | 15 | `tests/fm-review-diff.test.sh` |
| 2313 | 0 | 12 | `tests/fm-lint.test.sh` |
| 1771 | 0 | 18 | `tests/fm-send-strict.test.sh` |
| 1497 | 0 | 3 | `tests/fm-brief.test.sh` |
| 1409 | 0 | 17 | `tests/fm-send-settle.test.sh` |
| 1196 | 0 | 19 | `tests/fm-spawn-batch.test.sh` |
| 1039 | 0 | 16 | `tests/fm-send-popup-settle.test.sh` |
| 525 | 0 | 4 | `tests/fm-cd-pretool-check.test.sh` |
| 403 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 267 | 0 | 10 | `tests/fm-harness-pi.test.sh` |
| 170 | 0 | 9 | `tests/fm-ensure-agents-md.test.sh` |
| 155 | 0 | 20 | `tests/fm-supervision-instructions.test.sh` |
| 155 | 0 | 22 | `tests/fm-transition-lib.test.sh` |
| 88 | 0 | 5 | `tests/fm-composer-ghost.test.sh` |
| 85 | 0 | 6 | `tests/fm-composer-lib.test.sh` |
| 34 | 0 | 13 | `tests/fm-pi-primary-types.test.sh` |

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
