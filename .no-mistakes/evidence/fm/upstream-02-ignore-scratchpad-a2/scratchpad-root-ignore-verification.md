# Integration 2/10: root-only scratchpad ignore verification

Validated target `7c87aae1d94d4779406576b799d61c766fc4745f` against base
`98889a07bf0724599c89fb13deaef3c673f25695`.

## Observable Git behavior

The checks use Git's real ignore consumer, disable the user's global excludes,
and use `--no-index` so the paths do not need to be created in the worktree.

```console
$ git -c core.excludesFile=/dev/null check-ignore -v --no-index -- scratchpad/no-mistakes-probe.txt
.gitignore:4:/scratchpad/ scratchpad/no-mistakes-probe.txt

$ git -c core.excludesFile=/dev/null check-ignore -q --no-index -- nested-user-data/scratchpad/no-mistakes-probe.txt
$ echo $?
1

$ git -c core.excludesFile=/dev/null check-ignore -q --no-index -- scratchpad-backup/no-mistakes-probe.txt
$ echo $?
1
```

Result: a file under the repository-root `scratchpad/` is ignored, while an
identically named nested directory and a similarly prefixed root directory
remain visible to Git.

## Commit-graph and effective-scope assertions

```text
merge=8f65e391c0ec3b725b0770d7a57181f4ca90c635
parents=98889a07bf0724599c89fb13deaef3c673f25695 6789876442d0fb6da9f70d86399a2930c5073ae2
subject=Merge upstream commit 67898764 (integration 2/10)

upstream=6789876442d0fb6da9f70d86399a2930c5073ae2
parent=12384026c52803e033407f7f7add6611ec3d2aac
subject=chore: ignore scratchpad/ at the repo root (#2359)

PASS: integration 1 predates the base and remains an ancestor
PASS: exact upstream commit remains an ancestor and exact second parent of the merge
PASS: exact upstream parent is integration 1
```

The complete first-parent additive history after the base is:

```text
8f65e39 Merge upstream commit 67898764 (integration 2/10)
ac86863 fix: scope scratchpad ignore to repository root
728fc3b no-mistakes(document): Document root-only scratchpad ignore
662d599 no-mistakes: apply CI fixes
f3a92b9 Revert "no-mistakes: apply CI fixes"
7c87aae Revert "no-mistakes(document): Document root-only scratchpad ignore"
```

The effective base-to-target diff is limited to:

```text
1  0  .gitignore
```

The rejected `docs/configuration.md` and `.github/workflows/ci.yml` changes are
byte-identical to the base. Exactly one merge appears after the base, and its
second parent is the exact requested upstream commit.
