# Firstmate test isolation proof

This record is the concurrent isolation proof for the portable parallel candidate set.
`bin/fm-test-isolation-proof.sh` is the authoritative harness and `docs/fm-test-isolation-proof.json` is the machine-readable result.
`bin/fm-test-run.sh` owns the production lane partition.

## Verification

- Date: 2026-08-06
- Command: `bin/fm-test-isolation-proof.sh --jobs 4 --json /tmp/fm-remove-backends-isolation.json`
- Result: `FM_ISOLATION_SUMMARY total=23 failed=0 concurrency=4 duration_ms=199971`

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1785982153528-55781` |
| `started_at` | `2026-08-06T02:09:13Z` |
| `finished_at` | `2026-08-06T02:12:33Z` |
| concurrency | 4 |
| candidates | 23 |
| failed | 0 |
| wall duration | 199971 ms |

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
- `tests/fm-grok-harness.test.sh`
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
| 74427 | 0 | 23 | `tests/fm-x-mode.test.sh` |
| 71456 | 0 | 2 | `tests/fm-backend-herdr.test.sh` |
| 52335 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 37959 | 0 | 8 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 37646 | 0 | 4 | `tests/fm-cd-pretool-check.test.sh` |
| 30731 | 0 | 7 | `tests/fm-crew-state.test.sh` |
| 29957 | 0 | 21 | `tests/fm-test-run.test.sh` |
| 13588 | 0 | 11 | `tests/fm-herdr-lab.test.sh` |
| 12903 | 0 | 14 | `tests/fm-pr-merge.test.sh` |
| 8589 | 0 | 10 | `tests/fm-grok-harness.test.sh` |
| 5960 | 0 | 12 | `tests/fm-lint.test.sh` |
| 5642 | 0 | 16 | `tests/fm-send-popup-settle.test.sh` |
| 5632 | 0 | 15 | `tests/fm-review-diff.test.sh` |
| 4119 | 0 | 17 | `tests/fm-send-settle.test.sh` |
| 2571 | 0 | 18 | `tests/fm-send-strict.test.sh` |
| 2355 | 0 | 3 | `tests/fm-brief.test.sh` |
| 1659 | 0 | 19 | `tests/fm-spawn-batch.test.sh` |
| 690 | 0 | 9 | `tests/fm-ensure-agents-md.test.sh` |
| 666 | 0 | 20 | `tests/fm-supervision-instructions.test.sh` |
| 188 | 0 | 22 | `tests/fm-transition-lib.test.sh` |
| 138 | 0 | 5 | `tests/fm-composer-ghost.test.sh` |
| 127 | 0 | 6 | `tests/fm-composer-lib.test.sh` |
| 50 | 0 | 13 | `tests/fm-pi-primary-types.test.sh` |

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
