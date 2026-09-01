# Dispatch and start

Load this with the selected tool reference for dispatch, start, or adapter verification; add `references/common/model-and-effort.md` for either profile axis.

## Resolution

Use the router's detection and safety sections for static crew and secondmate harness resolution and all explicit overrides.
`config/crew-dispatch.json` can override that static default for one crewmate or scout with concrete harness, model, and effort axes.
For a profile array, load `quota-array-dispatch` after establishing harness and provider facts here.

`../secondmate-provisioning/SKILL.md` owns inherited local material.
Its harness consequence is that a secondmate's workers receive literal `config/crew-harness` and `config/crew-dispatch.json`, while the primary-only `config/secondmate-harness` is never inherited because secondmates do not spawn secondmates.
Only a concrete `pi` crew value is supported and inherited into a secondmate home.
Unset or `default` carries no concrete value, so its workers resolve that home's own plain Pi primary rather than inheriting the primary home's crew setting.
The inherited dispatch file applies the same best-fit profiles there.

## Owners

`../../../bin/fm-spawn.sh` owns launch, autonomy, concrete flags, task-kind compatibility, and worker turn-end wiring.
Natural-language rules stay with firstmate, while scripts receive concrete axes.

`../../../bin/fm-busy-lib.sh` owns semantic busy trust.
Composer shapes, glyphs, placeholders, popups, rendered delivery signals, and the `empty` / `pending` / `pending-unproven` / `unknown` decision belong only to `../../../bin/fm-composer-lib.sh`.
Tool references record empirical knowledge for those executable owners.

## Pi integration verification

Verify Pi detection in `../../../bin/fm-harness.sh`, canonical launch in `../../../bin/fm-spawn.sh`, busy state in `../../../bin/fm-busy-lib.sh`, shared composer behavior in `../../../bin/fm-composer-lib.sh`, lifecycle in `../../../bin/fm-control-lib.sh`, and Herdr liveness in `../../../bin/backends/herdr.sh` when secondmate use is supported.
Also verify primary integration through `references/common/primary-hooks.md`, model discovery through `references/common/model-and-effort.md`, and one tool record.
Pi support changes require their executable owner, portable regression, applicable credentialed live guard, and verification record to land together.
`../firstmate-coding-guidelines/SKILL.md` owns Pi-dependent proof.
