# Firstmate test isolation proof

This record is the concurrent isolation proof for the portable parallel candidate set.
`bin/fm-test-isolation-proof.sh` is the authoritative harness and `docs/fm-test-isolation-proof.json` is the machine-readable result.
`bin/fm-test-run.sh` owns the production lane partition.

## Verification

- Date: 2026-08-16
- Command: `bin/fm-test-isolation-proof.sh --jobs 4 --json docs/fm-test-isolation-proof.json`
- Result: `FM_ISOLATION_SUMMARY total=23 failed=0 concurrency=4 duration_ms=174865`

| Field | Value |
|---|---|
| `run_id` | `fm-isolation-1786863535042-7173` |
| `started_at` | `2026-08-16T06:58:55Z` |
| `finished_at` | `2026-08-16T07:01:49Z` |
| concurrency | 4 |
| candidates | 23 |
| failed | 0 |
| wall duration | 174865 ms |

## Candidate set

- `tests/fm-arm-pretool-check.test.sh`
- `tests/fm-herdr.test.sh`
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
- `tests/fm-herdr-transition.test.sh`

## Durations

| duration_ms | exit | worker | script |
|---:|---:|---:|---|
| 53498 | 0 | 2 | `tests/fm-herdr.test.sh` |
| 48401 | 0 | 14 | `tests/fm-relay.test.sh` |
| 44466 | 0 | 8 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 28028 | 0 | 21 | `tests/fm-test-run.test.sh` |
| 22558 | 0 | 7 | `tests/fm-crew-state.test.sh` |
| 10034 | 0 | 10 | `tests/fm-herdr-lab.test.sh` |
| 8960 | 0 | 13 | `tests/fm-pr-merge.test.sh` |
| 7930 | 0 | 1 | `tests/fm-arm-pretool-check.test.sh` |
| 7905 | 0 | 4 | `tests/fm-cd-pretool-check.test.sh` |
| 7629 | 0 | 19 | `tests/fm-spawn-batch.test.sh` |
| 5551 | 0 | 11 | `tests/fm-lint.test.sh` |
| 5214 | 0 | 5 | `tests/fm-composer-ghost.test.sh` |
| 5003 | 0 | 15 | `tests/fm-review-diff.test.sh` |
| 4536 | 0 | 16 | `tests/fm-send-popup-settle.test.sh` |
| 3393 | 0 | 18 | `tests/fm-send-strict.test.sh` |
| 2111 | 0 | 17 | `tests/fm-send-settle.test.sh` |
| 1598 | 0 | 3 | `tests/fm-brief.test.sh` |
| 1026 | 0 | 6 | `tests/fm-composer-lib.test.sh` |
| 314 | 0 | 9 | `tests/fm-ensure-agents-md.test.sh` |
| 245 | 0 | 20 | `tests/fm-supervision-instructions.test.sh` |
| 128 | 0 | 23 | `tests/fm-herdr-transition.test.sh` |
| 27 | 0 | 12 | `tests/fm-pi-primary-types.test.sh` |

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
