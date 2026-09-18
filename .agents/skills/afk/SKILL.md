---
name: afk
description: >-
  Enter the away posture when the captain invokes /afk, says they are going afk, `state/.afk-contract` exists, or an incoming message starts with `FM_INJECT_MARK`.
  It reads the captain's away words back as a mandate, writes the durable away-posture record after their go, announces hold-for-return only at entry, keeps Pi's ordinary supervision session running, and on the first unmarked message renders the return brief from durable records before ordinary work resumes.
user-invocable: true
metadata:
  internal: true
---

# afk

Away mode is a POSTURE of Pi's ordinary supervision session.
Being away changes exactly two things: how the captain is informed, and what happens at a captain-owned decision point (hold for return, or later a pre-answered clause).
It never changes the authority set.
The posture is a file, `state/.afk-contract`, written only by `bin/fm-afk-contract.sh` after the captain confirms a read-back; nothing infers the posture from chat.
Hold-for-return is the default and the only reach profile this release records: there is no phone channel, and the entry announcement says so aloud every time.

## Entering: `/afk [words]`

1. **Translate the captain's words into mandate clauses.**
   The words are recorded verbatim; the clauses are your reading of them as explicit fields `bin/fm-afk-contract.sh` records: an action from its fixed verb list, the object in the captain's words, and the stated precondition in the captain's words, plus an optional stop.
   Read `bin/fm-afk-contract.sh --help` for the field flags, verb list, and coarse best-effort never-set flag rather than memorizing them.
   No static parser reads the object or precondition text, by the captain's mandate: you supply the fields, the script records them verbatim, checks structural presence and the verb list, and may flag obvious never-set concepts without treating that best-effort scan as authoritative.
   A flagged clause is still recorded, never refused, and the read-back and return brief show the flag; the flag can miss spellings, including joined compounds such as `oneTimeCode`, never fires on unrelated names such as `ping-service`, and authoritative never-set, forbidden-action, and precondition judgment belongs to the supervision session at execution time in phase 4.
   Forbidden, destructive, irreversible, and security-sensitive actions are never pre-authorizable regardless of clause text, and no recorded clause is authority by itself.
   Write only clauses the words actually support; a wish with no object or no stated precondition is not a clause.
   Plain `/afk` with no words has no clauses.
2. **Propose and read back.**
   Run `bin/fm-afk-launch.sh propose --words-file <path> [--action <verb> --object <text> --when <text> [--stop <text>]]... [--expected-return <UTC ISO 8601>] [--spend <n>] [--grant <task-id>]...` (or `--words <text>`), and relay its read-back to the captain in `AGENTS.md` section 9 language: the accepted clauses as a numbered list, every refused clause with the part it is missing, the expected return, the spend cap, any merge-when-green task ids, and the one-sentence reach announcement.
   When the captain names task ids that may merge while green, pass `--grant <id>` for each named id.
   Never infer task ids from clause prose, object text, or the away words.
   Red-check exceptions stay in the words or clause `when` text and are not executed.
   A refused clause does not fail the proposal; the captain can restate it or leave it refused.
   Exit 3 only means a clause was refused; the proposal stands.
3. **Confirm on the captain's go.**
   Run `bin/fm-afk-launch.sh confirm`; it promotes the proposal into the record and prints the entry announcement.
   Relay that announcement verbatim in spirit: hold-for-return only, no phone channel, anything that needs the captain waits for their return, N clauses recorded and M refused, recorded clauses are held for the return brief and are not executed by this release, and forbidden, destructive, irreversible, and security-sensitive actions are never pre-authorizable regardless of clause text because no recorded clause is authority by itself.
   With no words, run `propose` and `confirm` back to back; the announcement is the same.
   Re-invoking `/afk` while already away with no new words is a refresh and leaves the standing record untouched; new words replace the mandate after the same read-back, preserve the original session entry, and archive the superseded mandate for the return brief.
4. **Keep Pi supervision live.**
   Stop after confirmation; do not run `bin/fm-afk-launch.sh start`.
   Pi's ordinary supervision session (`docs/pi-supervision-branch.md`) continues with the posture record present; the launch script records posture only.
5. **Do not arm a second cycle.**
   Pi's supervision extension owns the one live cycle exactly as it does while attended.

## While away

- The record exists, so the watcher never rechecks an item held for the captain; the return brief lists it instead.
  Declared external waits keep their condition-aware, hours-long recheck cadence (`bin/fm-watch.sh`, `bin/fm-classify-lib.sh`).
- Recorded clauses are not executed by this release.
  Forbidden, destructive, irreversible, and security-sensitive actions are never pre-authorizable regardless of clause text, no recorded clause is authority by itself, and merge authority plus ask-user findings keep exactly the rules they have when attended (`AGENTS.md` section 7 and `ask-user-authority`); anything that needs the captain holds for their return.
- The session-start digest reports the posture under its AFK subsection, so a restart re-enters the posture from the record, not from memory.

## How to exit: the return

No `/back` is needed. The first genuine message is the return signal:

- A message **without** the current operational prefix or a legacy bare marker, and **not** starting with `/afk` -> the captain is back.
  Run `bin/fm-afk-return.sh` before acting on the message that brought the captain back.
  That script owns stale-artifact cleanup, archive of the posture record, durable notification presentation and post-handling acknowledgement, the return brief, and the return-catch-up gate.
  Relay the return brief in section 9 language and in its own order: supervisor health across the away window first (any gap leads), then every clause and that it was recorded only, then what is waiting on the captain, then what was tried and failed or could not be fixed, then what was handled, then cost.
  The gate keeps every open `blocked:` event until that blocker's own resolution is proven: remediate each immediately through the normal lifecycle, or explicitly reclassify it with a durable reason and close its decision key with `resolved [key=...]`, then run `bin/fm-afk-return.sh check`.
  Captain-verdict outcomes are listed under "waiting on you", but do not exempt open blockers because per-blocker provenance is deferred to phase 4.
  Once the record is archived, resume full per-wake responsiveness through the emitted primary-harness supervision protocol while blocker handling proceeds, so the gate never creates a blind wait.
  A Bearings request may be answered while the gate is open, and the digest surfaces the catch-up state as a Charted Next `(return-catchup)` warning row naming what still holds it.
  Acting on the fleet - dispatching, steering, merging, or any other ordinary captain work - still waits until the check exits successfully.
- A message **with** the current operational prefix (`FM_OPERATIONAL_PREFIX`, U+2063 INVISIBLE SEPARATOR followed by `FIRSTMATE_OP: `), or a bare `FM_INJECT_MARK` escalation -> stay away and process it.
- Re-invoking `/afk` while already away -> stay away (refresh); this does **not** trigger an exit.

Bias ambiguous cases toward exit: a present captain beats token savings, and a false exit is self-correcting (the captain re-runs `/afk`).
When the captain wants this same token-saving supervision while staying present and chatting - ordinary messages should NOT exit it - that is `/quiet` (kunchenguid/firstmate#2356), not `/afk`.

## Orthogonal to approval authority

afk changes how the captain is informed and what happens at a captain-owned decision point, **not who approves what**.
"Away" never means "approves more" or "approves less."
A PR ready for merge keeps the merge authority from `AGENTS.md` section 7, and a needs-decision finding keeps the `ask-user-authority` policy; anything requiring the captain still waits for the captain's explicit word.
While the away-posture record exists, a merge proceeds only when that task's recorded yolo posture is on or its id is in the record's merge-grant list; otherwise it is held for the captain's return.
A merge grant never releases a captain hold, and it expires when the away record is archived.
`--allow-red` remains attended-only and is refused while the record exists.
A merge under away authority must be synchronous; `fm-pr-merge.sh` refuses auto-merge and any GitHub queue state that cannot prove an immediate merge while the record exists.
A mandate clause is the captain's explicit instruction given before leaving, recorded with its named object and condition; a clause is never inferred, never applied by analogy, and expires at return.
Forbidden, destructive, irreversible, and security-sensitive actions are never pre-authorizable regardless of clause text, and no recorded clause is authority by itself.
This release records clauses and does not execute them.
