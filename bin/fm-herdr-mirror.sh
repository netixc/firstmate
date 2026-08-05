#!/usr/bin/env bash
# Manage the pinned Herdr Mirror plugin and its operator CLI entrypoint.
#
# This is the single owner of Firstmate's supported netixc/herdr-mirror
# release, source commit, release-binary digests, installed-plugin contract,
# and ~/.local/bin entrypoint. Herdr remains the package manager: install uses
# its supported GitHub-plugin reinstall path, whose upstream build step fetches
# and verifies the published release asset. This script independently verifies
# the installed asset against the release digest before accepting it.
#
# Existing Herdr Mirror config/state and every unrelated Herdr plugin are owned
# by the user and Herdr. This script never reads or writes hosts.toml, Herdr's
# config.toml, plugin config/state, credentials, SSH aliases, or session names.
# It creates ~/.local/bin/herdr-mirror only when absent and never replaces an
# entrypoint it cannot prove already targets this exact managed plugin binary.
#
# Usage:
#   fm-herdr-mirror.sh required <secondmate-registry>
#   fm-herdr-mirror.sh check-plugin
#   fm-herdr-mirror.sh check
#   fm-herdr-mirror.sh status
#   fm-herdr-mirror.sh install
#
# `required` succeeds only when data/secondmates.md contains a valid registered
# remote route. Bootstrap uses that existing registration as the narrow opt-in:
# homes with only local second mates, or no second mates, never need the tool.
# `check-plugin` is silent and succeeds when plugin, binary, and source pin are
# current. `check` also requires the CLI link. `install` is the consent-gated
# convergence action called by fm-bootstrap.sh after approval; reruns are safe
# and preserve user-owned state.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FM_HERDR_MIRROR_VERSION=0.1.16
FM_HERDR_MIRROR_TAG="v${FM_HERDR_MIRROR_VERSION}"
FM_HERDR_MIRROR_SOURCE=netixc/herdr-mirror
FM_HERDR_MIRROR_OWNER=netixc
FM_HERDR_MIRROR_REPO=herdr-mirror
FM_HERDR_MIRROR_COMMIT=a569217ae59166470aa6a1fc0bbca2dea196af64
FM_HERDR_MIRROR_PLUGIN_ID=mirror

HERDR_BIN=${FM_HERDR_MIRROR_HERDR_BIN:-}
CLI_LINK=${FM_HERDR_MIRROR_CLI_LINK:-${HOME:?HOME is required}/.local/bin/herdr-mirror}
PLUGIN_ROOT=
PLUGIN_BINARY=
FM_HERDR_MIRROR_REASON=

usage() {
  printf 'usage: fm-herdr-mirror.sh required <secondmate-registry> | check-plugin | check | status | install\n' >&2
  exit 2
}

die() {
  printf 'fm-herdr-mirror.sh: %s\n' "$*" >&2
  exit 1
}

resolve_herdr() {
  if [ -n "$HERDR_BIN" ]; then
    [ -x "$HERDR_BIN" ] || return 1
    return 0
  fi
  HERDR_BIN=$(command -v herdr 2>/dev/null || true)
  [ -n "$HERDR_BIN" ] && [ -x "$HERDR_BIN" ]
}

expected_sha256() {
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64|Darwin-aarch64)
      printf '%s\n' 08483f7533f8097392c34ef4bd7d40fc2425ea0609bcfbf65d2bcae82c7bcdb4
      ;;
    Darwin-x86_64|Darwin-amd64)
      printf '%s\n' abd5eb373712d5764ef10a394812d052cc198c28859fd2339c4390c956541745
      ;;
    Linux-arm64|Linux-aarch64)
      printf '%s\n' 3af127b615199dfcca59613d898200f352747747dc152e8f3010921e44999dbe
      ;;
    Linux-x86_64|Linux-amd64)
      printf '%s\n' 640f32f4c93c9ae5c01057cb4a04980c6615faff5f7224ad5d7487dff41229f7
      ;;
    *) return 1 ;;
  esac
}

sha256_file() {
  local file=$1 digest
  if command -v sha256sum >/dev/null 2>&1; then
    digest=$(sha256sum "$file" 2>/dev/null | awk '{print $1; exit}') || return 1
  elif command -v shasum >/dev/null 2>&1; then
    digest=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1; exit}') || return 1
  else
    return 1
  fi
  case "$digest" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#digest}" -eq 64 ] || return 1
  printf '%s\n' "$digest"
}

plugin_current() {
  local json count version kind owner repo commit managed expected actual
  FM_HERDR_MIRROR_REASON=
  PLUGIN_ROOT=
  PLUGIN_BINARY=

  if ! resolve_herdr; then
    FM_HERDR_MIRROR_REASON='Herdr CLI is unavailable'
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    FM_HERDR_MIRROR_REASON='jq is unavailable'
    return 1
  fi
  if ! json=$("$HERDR_BIN" plugin list --plugin "$FM_HERDR_MIRROR_PLUGIN_ID" --json 2>/dev/null); then
    FM_HERDR_MIRROR_REASON='Herdr could not list the mirror plugin'
    return 1
  fi
  count=$(printf '%s' "$json" | jq -er '.result.plugins | length' 2>/dev/null) || {
    FM_HERDR_MIRROR_REASON='Herdr returned an unreadable plugin list'
    return 1
  }
  if [ "$count" != 1 ]; then
    FM_HERDR_MIRROR_REASON='the mirror plugin is not installed exactly once'
    return 1
  fi

  version=$(printf '%s' "$json" | jq -er '.result.plugins[0].version' 2>/dev/null) || version=
  kind=$(printf '%s' "$json" | jq -er '.result.plugins[0].source.kind' 2>/dev/null) || kind=
  owner=$(printf '%s' "$json" | jq -er '.result.plugins[0].source.owner' 2>/dev/null) || owner=
  repo=$(printf '%s' "$json" | jq -er '.result.plugins[0].source.repo' 2>/dev/null) || repo=
  commit=$(printf '%s' "$json" | jq -er '.result.plugins[0].source.resolved_commit' 2>/dev/null) || commit=
  PLUGIN_ROOT=$(printf '%s' "$json" | jq -er '.result.plugins[0].plugin_root' 2>/dev/null) || PLUGIN_ROOT=
  managed=$(printf '%s' "$json" | jq -er '.result.plugins[0].source.managed_path' 2>/dev/null) || managed=

  if [ "$version" != "$FM_HERDR_MIRROR_VERSION" ] \
    || [ "$kind" != github ] \
    || [ "$owner" != "$FM_HERDR_MIRROR_OWNER" ] \
    || [ "$repo" != "$FM_HERDR_MIRROR_REPO" ] \
    || [ "$commit" != "$FM_HERDR_MIRROR_COMMIT" ]; then
    FM_HERDR_MIRROR_REASON='the installed mirror plugin is absent, outdated, or from an unsupported source'
    return 1
  fi
  case "$PLUGIN_ROOT" in /*) ;; *)
    FM_HERDR_MIRROR_REASON='the managed mirror plugin root is missing or unsafe'
    return 1
  esac
  if [ "$managed" != "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ] || [ -L "$PLUGIN_ROOT" ]; then
    FM_HERDR_MIRROR_REASON='the managed mirror plugin root is missing or unsafe'
    return 1
  fi

  PLUGIN_BINARY="$PLUGIN_ROOT/target/release/herdr-mirror"
  if [ ! -f "$PLUGIN_BINARY" ] || [ -L "$PLUGIN_BINARY" ] || [ ! -x "$PLUGIN_BINARY" ]; then
    FM_HERDR_MIRROR_REASON='the managed mirror binary is missing or not executable'
    return 1
  fi
  expected=$(expected_sha256) || {
    FM_HERDR_MIRROR_REASON='this platform has no supported Herdr Mirror release asset'
    return 1
  }
  actual=$(sha256_file "$PLUGIN_BINARY") || {
    FM_HERDR_MIRROR_REASON='the managed mirror binary could not be integrity-checked'
    return 1
  }
  if [ "$actual" != "$expected" ]; then
    FM_HERDR_MIRROR_REASON='the managed mirror binary does not match the supported release digest'
    return 1
  fi
  return 0
}

link_current() {
  local target
  if [ ! -L "$CLI_LINK" ]; then
    if [ -e "$CLI_LINK" ]; then
      FM_HERDR_MIRROR_REASON="the CLI path is user-owned and was left unchanged: $CLI_LINK"
    else
      FM_HERDR_MIRROR_REASON="the managed CLI link is absent: $CLI_LINK"
    fi
    return 1
  fi
  target=$(readlink "$CLI_LINK" 2>/dev/null || true)
  if [ "$target" != "$PLUGIN_BINARY" ]; then
    FM_HERDR_MIRROR_REASON="the CLI link has an unrelated target and was left unchanged: $CLI_LINK"
    return 1
  fi
  return 0
}

mirror_current() {
  plugin_current && link_current
}

ensure_cli_link() {
  local parent target
  parent=${CLI_LINK%/*}
  [ "$parent" != "$CLI_LINK" ] || die "CLI link must include a parent directory: $CLI_LINK"
  if [ -e "$parent" ] || [ -L "$parent" ]; then
    [ -d "$parent" ] && [ ! -L "$parent" ] \
      || die "CLI directory is not a safe directory: $parent"
  else
    mkdir -p "$parent" || die "could not create CLI directory: $parent"
    [ -d "$parent" ] && [ ! -L "$parent" ] \
      || die "CLI directory is not a safe directory: $parent"
  fi

  if [ -e "$CLI_LINK" ] || [ -L "$CLI_LINK" ]; then
    [ -L "$CLI_LINK" ] \
      || die "refusing to overwrite user-owned CLI path: $CLI_LINK"
    target=$(readlink "$CLI_LINK" 2>/dev/null || true)
    [ "$target" = "$PLUGIN_BINARY" ] \
      || die "refusing to replace unrelated CLI link: $CLI_LINK"
    return 0
  fi
  ln -s "$PLUGIN_BINARY" "$CLI_LINK" \
    || die "could not create managed CLI link: $CLI_LINK"
}

remote_route_registered() {
  local registry=$1 line
  [ -f "$registry" ] && [ ! -L "$registry" ] || return 1
  # shellcheck source=bin/fm-secondmate-registry-lib.sh disable=SC1091
  . "$SCRIPT_DIR/fm-secondmate-registry-lib.sh"
  secondmate_registry_validate_bindings "$registry" secondmate_registry_path_key || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '- '*) ;; *) continue ;; esac
    secondmate_registry_parse_line "$line" || continue
    [ "$SECONDMATE_REGISTRY_REMOTE" -eq 1 ] && return 0
  done < "$registry"
  return 1
}

command=${1:-}
case "$command" in
  required)
    [ "$#" -eq 2 ] || usage
    remote_route_registered "$2"
    ;;
  check-plugin)
    [ "$#" -eq 1 ] || usage
    plugin_current
    ;;
  check)
    [ "$#" -eq 1 ] || usage
    mirror_current
    ;;
  status)
    [ "$#" -eq 1 ] || usage
    if mirror_current; then
      printf 'herdr-mirror %s is current (%s)\n' "$FM_HERDR_MIRROR_VERSION" "$PLUGIN_BINARY"
      exit 0
    fi
    printf 'herdr-mirror needs installation or repair: %s\n' "$FM_HERDR_MIRROR_REASON"
    exit 1
    ;;
  install)
    [ "$#" -eq 1 ] || usage
    if ! plugin_current; then
      resolve_herdr || die 'Herdr CLI is required before Herdr Mirror can be installed'
      command -v git >/dev/null 2>&1 || die 'git is required for Herdr plugin installation'
      command -v curl >/dev/null 2>&1 || die 'curl is required by the supported Herdr Mirror installer'
      printf 'fm-herdr-mirror.sh: installing %s at %s (%s)\n' \
        "$FM_HERDR_MIRROR_SOURCE" "$FM_HERDR_MIRROR_TAG" "$FM_HERDR_MIRROR_COMMIT" >&2
      "$HERDR_BIN" plugin install --ref "$FM_HERDR_MIRROR_COMMIT" --yes "$FM_HERDR_MIRROR_SOURCE" \
        || die 'Herdr plugin installation failed'
      plugin_current || die "installed plugin did not converge: $FM_HERDR_MIRROR_REASON"
    fi
    ensure_cli_link
    mirror_current || die "installation did not converge: $FM_HERDR_MIRROR_REASON"
    printf 'fm-herdr-mirror.sh: herdr-mirror %s is current at %s\n' \
      "$FM_HERDR_MIRROR_VERSION" "$PLUGIN_BINARY" >&2
    printf 'herdr-mirror %s\n' "$FM_HERDR_MIRROR_VERSION"
    ;;
  *) usage ;;
esac
