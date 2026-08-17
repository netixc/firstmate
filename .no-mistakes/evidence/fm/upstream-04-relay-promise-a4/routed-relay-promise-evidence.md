# Routed Relay promise — behavioral evidence

## End-user CLI guardrail and ownership state

```text
$ FM_HOME=<main> bin/fm-relay-link.sh routed-login discord-request-42
fm-relay-link: no such task: state/routed-login.meta
fm-relay-link: routed-login is a second mate task (found in: design), so this home cannot link it - a link only binds work whose record lives here.
fm-relay-link: bind the public promise through the promised-final path instead: tasks-axi public-followup add + bind-work, then bin/fm-public-followup.sh register <obligation-id> --relation <relation-id> --work-home secondmate:design --work-id routed-login --generation <n>, and put the bin/fm-public-followup.sh brief <obligation-id> command into the routed worker instructions.
exit=1
main task record: absent (no duplicate owner)
second-mate task record after refusal:
window=w
worktree=/work/design
kind=ship
```

This fixture exercises the executable CLI against a registered, marked second-mate home. The originating home refuses to invent a duplicate task/link, identifies the actual work owner, and prints the runnable promised-final binding that keeps the Discord reply owned and reachable from the originating home.

## Executable end-to-end outcomes

The focused behavioral suites exercised the real `tasks-axi` public-followup state machine with a fake Relay transport:

- backlog handoff moved promised work successfully, surfaced the unresolved main-home promise, and named `--work-home secondmate:design`; an unrelated item emitted no warning;
- a Discord promise bound to `secondmate:fmdev` survived restart, reconciled a typed terminal result from disk, and delivered exactly one reply to the original thread;
- duplicate terminal events and replay were no-ops;
- a Relay transport failure remained retryable with no false completion, then posted exactly once on retry;
- a child home could emit the typed result but could not become the outward-post owner.

## Required merge ancestry

```text
merge=ced428a3852a9c7c54101a7565316cea177a0ceb
parents=e867eb1f40e8ab783c8ac4b63de6a35534ff89d6 7a3259e5bca780a53ace49d77d086c89536f6f15
subject=Merge upstream commit 7a3259e5 (integration 4/10)
upstream-parent-is-ancestor=yes
prior-integrations-base-is-ancestor=yes
```

The exact upstream commit is the second parent of the real integration merge, while the prior integrated base remains an ancestor.
