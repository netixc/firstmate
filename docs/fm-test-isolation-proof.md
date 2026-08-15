# Firstmate test isolation proof

This record is the concurrent isolation proof for the portable parallel candidate set.
`bin/fm-test-isolation-proof.sh` is the authoritative harness and `docs/fm-test-isolation-proof.json` is the machine-readable result.
`bin/fm-test-run.sh` owns the production lane partition.

## Verification

- Date: 2026-08-15
- Command: `bin/fm-test-isolation-proof.sh --jobs 4 --json docs/fm-test-isolation-proof.json`
- Result: `FM_ISOLATION_SUMMARY total=23 failed=0 concurrency=4 duration_ms=215276`

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1786834685938-34236` |
| `started_at` | `2026-08-15T22:58:05Z` |
| `finished_at` | `2026-08-15T23:01:41Z` |
| concurrency | 4 |
| candidates | 23 |
| failed | 0 |
| wall duration | 215276 ms |

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
- `tests/fm-herdr-lab.test.sh`
- `tests/fm-lint.test.sh`
- `tests/fm-pi-primary-types.test.sh`
- `tests/fm-pr-merge.test.sh`
- `tests/fm-relay.test.sh`
- `tests/fm-review-diff.test.sh`
- `tests/fm-send-popup-settle.test.sh`
- `tests/fm-send-settle.test.sh`
- `tests/fm-send-strict.test.sh`
- `tests/fm-spawn-batch.test.sh`
- `tests/fm-supervision-instructions.test.sh`
- `tests/fm-test-run.test.sh`
- `tests/fm-tmux-submit-busy.test.sh`
- `tests/fm-transition-lib.test.sh`

## Durations

| duration_ms | exit | worker | script |
|---:|---:|---:|---|
| 66001 | 0 | 2 | `tests/fm-backend-herdr.test.sh` |
| 64743 | 0 | 8 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 56480 | 0 | 14 | `tests/fm-relay.test.sh` |
| 34918 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 29962 | 0 | 7 | `tests/fm-crew-state.test.sh` |
| 28744 | 0 | 4 | `tests/fm-cd-pretool-check.test.sh` |
| 27546 | 0 | 21 | `tests/fm-test-run.test.sh` |
| 13522 | 0 | 10 | `tests/fm-herdr-lab.test.sh` |
| 13423 | 0 | 13 | `tests/fm-pr-merge.test.sh` |
| 9678 | 0 | 16 | `tests/fm-send-popup-settle.test.sh` |
| 8561 | 0 | 5 | `tests/fm-composer-ghost.test.sh` |
| 7739 | 0 | 15 | `tests/fm-review-diff.test.sh` |
| 7577 | 0 | 11 | `tests/fm-lint.test.sh` |
| 4187 | 0 | 22 | `tests/fm-tmux-submit-busy.test.sh` |
| 3654 | 0 | 18 | `tests/fm-send-strict.test.sh` |
| 3203 | 0 | 6 | `tests/fm-composer-lib.test.sh` |
| 2543 | 0 | 17 | `tests/fm-send-settle.test.sh` |
| 2115 | 0 | 3 | `tests/fm-brief.test.sh` |
| 1862 | 0 | 19 | `tests/fm-spawn-batch.test.sh` |
| 534 | 0 | 9 | `tests/fm-ensure-agents-md.test.sh` |
| 292 | 0 | 20 | `tests/fm-supervision-instructions.test.sh` |
| 133 | 0 | 23 | `tests/fm-transition-lib.test.sh` |
| 28 | 0 | 12 | `tests/fm-pi-primary-types.test.sh` |

## Scope

Each worker used a separate mode-`0700` temporary root and private `TMPDIR` and `TMP`.
The harness cleared ambient `FM_HOME` and `FM_*_OVERRIDE` values for every worker and verified that global Git configuration was unchanged.
A candidate failure fails the aggregate run and requires investigation rather than a retry.

## Re-run

```sh
bin/fm-test-isolation-proof.sh --list
bin/fm-test-isolation-proof.sh --jobs 4 --json docs/fm-test-isolation-proof.json
bin/fm-test-run.sh --check-coverage
```
