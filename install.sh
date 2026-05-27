#!/usr/bin/env bash
# Install phpver into ~/.phpver and configure zsh.
# Local:  ./install.sh
# Remote: sh -c "$(curl -fsSL .../tools/install.sh)"  (downloads repo, then runs this file)
set -euo pipefail

if [[ -n "${PHPVER_REPO_DIR:-}" && -f "${PHPVER_REPO_DIR}/lib/phpver.sh" ]]; then
  REPO_DIR="$PHPVER_REPO_DIR"
elif [[ -n "${BASH_SOURCE[0]:-}" && -r "${BASH_SOURCE[0]}" ]]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  printf 'phpver install: cannot detect repository directory\n' >&2
  printf 'Use: sh -c "$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)"\n' >&2
  exit 1
fi

PHPVER_ROOT="${PHPVER_ROOT:-$HOME/.phpver}"
ZSHRC="${ZSHRC:-$HOME/.zshrc}"
MARKER="# phpver"
SOURCE_LINE="export PHPVER_ROOT=\"\$HOME/.phpver\"
[[ -f \"\$PHPVER_ROOT/lib/phpver.sh\" ]] && source \"\$PHPVER_ROOT/lib/phpver.sh\""

[[ "$(uname -s)" == "Darwin" ]] || {
  printf 'phpver install: macOS only\n' >&2
  exit 1
}

echo "==> Installing phpver to $PHPVER_ROOT"

mkdir -p "$PHPVER_ROOT/lib" "$PHPVER_ROOT/bin"
cp "$REPO_DIR/lib/phpver.sh" "$PHPVER_ROOT/lib/phpver.sh"
cp "$REPO_DIR/bin/phpver" "$PHPVER_ROOT/bin/phpver"
chmod +x "$PHPVER_ROOT/bin/phpver"

COMP_DIR="$PHPVER_ROOT/completions"
mkdir -p "$COMP_DIR"
if [[ -f "$REPO_DIR/completions/_phpver" ]]; then
  cp "$REPO_DIR/completions/_phpver" "$COMP_DIR/_phpver"
fi

if [[ "${PHPVER_SKIP_ZSHRC:-}" != "1" ]]; then
  if ! grep -Fq "$MARKER" "$ZSHRC" 2>/dev/null; then
    {
      echo ""
      echo "$MARKER"
      echo "$SOURCE_LINE"
      echo "export PATH=\"\$PHPVER_ROOT/bin:\$PATH\""
      echo 'fpath=("$PHPVER_ROOT/completions" $fpath)'
    } >>"$ZSHRC"
    echo "==> Added phpver to $ZSHRC"
  else
    echo "==> $ZSHRC already contains phpver block ($MARKER)"
  fi
else
  echo "==> Skipped $ZSHRC (PHPVER_SKIP_ZSHRC=1)"
fi

echo ""
echo "Done. Run:"
echo "  source \"$ZSHRC\""
echo "  phpver install 8.4"
echo "  phpver use 8.4 --global"
echo "  php -v"
echo ""
echo "One-line install (share with others):"
echo '  sh -c "$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)"'
echo ""
echo "To update an existing install:"
echo "  sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)\""
