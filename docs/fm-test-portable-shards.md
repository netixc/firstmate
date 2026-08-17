# Firstmate portable test shards

`bin/fm-test-run.sh` owns portable lane composition and execution.
`bin/fm-test-isolation-proof.sh` owns the proven-isolated candidate set.

## Verification inputs

The current candidate timings came from the 2026-08-16 concurrent proof recorded in [fm-test-isolation-proof.md](fm-test-isolation-proof.md).
The proof ran 23 candidates with 4 workers and no failures.

| duration_ms | script |
|---:|---|
| 67643 | `tests/fm-relay.test.sh` |
| 61341 | `tests/fm-backend-herdr.test.sh` |
| 60961 | `tests/fm-decision-hold-lifecycle.test.sh` |
| 60685 | `tests/fm-test-run.test.sh` |
| 31997 | `tests/fm-crew-state.test.sh` |
| 20653 | `tests/fm-arm-pretool-check.test.sh` |
| 19247 | `tests/fm-spawn-batch.test.sh` |
| 17302 | `tests/fm-cd-pretool-check.test.sh` |
| 16582 | `tests/fm-pr-merge.test.sh` |
| 13032 | `tests/fm-herdr-lab.test.sh` |
| 12482 | `tests/fm-send-popup-settle.test.sh` |
| 10295 | `tests/fm-review-diff.test.sh` |
| 9029 | `tests/fm-composer-ghost.test.sh` |
| 8544 | `tests/fm-tmux-submit-busy.test.sh` |
| 8258 | `tests/fm-send-strict.test.sh` |
| 6390 | `tests/fm-lint.test.sh` |
| 3580 | `tests/fm-composer-lib.test.sh` |
| 3239 | `tests/fm-send-settle.test.sh` |
| 2014 | `tests/fm-brief.test.sh` |
| 750 | `tests/fm-supervision-instructions.test.sh` |
| 432 | `tests/fm-ensure-agents-md.test.sh` |
| 261 | `tests/fm-transition-lib.test.sh` |
| 38 | `tests/fm-pi-primary-types.test.sh` |


## Parallel lanes

The two parallel lanes use longest-processing-time assignment from those measured durations.

| Lane | Script count | Estimated duration |
|---|---:|---:|
| `portable-parallel-1` | 13 | 228151 ms (~228.2 s) |
| `portable-parallel-2` | 10 | 206604 ms (~206.6 s) |
| imbalance | | 21547 ms |

`bin/fm-test-run.sh` contains the exact ordered memberships in `list_portable_parallel_1` and `list_portable_parallel_2`.

## Portable serial remainder

`portable-serial` includes every `tests/*.test.sh` that is neither proven-isolated nor `real-herdr-gated`.
It keeps watcher, lock, AFK, real tmux, daemon, secondmate lifecycle, bootstrap, live-harness opt-in, GUI-backend, and other unproven work serial.
Membership is derived rather than enumerated, so a newly added test lands here by default.

## Portable serial CI shards

On green CI run [30725985757](https://github.com/kunchenguid/firstmate/actions/runs/30725985757), that remainder accumulated 19m04s of script time against a 20-minute job timeout.
On [PR 1495](https://github.com/kunchenguid/firstmate/pull/1495), its main step ran about 19m51s before the job was cancelled at that boundary.
`portable-serial-<k>of<n>` splits it across `n` separate CI runners.
Each shard is still strictly serial in itself, and separate runners mean no two of these stateful scripts ever share a machine, so the split needs no concurrency isolation proof.

`bin/fm-test-run.sh` owns `n` and refuses any lane whose `of<n>` disagrees with it.
`.github/workflows/ci.yml` derives the same `n` from `strategy.job-total` rather than a literal, so changing the shard count in either file without the other fails the lane loudly instead of leaving part of the required suite unrun.

Assignment is longest-processing-time bin packing over per-script duration hints embedded in `bin/fm-test-run.sh`.
The unchanged hints came from that run's `fm-test-timing-portable-serial` artifact on 2026-08-02.
The changed security script was remeasured in the final changed-selection run on 2026-08-16 and completed in 269158 ms with all cases passing.
The current inventory contains 89 portable-serial scripts with 1407856 ms of estimated work after that measured refresh.
A script with no hint gets the conservative `PORTABLE_SERIAL_DEFAULT_WEIGHT_MS` default.
Hints only affect balance: the coverage guard keeps the partition complete and disjoint whatever they say, so a stale hint costs a slower shard rather than lost coverage.

| Lane | Script count | Estimated duration |
|---|---:|---:|
| `portable-serial-1of4` | 17 | 374457 ms (~374.5 s) |
| `portable-serial-2of4` | 27 | 334474 ms (~334.5 s) |
| `portable-serial-3of4` | 22 | 354465 ms (~354.5 s) |
| `portable-serial-4of4` | 23 | 344460 ms (~344.5 s) |
| imbalance | | 39983 ms |

The single longest script, `tests/fm-pr-check-security.test.sh` at 269158 ms, is the floor for any shard count.

Refresh the hints by downloading the per-shard timing artifacts from a green CI run, replacing the `portable_serial_weight_hints` table in `bin/fm-test-run.sh` with the measured `path`/`duration_ms` pairs, and updating the table above:

```sh
gh run download <run-id> -R kunchenguid/firstmate --pattern 'fm-test-timing-portable-serial-*' -D /tmp/fm-serial
jq -r '.scripts[] | [.path, .duration_ms] | @tsv' /tmp/fm-serial/*.json | LC_ALL=C sort
bin/fm-test-run.sh --check-coverage
```

## Coverage guard

`bin/fm-test-run.sh --check-coverage` verifies that both parallel lanes partition the proven-isolated set.
It also verifies that the parallel lanes, portable serial lane, and real-Herdr family are disjoint and cover every `tests/*.test.sh` script.
It separately verifies that the portable serial CI shards are non-empty, disjoint, and together equal the portable serial lane.

## Timing artifacts

Portable shards, each portable serial shard, and the Herdr lane upload runner-generated timing JSON.
`bin/fm-test-run.sh --aggregate-json` creates the combined summary artifact.
`.github/workflows/ci.yml` owns the exact artifact names and aggregation wiring.

## Local entry points

[CONTRIBUTING.md](../CONTRIBUTING.md) owns the local test policy and common entry points.
`bin/fm-test-run.sh --help` owns exact lane names, selection flags, and bounded `--jobs` mechanics.

## Timeouts

| Lane | Bound | Rationale |
|---|---|---|
| portable parallel 1/2 | job `timeout-minutes: 10` | The measured shard sums are about three minutes and the timeout is a hang tripwire. |
| portable serial 1-4 | job `timeout-minutes: 15` | Each balanced shard is about five minutes, leaving roughly 3x hang-tripwire margin. |
| Herdr | family-run step `timeout-minutes: 20`; job `timeout-minutes: 75` backstop | Healthy runs finish around 7 minutes, so the step bound is the hang tripwire (cleanup and timing artifacts still upload) while the job cap stays a last-resort backstop. |

Timeouts are hang tripwires rather than expected healthy durations.
`.github/workflows/ci.yml` owns the exact numbers.
