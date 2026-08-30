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

The test initializes two temporary local repositories whose sole `origin` URLs identify `netixc/firstmate` and `octocat/Hello-World`, then invokes the tracked policy through its public executable interface.
Each invocation resolves fresh canonical owner, full-name, and repository-URL evidence through `gh-axi api`.
The test performs no pull-request or issue mutation.
