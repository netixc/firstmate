# GitHub owner-policy verification

This record maintains the real read-only GitHub evidence for the personal edition's canonical repository-owner policy.
The executable contract is owned by [`bin/fm-github-owner-policy.sh`](../../bin/fm-github-owner-policy.sh), with portable mechanics covered by [`tests/fm-github-owner-policy.test.sh`](../../tests/fm-github-owner-policy.test.sh).

## 2026-08-30 live evidence

Tool versions:

```text
gh-axi 0.1.34
```

Command:

```sh
FM_GITHUB_OWNER_POLICY_LIVE=1 tests/fm-github-owner-policy-live.test.sh
```

Exact output:

```text
ok - live GitHub API allows canonical netixc/firstmate
ok - live GitHub API refuses canonical octocat/Hello-World before mutation
```

The test initializes two temporary local repositories whose sole `origin` fetch and effective push URLs identify `netixc/firstmate` and `octocat/Hello-World`, then invokes the tracked policy through its public executable interface.
Each invocation binds its read-only API request to github.com and resolves fresh canonical owner, full-name, and repository-URL evidence through `gh-axi api`.
A successful invocation emits the canonical owner and repository for native creation commands to bind through `GH_REPO`.
The portable regression also proves that multiple push destinations, divergent explicit `remote.origin.pushurl`, and effective `url.*.pushInsteadOf` rewrites are refused before a caller can mutate them.
The test performs no pull-request or issue mutation.
