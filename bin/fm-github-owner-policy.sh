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
# Identity is resolved fresh on every call. The project's one exact origin fetch
# URL and effective push URL must identify the same repository, then GitHub's
# authenticated github.com API supplies canonical owner, full name, and URL.
# Missing or multiple URLs, divergent push destinations, non-GitHub remotes,
# incomplete or inconsistent API evidence, and every canonical owner other than
# the literal `netixc` refuse. Success prints the canonical OWNER/REPOSITORY so a
# native creation command can bind GH_REPO to the identity that was verified.

set -u

PROJECT_DIR=${1:-.}
ALLOWED_OWNER=netixc

fail() {
  echo "REFUSED: $*" >&2
  exit 1
}

ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null) \
  || fail "cannot resolve a Git repository from $PROJECT_DIR"
FETCH_URLS=$(git -C "$ROOT" remote get-url --all origin 2>/dev/null) \
  || fail "repository has no readable origin remote"
FETCH_COUNT=$(printf '%s\n' "$FETCH_URLS" | awk 'NF { count++ } END { print count + 0 }')
[ "$FETCH_COUNT" -eq 1 ] \
  || fail "repository origin fetch destination is absent or ambiguous ($FETCH_COUNT URLs)"
FETCH_URL=$(printf '%s\n' "$FETCH_URLS" | awk 'NF { print; exit }')

PUSH_URLS=$(git -C "$ROOT" remote get-url --push --all origin 2>/dev/null) \
  || fail "repository has no readable origin push destination"
PUSH_COUNT=$(printf '%s\n' "$PUSH_URLS" | awk 'NF { count++ } END { print count + 0 }')
[ "$PUSH_COUNT" -eq 1 ] \
  || fail "repository origin push destination is absent or ambiguous ($PUSH_COUNT URLs)"
PUSH_URL=$(printf '%s\n' "$PUSH_URLS" | awk 'NF { print; exit }')

parse_github_repository() {
  local label=$1 url=$2 repository owner repo
  case "$url" in
    https://github.com/*) repository=${url#https://github.com/} ;;
    git@github.com:*) repository=${url#git@github.com:} ;;
    ssh://git@github.com/*) repository=${url#ssh://git@github.com/} ;;
    *) fail "$label is not an exact github.com repository URL" ;;
  esac
  repository=${repository%.git}
  case "$repository" in
    */*) ;;
    *) fail "$label does not identify owner/repository" ;;
  esac
  owner=${repository%%/*}
  repo=${repository#*/}
  case "$owner" in
    ''|*/*|*[!A-Za-z0-9-]*) fail "$label has an invalid GitHub owner" ;;
  esac
  case "$repo" in
    ''|*/*|.|..|*[!A-Za-z0-9._-]*) fail "$label has an invalid GitHub repository" ;;
  esac
  printf '%s/%s\n' "$owner" "$repo"
}

FETCH_REPOSITORY=$(parse_github_repository "origin fetch destination" "$FETCH_URL") || exit 1
PUSH_REPOSITORY=$(parse_github_repository "origin push destination" "$PUSH_URL") || exit 1
[ "$FETCH_REPOSITORY" = "$PUSH_REPOSITORY" ] \
  || fail "origin push destination '$PUSH_REPOSITORY' differs from fetch repository '$FETCH_REPOSITORY'"
REMOTE_OWNER=${PUSH_REPOSITORY%%/*}
REMOTE_REPO=${PUSH_REPOSITORY#*/}

API_OUTPUT=$(gh-axi api "/repos/$REMOTE_OWNER/$REMOTE_REPO" --hostname github.com \
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

printf '%s\n' "$CANONICAL_FULL_NAME"
