#!/usr/bin/env bash
# Remote installer — pipe from GitHub (oh-my-zsh style):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)"
set -euo pipefail

PHPVER_REPO="${PHPVER_REPO:-https://github.com/robertoporceddu/phpver.git}"
PHPVER_BRANCH="${PHPVER_BRANCH:-main}"
PHPVER_RAW_BASE="${PHPVER_RAW_BASE:-https://raw.githubusercontent.com/robertoporceddu/phpver/${PHPVER_BRANCH}}"

phpver_install__die() {
  printf 'phpver install: %s\n' "$*" >&2
  exit 1
}

phpver_install__require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || phpver_install__die "phpver supports macOS only"
}

phpver_install__fetch_with_git() {
  local dest="$1"
  command -v git >/dev/null 2>&1 || return 1
  git clone --depth 1 --branch "$PHPVER_BRANCH" "$PHPVER_REPO" "$dest"
}

phpver_install__fetch_with_curl() {
  local dest="$1"
  command -v curl >/dev/null 2>&1 || return 1

  mkdir -p "$dest/lib" "$dest/bin" "$dest/completions" "$dest/tools"
  curl -fsSL "$PHPVER_RAW_BASE/install.sh" -o "$dest/install.sh"
  curl -fsSL "$PHPVER_RAW_BASE/lib/phpver.sh" -o "$dest/lib/phpver.sh"
  curl -fsSL "$PHPVER_RAW_BASE/bin/phpver" -o "$dest/bin/phpver"
  curl -fsSL "$PHPVER_RAW_BASE/completions/_phpver" -o "$dest/completions/_phpver" 2>/dev/null || true
  chmod +x "$dest/install.sh" "$dest/bin/phpver"
}

main() {
  phpver_install__require_macos

  if ! command -v brew >/dev/null 2>&1; then
    printf 'phpver install: warning: Homebrew not found. Install from https://brew.sh before using phpver.\n' >&2
  fi

  local tmp=""
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t phpver-install)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  printf '==> Downloading phpver (%s)...\n' "$PHPVER_BRANCH"

  if phpver_install__fetch_with_git "$tmp/phpver"; then
    :
  elif phpver_install__fetch_with_curl "$tmp/phpver"; then
    :
  else
    phpver_install__die "need git or curl to download phpver"
  fi

  [[ -f "$tmp/phpver/install.sh" ]] || phpver_install__die "download incomplete (missing install.sh)"

  PHPVER_REPO_DIR="$tmp/phpver" bash "$tmp/phpver/install.sh"
}

main "$@"
