#!/usr/bin/env bash
# Verify that one project's canonical GitHub repository owner is exactly netixc.
#
# Usage: fm-github-owner-policy.sh [project-dir]
#
# This is the single owner of the personal edition's GitHub PR/issue creation
# policy. Firstmate calls it immediately before each Firstmate-managed
# no-mistakes run and immediately before native `gh-axi pr create` or
# `gh-axi issue create` operations. It is a verifier, not a forge wrapper:
# successful callers continue with their existing mutation path.
#
# Identity is resolved fresh on every call. The project's one exact origin URL
# supplies the repository candidate, then GitHub's authenticated repository API
# supplies canonical owner, full name, and URL. Missing or multiple origin URLs,
# non-GitHub remotes, incomplete or inconsistent API evidence, and every
# canonical owner other than the literal `netixc` refuse.

set -u

PROJECT_DIR=${1:-.}
ALLOWED_OWNER=netixc

fail() {
  echo "REFUSED: $*" >&2
  exit 1
}

ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null) \
  || fail "cannot resolve a Git repository from $PROJECT_DIR"
ORIGINS=$(git -C "$ROOT" remote get-url --all origin 2>/dev/null) \
  || fail "repository has no readable origin remote"
ORIGIN_COUNT=$(printf '%s\n' "$ORIGINS" | awk 'NF { count++ } END { print count + 0 }')
[ "$ORIGIN_COUNT" -eq 1 ] \
  || fail "repository origin is absent or ambiguous ($ORIGIN_COUNT URLs)"
ORIGIN=$(printf '%s\n' "$ORIGINS" | awk 'NF { print; exit }')

case "$ORIGIN" in
  https://github.com/*)
    REPOSITORY=${ORIGIN#https://github.com/}
    ;;
  git@github.com:*)
    REPOSITORY=${ORIGIN#git@github.com:}
    ;;
  ssh://git@github.com/*)
    REPOSITORY=${ORIGIN#ssh://git@github.com/}
    ;;
  *)
    fail "origin is not an exact github.com repository URL"
    ;;
esac
REPOSITORY=${REPOSITORY%.git}
case "$REPOSITORY" in
  */*) ;;
  *) fail "origin does not identify owner/repository" ;;
esac
REMOTE_OWNER=${REPOSITORY%%/*}
REMOTE_REPO=${REPOSITORY#*/}
case "$REMOTE_OWNER" in
  ''|*/*|*[!A-Za-z0-9-]*) fail "origin has an invalid GitHub owner" ;;
esac
case "$REMOTE_REPO" in
  ''|*/*|.|..|*[!A-Za-z0-9._-]*) fail "origin has an invalid GitHub repository" ;;
esac

API_OUTPUT=$(gh-axi api "/repos/$REMOTE_OWNER/$REMOTE_REPO" \
  --jq '{owner:.owner.login,full_name:.full_name,html_url:.html_url}' 2>/dev/null) \
  || fail "GitHub did not return authoritative repository identity"
CANONICAL_OWNER=$(printf '%s\n' "$API_OUTPUT" | sed -n 's/^owner: \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p')
CANONICAL_FULL_NAME=$(printf '%s\n' "$API_OUTPUT" | sed -n 's/^full_name: \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p')
CANONICAL_URL=$(printf '%s\n' "$API_OUTPUT" | sed -n 's/^html_url: \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p')
[ -n "$CANONICAL_OWNER" ] && [ -n "$CANONICAL_FULL_NAME" ] && [ -n "$CANONICAL_URL" ] \
  || fail "GitHub repository identity is absent or ambiguous"
case "$CANONICAL_OWNER" in
  ''|*/*|*[!A-Za-z0-9-]*) fail "GitHub canonical owner is ambiguous ($CANONICAL_OWNER)" ;;
esac
case "$CANONICAL_FULL_NAME" in
  "$CANONICAL_OWNER"/*) ;;
  *) fail "GitHub canonical repository identity is ambiguous ($CANONICAL_FULL_NAME)" ;;
esac
CANONICAL_REPO=${CANONICAL_FULL_NAME#"$CANONICAL_OWNER"/}
case "$CANONICAL_REPO" in
  ''|*/*|.|..|*[!A-Za-z0-9._-]*)
    fail "GitHub canonical repository identity is ambiguous ($CANONICAL_FULL_NAME)" ;;
esac
[ "$CANONICAL_URL" = "https://github.com/$CANONICAL_FULL_NAME" ] \
  || fail "GitHub canonical repository URL is ambiguous ($CANONICAL_URL)"
[ "$CANONICAL_OWNER" = "$ALLOWED_OWNER" ] \
  || fail "canonical GitHub owner '$CANONICAL_OWNER' is not allowed (expected '$ALLOWED_OWNER')"

printf 'allowed: %s\n' "$CANONICAL_FULL_NAME"
