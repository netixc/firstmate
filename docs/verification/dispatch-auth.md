# Dispatch authentication verification

Audience: maintainer verification.

This record supports the dispatch judgment rules in `.agents/skills/quota-array-dispatch/SKILL.md`.
It records only facts that must be re-established when a producer or vendor version changes.
Task chronology, incident transcripts, and credential metadata stay in private reports or PR evidence.

Firstmate resolves a candidate's provider family, credential surface, and applicable quota by reading the evidence below and reasoning in the open.
No script maps a model to a provider, a provider to a credential store, or a name prefix to a family, so the facts here are what that reasoning rests on.
Credential paths below are shown with the home directory replaced by `<home>`.

## Quota granularity the judgment depends on

Verified 2026-07-30 against quota-axi 0.1.16.

`quota-axi --json` reports availability at whatever granularity the vendor supplies, and states the vendor's own bounding rule in `quotaSemantics.description`.

```json
{
  "provider": "codex",
  "state": { "status": "fresh", "stale": false },
  "quotaSemantics": {
    "status": "known",
    "description": "Codex base account windows bound every model. Named model windows add bounds for that model; code-review windows describe a separate workload and are not included in model availability.",
    "effectiveAvailability": [
      { "scope": "all_models", "status": "known", "effectivePercentRemaining": 64, "boundedBy": ["weekly"] },
      { "scope": "model:codex_bengalfox", "status": "known", "effectivePercentRemaining": 64, "boundedBy": ["weekly", "model:codex_bengalfox:7d"] }
    ]
  }
}
```

Three properties follow and are load-bearing for dispatch:

- An `all_models` (or `all_products`) scope is real evidence for every model in that provider family, including a model with no window of its own.
- A `model:`-scoped entry is an additional bound for that one model. `model:codex_bengalfox` is the GPT-5.3-Codex-Spark window and bounds nothing else.
- A named-model window can be tighter than the account bound, so it must not be read across models. A model-specific scope applies only to that named model; every other model remains bounded by the provider's applicable account scopes.

`quotaSemantics.status` is `unknown` with no `effectiveAvailability` entries at all for providers whose vendor exposes no window (observed for `copilot`).
`state.authStatus` is optional, so its absence is missing evidence, not a credential fault.

## Completion-runway shape the judgment depends on

Verified 2026-07-31 against quota-axi 0.1.17 schema 3.
The command below records the producer shape without persisting account-specific quota values:

```sh
quota-axi --json | jq '{schemaVersion, effectiveAvailabilityFields: ([.providers[]?.quotaSemantics.effectiveAvailability[]? | keys] | unique), runwayFields: ([.providers[]?.quotaSemantics.effectiveAvailability[]?.runway? | select(type == "object") | keys] | unique)}'
```

```json
{
  "schemaVersion": 3,
  "effectiveAvailabilityFields": [
    [
      "boundedBy",
      "effectivePercentRemaining",
      "limitingWindowIds",
      "pace",
      "runway",
      "scope",
      "status"
    ]
  ],
  "runwayFields": [
    [
      "limitingWindowId",
      "projectedExhaustedAt",
      "projectionBasis",
      "projectionConfidence",
      "status",
      "usableRunwaySeconds"
    ],
    [
      "limitingWindowId",
      "projectedExhaustedAt",
      "status",
      "usableRunwaySeconds"
    ]
  ]
}
```

`runway` is nested under each effective-availability scope, so the same provider/model applicability rules govern both effective headroom and runway.
Projection confidence and basis are not present on every known runway, so selection must preserve their absence as uncertainty rather than fabricate them.
The older-schema fallback contract is owned by `quota-array-dispatch`; this evidence does not reinterpret an absent runway or pace field.

## Provider-family counterfactual that this producer schema supports

Verified 2026-07-30 on Pi 0.82.0 and quota-axi 0.1.16.

```sh
pi --list-models terra
```

```text
provider      model          context  max-out  thinking  images
openai-codex  gpt-5.6-terra  272K     128K     yes       yes
```

The Pi catalog is authoritative for Pi model support and reports the provider family in its own column.
For `harness=pi`, `model=openai-codex/gpt-5.6-terra` the catalog establishes the model is supported and belongs to the `openai-codex` family, and the Codex `all_models` scope above supplies fresh, known 64 effective remaining for every model in that family.
No Terra-specific window exists in the snapshot, and `quota-axi auth --json` lists no `pi:openai-codex` source.
Both absences are missing model-level and source-level detail, not contradictory evidence, so this candidate is dispatchable with the model-level uncertainty disclosed.

```sh
pi --list-models gpt-9.9-nonexistent
```

```text
No models matching "gpt-9.9-nonexistent"
```

A listing that reaches the account and returns no row is the authoritative negative that does block a candidate.

## Credential sources are independent per provider

Verified 2026-07-30 against quota-axi 0.1.16.

`quota-axi auth --json` reports each provider's credential sources separately, which is what lets a candidate be scoped to the one surface it actually authenticates through:

```json
[
  { "provider": "codex", "sources": [
      { "source": "auth-json", "path": "<home>/.codex/auth.json", "status": "available" },
      { "source": "cli-rpc", "path": "<path-to>/codex", "status": "available" } ] }
]
```

The snapshot reports each source independently rather than collapsing the provider to one credential status.

- A provider can carry more than one independent source, so the sources must remain distinct.
- A source is evidence only for the provider and credential surface that reports it; a missing source with a guessed name is never evidence against a candidate.

Neither this per-source shape nor `state.authStatus` exists before quota-axi 0.1.16.
`bin/fm-bootstrap.sh` enforces the current compatibility floor through `bin/fm-quota-axi-lib.sh`.

## Regression coverage

`tests/fm-spawn-dispatch-profile.test.sh` owns spawn's deterministic profile and harness refusals.
`tests/fm-bootstrap.test.sh` owns the quota-axi version-floor diagnostic.
`tests/fm-quota-array-dispatch-live-e2e.test.sh` drives the public Pi skill-loading interface against one fake `quota-axi --json` snapshot per case.
It covers sharply unequal candidate reserves, explicit accounting for unmeasurable runway, and the strongest-reasoning constraint.
