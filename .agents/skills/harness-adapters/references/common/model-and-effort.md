# Model and effort

Load this with the selected tool reference before choosing, validating, or changing either axis.
Add `references/common/dispatch.md` for configured profile precedence.

## Axes and precedence

`../../../bin/fm-spawn.sh` accepts concrete `--harness`, `--model`, and `--effort` values selected at intake; scripts never parse natural-language dispatch rules.
The tool reference records verified flags, accepted values, omission behavior, and discovery.

Effort precedence is a per-task captain instruction, then applicable dispatch profile or secondmate pin, then the fallback below.
Never replace either higher-precedence value.
Use the fallback only when neither specifies effort.

Use `low` for well-understood work with an explicit bounded path and `xhigh` for ambiguous investigation or design.
Choose intermediate levels as complexity, uncertainty, blast radius, or open-ended reasoning rises.
Pi accepts `xhigh`; do not silently omit the intent.
Never select `max` through this fallback; only an explicit per-task or standing captain preference permits it.

If requested effort is outside Pi's accepted set, the spawn records `effort=` in task metadata but emits no effort flag.
This preserves launch success instead of passing a known-bad value.

## Harness and provider identity

Harness identity is independent of model provider.
A Pi model's provider family does not change the recorded plain Pi harness identity.

No script resolves credential provenance for you.
Establish it from the tool's discovery surface and `quota-axi auth --json` per-provider sources, and show the reasoning rather than inferring it from a name.

## Discovery

Treat model and provider knowledge as current discovery, not a permanent namespace or mapping.
Use the selected tool reference's authoritative surface in the current authenticated environment because availability changes by version, account, and configuration.

For an unfamiliar namespace, establish support and provider identity from Pi's CLI help, model listing, or current documentation.
An account-reaching listing that omits a model is concrete unsupported evidence; block the candidate and quote it.
An unreachable surface establishes nothing; report uncertainty instead of a verdict.

For a matched profile array, return to `quota-array-dispatch` only after establishing every candidate's Pi model support, provider relationship, and uncertainty.
