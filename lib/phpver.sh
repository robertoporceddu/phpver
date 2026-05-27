# shellcheck shell=bash
# phpver — PHP version manager for macOS (Homebrew bottles, no compile).
# Sourced from zsh (.zshrc) and run via bash (bin/phpver); avoid bash-only regex captures.

PHPVER_VERSION="0.2.2"
PHPVER_ROOT="${PHPVER_ROOT:-$HOME/.phpver}"
PHPVER_VERSIONS_DIR="$PHPVER_ROOT/versions"
PHPVER_DEFAULT_FILE="$PHPVER_ROOT/default"
PHPVER_PROJECT_VERSION_FILE=".php-version"
PHPVER_PROJECT_EXTENSIONS_FILE=".php-extensions"
PHPVER_AUTO_EXT_SYNC="${PHPVER_AUTO_EXT_SYNC:-1}"
PHPVER_REPO_DIR="${PHPVER_REPO_DIR:-}"

phpver__die() {
  printf 'phpver: %s\n' "$*" >&2
  return 1
}

phpver__info() {
  printf 'phpver: %s\n' "$*"
}

phpver__require_brew() {
  command -v brew >/dev/null 2>&1 || phpver__die "Homebrew is required (https://brew.sh)"
}

phpver__require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || phpver__die "phpver currently supports macOS only"
}

phpver__normalize_version() {
  local input="$1"
  local ver="$input"
  local major minor rest

  if [[ -z "$ver" ]]; then
    phpver__die "invalid version: (empty) (expected e.g. 8.4 or 8.4.20)"
    return 1
  fi

  # Portable in bash + zsh (do not use BASH_REMATCH — breaks when sourced from zsh)
  ver="${ver//[^0-9.]/}"
  major="${ver%%.*}"
  rest="${ver#*.}"
  minor="${rest%%.*}"

  if [[ -z "$major" || -z "$minor" ]]; then
    phpver__die "invalid version: $input (expected e.g. 8.4 or 8.4.20)"
    return 1
  fi

  echo "${major}.${minor}"
}

phpver__brew_formula() {
  local short="$1"
  echo "php@${short}"
}

phpver__version_path() {
  echo "$PHPVER_VERSIONS_DIR/$1"
}

phpver__formula_installed() {
  brew ls --versions "$1" &>/dev/null
}

phpver__link_version() {
  local short="$1"
  local formula="$2"
  local prefix
  prefix="$(brew --prefix "$formula" 2>/dev/null)" || return 1
  mkdir -p "$PHPVER_VERSIONS_DIR"
  ln -sfn "$prefix" "$(phpver__version_path "$short")"
}

phpver__path_for_version() {
  local short="$1"
  local dir
  dir="$(phpver__version_path "$short")"
  if [[ -d "$dir/bin" ]]; then
    echo "$dir/bin"
    return 0
  fi
  return 1
}

phpver__path_remove_prefix() {
  local remove="$1"
  local result="" p
  local old_ifs="$IFS"
  IFS=':'
  for p in $PATH; do
    [[ "$p" == "$remove" ]] && continue
    [[ -z "$p" ]] && continue
    if [[ -z "$result" ]]; then
      result="$p"
    else
      result="$result:$p"
    fi
  done
  IFS="$old_ifs"
  echo "$result"
}

phpver__prepend_path() {
  local bin_path="$1"
  if [[ -n "${PHPVER_ACTIVE_BIN:-}" ]]; then
    PATH="$(phpver__path_remove_prefix "$PHPVER_ACTIVE_BIN")"
  fi
  export PHPVER_ACTIVE_BIN="$bin_path"
  export PATH="${bin_path}:${PATH}"
  hash -r 2>/dev/null || true
}

phpver__project_version_path() {
  echo "$PWD/$PHPVER_PROJECT_VERSION_FILE"
}

phpver__read_php_version_file() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/$PHPVER_PROJECT_VERSION_FILE" ]]; then
      local content
      content="$(<"$dir/$PHPVER_PROJECT_VERSION_FILE")"
      content="${content//[[:space:]]/}"
      printf '%s' "$content"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

phpver__write_project_version() {
  local ver="$1"
  local path
  path="$(phpver__project_version_path)"
  printf '%s\n' "$ver" >"$path"
  phpver__info "wrote $path"
}

phpver__find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/$PHPVER_PROJECT_VERSION_FILE" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

phpver__project_extensions_path() {
  local root=""
  if root="$(phpver__find_project_root 2>/dev/null)"; then
    echo "$root/$PHPVER_PROJECT_EXTENSIONS_FILE"
  else
    echo "$PWD/$PHPVER_PROJECT_EXTENSIONS_FILE"
  fi
}

phpver__find_project_extensions_file() {
  local dir="" root=""

  # With .php-version in tree: only use .php-extensions beside that file (not ~/.php-extensions).
  if root="$(phpver__find_project_root 2>/dev/null)"; then
    if [[ -f "$root/$PHPVER_PROJECT_EXTENSIONS_FILE" ]]; then
      echo "$root/$PHPVER_PROJECT_EXTENSIONS_FILE"
      return 0
    fi
    return 1
  fi

  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/$PHPVER_PROJECT_EXTENSIONS_FILE" ]]; then
      if [[ "$dir" == "$HOME" && "$PWD" != "$HOME" ]]; then
        return 1
      fi
      echo "$dir/$PHPVER_PROJECT_EXTENSIONS_FILE"
      return 0
    fi
    [[ "$dir" == "$HOME" ]] && return 1
    dir="$(dirname "$dir")"
  done
  return 1
}

phpver__normalize_extension_name() {
  local name="${1:-}"
  # No external tr(1): PATH may be minimal after pecl; must work when sourced from zsh
  name="${name//[[:space:]]/}"
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    echo "${name:l}"
  else
    printf '%s' "$name" | /usr/bin/tr '[:upper:]' '[:lower:]'
  fi
}

phpver__append_project_extension() {
  local ext path line existing
  ext="$(phpver__normalize_extension_name "$1")"
  [[ -n "$ext" ]] || return 1

  path="$(phpver__project_extensions_path)"

  if [[ ! -f "$path" ]]; then
    printf '%s\n' "# PECL extensions for this project (phpver)" "$ext" >"$path"
    phpver__info "created $path"
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    existing="$(phpver__normalize_extension_name "$line")"
    [[ -z "$existing" ]] && continue
    if [[ "$existing" == "$ext" ]]; then
      phpver__info "$ext already listed in $path"
      return 0
    fi
  done <"$path"

  echo "$ext" >>"$path"
  phpver__info "added $ext to $path"
}

phpver__remove_project_extension() {
  local ext path tmp line existing found=0

  ext="$(phpver__normalize_extension_name "$1")"
  [[ -n "$ext" ]] || return 1

  path="$(phpver__project_extensions_path)"

  if [[ ! -f "$path" ]]; then
    phpver__info "no $path to update"
    return 0
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/phpver-extensions.XXXXXX")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    existing="$(phpver__normalize_extension_name "${line%%#*}")"
    if [[ -n "$existing" && "$existing" == "$ext" ]]; then
      found=1
      continue
    fi
    printf '%s\n' "$line"
  done <"$path" >"$tmp"

  if [[ "$found" -eq 1 ]]; then
    mv "$tmp" "$path"
    phpver__info "removed $ext from $path"
  else
    rm -f "$tmp"
    phpver__info "$ext not listed in $path"
  fi
}

phpver__php_quiet_ini_flags() {
  echo "-d" "display_errors=0" "-d" "display_startup_errors=0"
}

phpver__php_version_string() {
  local php_bin="$1"
  "$php_bin" $(phpver__php_quiet_ini_flags) -r 'echo PHP_VERSION;' 2>/dev/null
}

phpver__php_ini_scan_dir() {
  local php_bin="$1"
  "$php_bin" $(phpver__php_quiet_ini_flags) -r 'echo PHP_CONFIG_FILE_SCAN_DIR;' 2>/dev/null | head -1
}

phpver__php_module_list() {
  local php_bin="$1"
  "$php_bin" $(phpver__php_quiet_ini_flags) -r '
    foreach (get_loaded_extensions() as $e) {
      echo $e, "\n";
    }
  ' 2>/dev/null | LC_ALL=C sort -f
}

phpver__ext_is_loaded() {
  local php_bin="$1"
  local ext="$2"
  [[ "$ext" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || return 1
  "$php_bin" $(phpver__php_quiet_ini_flags) -r "exit(extension_loaded('${ext}') ? 0 : 1);" 2>/dev/null
}

phpver__ext_ini_references() {
  local php_bin="$1"
  local ext="$2"
  local ini_dir f

  ext="$(phpver__normalize_extension_name "$ext")"
  ini_dir="$(phpver__php_ini_scan_dir "$php_bin")" || return 1
  [[ -d "$ini_dir" ]] || return 1

  for f in "$ini_dir"/*; do
    [[ -f "$f" ]] || continue
    if grep -qiE "(^|[[:space:]])(zend_)?extension[[:space:]]*=[[:space:]]*\"?${ext}(\.so)?\"?" "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

phpver__ext_cleanup_ini_files() {
  local php_bin="$1"
  local ext="$2"
  local ini_dir f removed=0

  ext="$(phpver__normalize_extension_name "$ext")"
  ini_dir="$(phpver__php_ini_scan_dir "$php_bin")" || return 0
  [[ -d "$ini_dir" ]] || return 0

  for f in "$ini_dir"/*; do
    [[ -e "$f" ]] || continue
    if grep -qiE "(^|[[:space:]])(zend_)?extension[[:space:]]*=[[:space:]]*\"?${ext}(\.so)?\"?" "$f" 2>/dev/null; then
      rm -f "$f"
      phpver__info "removed stale ini: $f"
      removed=$((removed + 1))
    fi
  done

  [[ "$removed" -gt 0 ]]
}

phpver__resolve_ext_version_for_project() {
  local arg_ver="${1:-}"
  local from_php_version=""

  from_php_version="$(phpver__read_php_version_file 2>/dev/null)" || true
  if [[ -n "$from_php_version" ]]; then
    phpver__normalize_version "$from_php_version"
    return $?
  fi

  phpver__resolve_ext_version "$arg_ver"
}

phpver__ext_all_project_extensions_loaded() {
  local php_bin="$1"
  local file="$2"
  local line ext

  [[ -f "$file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    ext="$(phpver__normalize_extension_name "$line")"
    [[ -z "$ext" ]] && continue
    if ! phpver__ext_is_loaded "$php_bin" "$ext"; then
      return 1
    fi
  done <"$file"

  return 0
}

phpver_install() {
  local ver raw_short formula prefix
  raw_short="$(phpver__normalize_version "$1")" || return 1
  ver="$raw_short"
  phpver__require_macos || return 1
  phpver__require_brew || return 1

  formula="$(phpver__brew_formula "$ver")"

  if ! brew info "$formula" &>/dev/null; then
    phpver__die "Homebrew formula not found: $formula (try: brew search php)"
    return 1
  fi

  if phpver__formula_installed "$formula"; then
    phpver__info "$formula already installed via Homebrew"
  else
    phpver__info "installing $formula (prebuilt bottle)..."
    brew install "$formula" || return 1
  fi

  phpver__link_version "$ver" "$formula" || return 1
  prefix="$(brew --prefix "$formula")"

  if ! command -v composer >/dev/null 2>&1; then
    phpver__info "composer not found; install with: brew install composer"
  fi

  phpver__info "linked $ver -> $prefix"
  phpver__info "run: phpver use $ver"
}

phpver_uninstall() {
  local ver formula
  ver="$(phpver__normalize_version "$1")" || return 1
  formula="$(phpver__brew_formula "$ver")"

  rm -f "$(phpver__version_path "$ver")"

  local default_ver=""
  [[ -f "$PHPVER_DEFAULT_FILE" ]] && default_ver="$(<"$PHPVER_DEFAULT_FILE")"
  if [[ "$default_ver" == "$ver" ]]; then
    rm -f "$PHPVER_DEFAULT_FILE"
  fi

  phpver__info "removed phpver link for $ver"
  phpver__info "Homebrew package $formula is still installed."
  phpver__info "To remove it: brew uninstall $formula"
}

# Activate a version on PATH. Prints only when the version actually changes.
# source: "project" | "global" | "" (manual phpver use)
phpver__activate() {
  local ver="$1"
  local source="${2:-}"
  local bin_path msg

  bin_path="$(phpver__path_for_version "$ver")" || {
    phpver__die "version $ver is not installed (phpver install $ver)"
    return 1
  }

  if [[ "${PHPVER_ACTIVE_VERSION:-}" == "$ver" && "${PHPVER_ACTIVE_BIN:-}" == "$bin_path" ]]; then
    return 0
  fi

  phpver__prepend_path "$bin_path"
  PHPVER_ACTIVE_VERSION="$ver"

  msg="$(phpver__php_version_string "$bin_path/php")"
  case "$source" in
    project) phpver__info "using PHP $msg ($ver) — from .php-version" ;;
    global) phpver__info "using PHP $msg ($ver) — global default" ;;
    *) phpver__info "using PHP $msg ($ver)" ;;
  esac
}

phpver_use() {
  local ver global=false project=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -g | --global) global=true; shift ;;
      -p | --project) project=true; shift ;;
      -*) phpver__die "unknown option: $1"; return 1 ;;
      *)
        ver="$(phpver__normalize_version "$1")" || return 1
        shift
        ;;
    esac
  done

  if [[ -z "${ver:-}" ]]; then
    if [[ -f "$PHPVER_DEFAULT_FILE" ]]; then
      ver="$(<"$PHPVER_DEFAULT_FILE")"
    else
      phpver__die "usage: phpver use <version> [-g|--global] [-p|--project]"
      return 1
    fi
  fi

  ver="$(phpver__normalize_version "$ver")" || return 1
  phpver__activate "$ver" "" || return 1

  if $project; then
    phpver__write_project_version "$ver"
  fi

  if $global; then
    mkdir -p "$PHPVER_ROOT"
    echo "$ver" >"$PHPVER_DEFAULT_FILE"
    phpver__info "global default set to $ver"
  fi
}

phpver_list() {
  phpver__info "phpver versions:"
  if [[ -d "$PHPVER_VERSIONS_DIR" ]]; then
    local name target
    for name in "$PHPVER_VERSIONS_DIR"/*; do
      [[ -e "$name" ]] || continue
      name="$(basename "$name")"
      target="$(readlink "$(phpver__version_path "$name")" 2>/dev/null || true)"
      printf '  %s -> %s\n' "$name" "${target:-?}"
    done
  else
    printf '  (none)\n'
  fi

  echo ""
  phpver__info "Homebrew PHP formulas:"
  brew list --formula 2>/dev/null | grep -E '^php(@|$)' || true

  if [[ -f "$PHPVER_DEFAULT_FILE" ]]; then
    echo ""
    phpver__info "global default: $(<"$PHPVER_DEFAULT_FILE")"
  fi

  if [[ -f "$(phpver__project_version_path)" ]]; then
    echo ""
    phpver__info "project ($(phpver__project_version_path)): $(<"$(phpver__project_version_path)")"
  fi

  if [[ -f "$(phpver__project_extensions_path)" ]]; then
    echo ""
    phpver__info "project extensions ($(phpver__project_extensions_path)):"
    grep -v '^[[:space:]]*#' "$(phpver__project_extensions_path)" 2>/dev/null | grep -v '^[[:space:]]*$' | sed 's/^/  /' || true
  fi
}

phpver_current() {
  if command -v php >/dev/null 2>&1; then
    php -r 'echo PHP_VERSION, "\n";'
  else
    phpver__die "php not found in PATH"
    return 1
  fi
}

phpver_which() {
  command -v php || phpver__die "php not found in PATH"
}

phpver_version() {
  echo "phpver $PHPVER_VERSION"
}

# --- Extensions (PECL + built-in via Homebrew PHP) ---

phpver__bin_dir_for_version() {
  local short="$1"
  local bin_dir formula prefix

  bin_dir="$(phpver__path_for_version "$short" 2>/dev/null || true)"
  if [[ -n "$bin_dir" && -d "$bin_dir" ]]; then
    echo "$bin_dir"
    return 0
  fi

  formula="$(phpver__brew_formula "$short")"
  if phpver__formula_installed "$formula"; then
    prefix="$(brew --prefix "$formula" 2>/dev/null)" || return 1
    if [[ -d "$prefix/bin" ]]; then
      echo "$prefix/bin"
      return 0
    fi
  fi

  return 1
}

phpver__php_bin_for_version() {
  local short="$1"
  local bin_dir
  bin_dir="$(phpver__bin_dir_for_version "$short")" || return 1
  if [[ -x "$bin_dir/php" ]]; then
    echo "$bin_dir/php"
    return 0
  fi
  phpver__die "php binary not found for version $short"
  return 1
}

phpver__pecl_bin_for_version() {
  local short="$1"
  local bin_dir
  bin_dir="$(phpver__bin_dir_for_version "$short")" || return 1
  if [[ -x "$bin_dir/pecl" ]]; then
    echo "$bin_dir/pecl"
    return 0
  fi
  phpver__die "pecl not found for version $short"
  return 1
}

phpver__php_ini_dir_for_version() {
  local short="$1"
  local php_bin
  php_bin="$(phpver__php_bin_for_version "$short")" || return 1
  phpver__php_ini_scan_dir "$php_bin"
}

phpver__resolve_ext_version() {
  local arg_ver="${1:-}"
  local from_file="" php_bin="" full_ver=""

  if [[ -n "$arg_ver" ]]; then
    phpver__normalize_version "$arg_ver"
    return $?
  fi

  from_file="$(phpver__read_php_version_file 2>/dev/null)" || true
  if [[ -n "$from_file" ]]; then
    phpver__normalize_version "$from_file"
    return $?
  fi

  if [[ -n "${PHPVER_ACTIVE_BIN:-}" && -x "${PHPVER_ACTIVE_BIN}/php" ]]; then
    php_bin="${PHPVER_ACTIVE_BIN}/php"
  elif command -v php >/dev/null 2>&1; then
    php_bin="$(command -v php)"
  else
    phpver__die "no PHP in PATH; run phpver use <version> or pass a version argument"
    return 1
  fi

  full_ver="$(phpver__php_version_string "$php_bin")"
  [[ -n "$full_ver" ]] || {
    phpver__die "could not read PHP version from $php_bin"
    return 1
  }
  phpver__normalize_version "$full_ver"
}

phpver__ext_brew_packages() {
  local ext="$1"
  case "$ext" in
    imagick) echo "imagemagick" ;;
    redis) echo "redis" ;;
    memcached) echo "libmemcached" ;;
    memcache) echo "libmemcached" ;;
    xdebug) echo "" ;;
    *) echo "" ;;
  esac
}

phpver__ext_install_brew_deps() {
  local ext="$1"
  local pkg
  phpver__require_brew || return 1

  for pkg in $(phpver__ext_brew_packages "$ext"); do
    [[ -z "$pkg" ]] && continue
    if phpver__formula_installed "$pkg"; then
      phpver__info "$pkg already installed"
    else
      phpver__info "installing brew dependency: $pkg"
      brew install "$pkg" || return 1
    fi
  done
}

phpver__laravel_extensions() {
  echo "bcmath ctype curl dom fileinfo gd intl json mbstring openssl pcre pdo tokenizer xml zip"
}

phpver__ext_install_pecl() {
  local ver="$1"
  local ext="$2"
  local php_bin pecl_bin attempt

  ext="$(phpver__normalize_extension_name "$ext")"

  php_bin="$(phpver__php_bin_for_version "$ver")" || return 1
  pecl_bin="$(phpver__pecl_bin_for_version "$ver")" || return 1

  if ! phpver__bin_dir_for_version "$ver" >/dev/null; then
    phpver__die "version $ver not found (phpver install $ver)"
    return 1
  fi

  if phpver__ext_is_loaded "$php_bin" "$ext"; then
    phpver__info "extension '$ext' already loaded for PHP $(phpver__php_version_string "$php_bin") ($ver)"
    return 0
  fi

  phpver__ext_install_brew_deps "$ext" || return 1

  for attempt in 1 2 3; do
    if PECL_PHPBIN="$php_bin" "$pecl_bin" install -f "$ext"; then
      return 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
      phpver__info "PECL install failed (attempt $attempt/3), retrying in 3s..."
      sleep 3
    fi
  done

  phpver__info "PECL download failed (pecl.php.net may be down). Retry later or: pecl install $ext"
  return 1
}

phpver__ext_uninstall_pecl() {
  local ver="$1"
  local ext="$2"
  local php_bin pecl_bin loaded=0 ini_ref=0

  php_bin="$(phpver__php_bin_for_version "$ver")" || return 1
  pecl_bin="$(phpver__pecl_bin_for_version "$ver")" || return 1

  if ! phpver__bin_dir_for_version "$ver" >/dev/null; then
    phpver__die "version $ver not found (phpver install $ver)"
    return 1
  fi

  ext="$(phpver__normalize_extension_name "$ext")"

  phpver__ext_is_loaded "$php_bin" "$ext" && loaded=1
  phpver__ext_ini_references "$php_bin" "$ext" && ini_ref=1

  if [[ "$loaded" -eq 0 && "$ini_ref" -eq 0 ]]; then
    phpver__info "extension '$ext' is not installed for PHP $ver"
    return 0
  fi

  if [[ "$loaded" -eq 1 ]]; then
    phpver__info "uninstalling PECL extension '$ext' for PHP $(phpver__php_version_string "$php_bin") ($ver)"
    PECL_PHPBIN="$php_bin" printf 'y\n' | "$pecl_bin" uninstall "$ext" 2>/dev/null \
      || PECL_PHPBIN="$php_bin" printf 'y\n' | "$pecl_bin" uninstall "$ext"
  elif [[ "$ini_ref" -eq 1 ]]; then
    phpver__info "extension '$ext' has stale ini entries; running PECL uninstall + cleanup"
    PECL_PHPBIN="$php_bin" printf 'y\n' | "$pecl_bin" uninstall "$ext" 2>/dev/null || true
  fi

  if phpver__ext_cleanup_ini_files "$php_bin" "$ext"; then
    :
  elif [[ "$ini_ref" -eq 1 ]]; then
    phpver__info "no ini files removed (check: php --ini)"
  fi
}

phpver__ext_sync_project() {
  local arg_ver="${1:-}"
  local ver php_bin bin_dir file
  local count_installed=0 count_skipped=0 count_failed=0
  local line ext

  [[ -n "${PHPVER_EXT_SYNCING:-}" ]] && return 0

  file="$(phpver__find_project_extensions_file 2>/dev/null)" || {
    return 0
  }

  export PHPVER_EXT_SYNCING=1

  ver="$(phpver__resolve_ext_version_for_project "$arg_ver")" || {
    unset PHPVER_EXT_SYNCING
    return 1
  }

  php_bin="$(phpver__php_bin_for_version "$ver")" || {
    unset PHPVER_EXT_SYNCING
    return 1
  }

  bin_dir="$(phpver__bin_dir_for_version "$ver")" || {
    unset PHPVER_EXT_SYNCING
    return 1
  }

  phpver__prepend_path "$bin_dir"

  if phpver__ext_all_project_extensions_loaded "$php_bin" "$file"; then
    unset PHPVER_EXT_SYNCING
    return 0
  fi

  phpver__info "syncing extensions from $file for PHP $(phpver__php_version_string "$php_bin") ($ver)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    ext="$(phpver__normalize_extension_name "$line")"
    [[ -z "$ext" ]] && continue

    if phpver__ext_is_loaded "$php_bin" "$ext"; then
      phpver__info "  [skip] $ext (already loaded)"
      count_skipped=$((count_skipped + 1))
      continue
    fi

    phpver__info "  [install] $ext"
    if phpver__ext_install_pecl "$ver" "$ext"; then
      count_installed=$((count_installed + 1))
    else
      phpver__info "  [failed] $ext"
      count_failed=$((count_failed + 1))
    fi
  done <"$file"

  phpver__info "sync complete: installed=$count_installed skipped=$count_skipped failed=$count_failed"
  unset PHPVER_EXT_SYNCING
  [[ "$count_failed" -eq 0 ]]
}

phpver_ext_list() {
  local ver php_bin laravel ext modules
  ver="$(phpver__resolve_ext_version "${1:-}")" || return 1
  php_bin="$(phpver__php_bin_for_version "$ver")" || return 1

  modules="$(phpver__php_module_list "$php_bin")"

  phpver__info "PHP $(phpver__php_version_string "$php_bin") ($ver) — loaded extensions:"
  echo ""

  if [[ -n "$modules" ]]; then
    printf '%s\n' "$modules"
  else
    phpver__info "(could not list modules — check php startup errors with: php --ini)"
  fi

  echo ""
  phpver__info "Laravel common extensions:"
  for ext in $(phpver__laravel_extensions); do
    if printf '%s\n' "$modules" | grep -qi "^${ext}$"; then
      printf '  [ok] %s\n' "$ext"
    else
      printf '  [missing] %s\n' "$ext"
    fi
  done

  local ini_dir
  ini_dir="$(phpver__php_ini_dir_for_version "$ver" 2>/dev/null || true)"
  if [[ -n "$ini_dir" ]]; then
    echo ""
    phpver__info "config scan dir: $ini_dir"
  fi

  local ext_file
  ext_file="$(phpver__find_project_extensions_file 2>/dev/null || true)"
  if [[ -n "$ext_file" ]]; then
    echo ""
    phpver__info "project manifest ($ext_file):"
    grep -v '^[[:space:]]*#' "$ext_file" 2>/dev/null | grep -v '^[[:space:]]*$' | sed 's/^/  /' || true
  fi
}

phpver_ext_install() {
  local project=false
  local pecl_name="" ver=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p | --project) project=true; shift ;;
      -*) phpver__die "unknown option: $1"; return 1 ;;
      *)
        if [[ -z "$pecl_name" ]]; then
          pecl_name="$1"
        elif [[ -z "$ver" ]]; then
          ver="$1"
        else
          phpver__die "too many arguments"
          return 1
        fi
        shift
        ;;
    esac
  done

  [[ -n "$pecl_name" ]] || {
    phpver__die "usage: phpver ext install <extension> [version] [-p|--project]"
    return 1
  }

  ver="$(phpver__resolve_ext_version "$ver")" || return 1
  phpver__require_macos || return 1
  phpver__require_brew || return 1

  local php_bin
  php_bin="$(phpver__php_bin_for_version "$ver")" || return 1

  phpver__info "installing PECL extension '$pecl_name' for PHP $(phpver__php_version_string "$php_bin") ($ver)"

  if ! phpver__ext_install_pecl "$ver" "$pecl_name"; then
    phpver__die "failed to install $pecl_name"
    return 1
  fi

  if $project; then
    phpver__append_project_extension "$pecl_name"
  fi

  phpver__info "done. verify with: phpver ext list $ver | grep -i $pecl_name"
}

phpver_ext_uninstall() {
  local project=false
  local pecl_name="" ver=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p | --project) project=true; shift ;;
      -*) phpver__die "unknown option: $1"; return 1 ;;
      *)
        if [[ -z "$pecl_name" ]]; then
          pecl_name="$1"
        elif [[ -z "$ver" ]]; then
          ver="$1"
        else
          phpver__die "too many arguments"
          return 1
        fi
        shift
        ;;
    esac
  done

  [[ -n "$pecl_name" ]] || {
    phpver__die "usage: phpver ext uninstall <extension> [version] [-p|--project]"
    return 1
  }

  ver="$(phpver__resolve_ext_version "$ver")" || return 1
  phpver__require_macos || return 1
  phpver__require_brew || return 1

  if $project; then
    phpver__remove_project_extension "$pecl_name"
  fi

  if ! phpver__ext_uninstall_pecl "$ver" "$pecl_name"; then
    phpver__die "failed to uninstall $pecl_name"
    return 1
  fi

  phpver__info "done. verify with: phpver ext list $ver | grep -i $pecl_name"
}

phpver_ext_cleanup() {
  local pecl_name="${1:-}" ver="${2:-}"
  local php_bin

  [[ -n "$pecl_name" ]] || {
    phpver__die "usage: phpver ext cleanup <extension> [version]"
    return 1
  }

  ver="$(phpver__resolve_ext_version "$ver")" || return 1
  php_bin="$(phpver__php_bin_for_version "$ver")" || return 1

  if phpver__ext_cleanup_ini_files "$php_bin" "$pecl_name"; then
    phpver__info "done. verify with: php -m 2>&1 | head"
  else
    phpver__info "no stale ini found for $pecl_name (PHP $ver)"
  fi
}

phpver_ext_sync() {
  local ver="${1:-}"

  phpver__require_macos || return 1
  phpver__require_brew || return 1

  local file
  file="$(phpver__find_project_extensions_file 2>/dev/null)" || {
    phpver__info "no $PHPVER_PROJECT_EXTENSIONS_FILE found in project tree"
    return 0
  }

  phpver__ext_sync_project "$ver"
}

phpver_ext_help() {
  cat <<'EOF'
phpver ext — PHP extensions (Homebrew built-in + PECL)

Usage:
  phpver ext list [version]              List loaded extensions
  phpver ext install <ext> [version] [-p]    Install via PECL; -p writes .php-extensions
  phpver ext uninstall <ext> [version] [-p]  Uninstall via PECL; -p removes from .php-extensions
  phpver ext cleanup <ext> [version]       Remove stale extension= lines from conf.d
  phpver ext sync [version]                  Install all extensions from .php-extensions
  phpver ext help                            Show this help

Project file (.php-extensions):
  phpver ext install imagick -p            Add imagick to .php-extensions and install
  phpver ext uninstall imagick -p          Remove imagick from .php-extensions and uninstall
  phpver ext sync                          Replicate installs (also on cd if enabled)

Auto-sync on cd (default on): set PHPVER_AUTO_EXT_SYNC=0 to disable.

Common PECL extensions and Homebrew dependencies:
  imagick     -> brew install imagemagick
  redis       -> brew install redis
  memcached   -> brew install libmemcached
  xdebug      -> (no extra brew formula)

Built into Homebrew php@8.x (usually no action needed):
  gd, intl, mbstring, curl, zip, openssl, pdo, xml, bcmath, fileinfo, ...

Examples:
  phpver use 8.4
  phpver ext list
  phpver use 8.4 -p
  phpver ext install imagick -p
  phpver ext uninstall imagick -p
  phpver ext sync
  phpver ext install redis 8.3
EOF
}

phpver_ext() {
  local sub="${1:-help}"
  shift || true

  case "$sub" in
    list | ls) phpver_ext_list "${1:-}" ;;
    install | i) phpver_ext_install "$@" ;;
    uninstall | un) phpver_ext_uninstall "$@" ;;
    cleanup) phpver_ext_cleanup "$@" ;;
    sync) phpver_ext_sync "${1:-}" ;;
    help | -h | --help) phpver_ext_help ;;
    "") phpver_ext_help ;;
    *) phpver__die "unknown ext command: $sub (phpver ext help)"; return 1 ;;
  esac
}

phpver_help() {
  cat <<'EOF'
phpver — PHP version manager for macOS (Homebrew)

Usage:
  phpver install <version>     Install PHP via Homebrew and register (e.g. 8.4)
  phpver uninstall <version>   Remove phpver link (brew package kept)
  phpver use <version>         Activate version in current shell
  phpver use <version> -g      Set global default (~/.phpver/default)
  phpver use <version> -p      Write .php-version in current directory (project)
  phpver list                  List registered versions
  phpver current               Show active PHP version
  phpver which                 Show path to php binary
  phpver version               Show phpver version
  phpver ext list [version]       List PHP extensions
  phpver ext install <ext> [-p]      Install PECL extension (optional version)
  phpver ext uninstall <ext> [-p]    Uninstall PECL extension
  phpver ext sync [version]          Install extensions from .php-extensions
  phpver ext help                 Extension help
  phpver help                     Show this help

Project files:
  phpver use 8.4 -p                  Write .php-version
  phpver ext install imagick -p      Write .php-extensions and install
  phpver ext sync                    Apply .php-extensions for current project
  PHPVER_AUTO_EXT_SYNC=0             Disable auto ext sync on cd

Setup:
  Run ./install.sh from the repo, or add to ~/.zshrc:
    export PHPVER_ROOT="$HOME/.phpver"
    source /path/to/phpver/lib/phpver.sh
EOF
}

phpver() {
  local cmd="${1:-help}"
  local rc=0
  shift || true

  case "$cmd" in
    install | i) phpver_install "$@" || rc=$? ;;
    uninstall | un) phpver_uninstall "$@" || rc=$? ;;
    use | u) phpver_use "$@" || rc=$? ;;
    list | ls) phpver_list || rc=$? ;;
    current | c) phpver_current || rc=$? ;;
    which) phpver_which || rc=$? ;;
    version | -v | --version) phpver_version || rc=$? ;;
    ext) phpver_ext "$@" || rc=$? ;;
    help | -h | --help) phpver_help || rc=$? ;;
    "") phpver_help || rc=$? ;;
    *) phpver__die "unknown command: $cmd (phpver help)"; rc=1 ;;
  esac
  return "$rc"
}

# Auto-activate: .php-version in tree overrides global default (zsh on source / cd only).
# Version message is printed only when the active version changes.
phpver__auto_activate() {
  local from_file="" ver="" source=""

  from_file="$(phpver__read_php_version_file 2>/dev/null)" || true
  if [[ -n "$from_file" ]]; then
    ver="$(phpver__normalize_version "$from_file" 2>/dev/null)" || ver=""
    source="project"
  elif [[ -f "$PHPVER_DEFAULT_FILE" ]]; then
    ver="$(phpver__normalize_version "$(<"$PHPVER_DEFAULT_FILE")" 2>/dev/null)" || ver=""
    source="global"
  fi

  if [[ -n "$ver" ]]; then
    phpver__activate "$ver" "$source" 2>/dev/null || true
  fi

  if [[ "${PHPVER_AUTO_EXT_SYNC}" != "0" ]]; then
    phpver__ext_sync_project 2>/dev/null || true
  fi
}

if [[ -z "${PHPVER_NO_AUTO:-}" ]]; then
  phpver__auto_activate
fi

# Re-apply version when changing directory (zsh)
phpver__chpwd() {
  phpver__auto_activate
}

if [[ -n "${ZSH_VERSION:-}" ]]; then
  if typeset -f add-zsh-hook >/dev/null 2>&1; then
    add-zsh-hook chpwd phpver__chpwd
  else
    autoload -U add-zsh-hook 2>/dev/null && add-zsh-hook chpwd phpver__chpwd
  fi
fi
