# Firstmate test isolation proof

This record is the concurrent isolation proof for the portable parallel candidate set.
`bin/fm-test-isolation-proof.sh` is the authoritative harness and `docs/fm-test-isolation-proof.json` is the machine-readable result.
`bin/fm-test-run.sh` owns the production lane partition.

## Verification

- Date: 2026-08-16
- Command: `bin/fm-test-isolation-proof.sh --jobs 4 --json docs/fm-test-isolation-proof.json`
- Result: `FM_ISOLATION_SUMMARY total=23 failed=0 concurrency=4 duration_ms=251408`

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1786842975864-88248` |
| `started_at` | `2026-08-16T01:16:15Z` |
| `finished_at` | `2026-08-16T01:20:27Z` |
| concurrency | 4 |
| candidates | 23 |
| failed | 0 |
| wall duration | 251408 ms |

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
| 67643 | 0 | 14 | `tests/fm-relay.test.sh` |
| 61341 | 0 | 2 | `tests/fm-backend-herdr.test.sh` |
| 60961 | 0 | 8 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 60685 | 0 | 21 | `tests/fm-test-run.test.sh` |
| 31997 | 0 | 7 | `tests/fm-crew-state.test.sh` |
| 20653 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 19247 | 0 | 19 | `tests/fm-spawn-batch.test.sh` |
| 17302 | 0 | 4 | `tests/fm-cd-pretool-check.test.sh` |
| 16582 | 0 | 13 | `tests/fm-pr-merge.test.sh` |
| 13032 | 0 | 10 | `tests/fm-herdr-lab.test.sh` |
| 12482 | 0 | 16 | `tests/fm-send-popup-settle.test.sh` |
| 10295 | 0 | 15 | `tests/fm-review-diff.test.sh` |
| 9029 | 0 | 5 | `tests/fm-composer-ghost.test.sh` |
| 8544 | 0 | 22 | `tests/fm-tmux-submit-busy.test.sh` |
| 8258 | 0 | 18 | `tests/fm-send-strict.test.sh` |
| 6390 | 0 | 11 | `tests/fm-lint.test.sh` |
| 3580 | 0 | 6 | `tests/fm-composer-lib.test.sh` |
| 3239 | 0 | 17 | `tests/fm-send-settle.test.sh` |
| 2014 | 0 | 3 | `tests/fm-brief.test.sh` |
| 750 | 0 | 20 | `tests/fm-supervision-instructions.test.sh` |
| 432 | 0 | 9 | `tests/fm-ensure-agents-md.test.sh` |
| 261 | 0 | 23 | `tests/fm-transition-lib.test.sh` |
| 38 | 0 | 12 | `tests/fm-pi-primary-types.test.sh` |

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
