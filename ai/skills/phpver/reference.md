# phpver — reference (agents)

Supplement to [SKILL.md](SKILL.md). Tool-agnostic diagnostic cheat sheet.

## Install paths

| Path | Purpose |
|------|---------|
| `~/.phpver/lib/phpver.sh` | Sourced from zsh (hooks) |
| `~/.phpver/bin/phpver` | Bash CLI entrypoint |
| `~/.phpver/versions/8.4` | Symlink → `$(brew --prefix php@8.4)` |
| `~/.phpver/default` | Global version string |
| `$(brew --prefix)/etc/php/8.4/conf.d/` | PECL ini drop-ins |

## zsh integration

Expected `~/.zshrc` block (marker `# phpver`):

```bash
export PHPVER_ROOT="$HOME/.phpver"
[[ -f "$PHPVER_ROOT/lib/phpver.sh" ]] && source "$PHPVER_ROOT/lib/phpver.sh"
export PATH="$PHPVER_ROOT/bin:$PATH"
```

- **Hooks** (`chpwd`, auto-activate): from sourced `lib/phpver.sh`
- **CLI commands**: handled by the `phpver` shell function defined in `lib/phpver.sh`

Verify:

```bash
type phpver          # shell function from .zshrc
~/.phpver/bin/phpver version
```

**Recommendation (avoid conflicts):** before using phpver, prefer uninstalling any Homebrew-installed “default” PHP (`brew uninstall php`) so `php` in PATH is controlled by `php@X.Y` + phpver, avoiding PATH clashes and stale dylib link errors after brew upgrades.

## Diagnostic commands

```bash
# Active PHP
phpver current
phpver which
php -v
php --ini

# Project files (from repo root)
find . -maxdepth 3 -name '.php-version' -o -name '.php-extensions' 2>/dev/null

# Imagick / ini issues
ini_dir="$(php -r 'echo PHP_CONFIG_FILE_SCAN_DIR;' 2>/dev/null)"
grep -ril imagick "$ini_dir" 2>/dev/null
ls -la "$ini_dir"/*imagick* 2>/dev/null

# Extension state
phpver ext list "$(cat .php-version 2>/dev/null)"
phpver ext cleanup imagick "$(cat .php-version 2>/dev/null)"
```

## Manual PECL (fallback)

Only if phpver is unavailable:

```bash
export PECL_PHPBIN="$(brew --prefix php@8.4)/bin/php"
"$(brew --prefix php@8.4)/bin/pecl" install imagick
```

## Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `PHPVER_ROOT` | `~/.phpver` | Install root |
| `PHPVER_AUTO_EXT_SYNC` | `1` | Auto `ext sync` on `cd` |
| `PHPVER_NO_AUTO` | unset | Set by `bin/phpver` to skip hooks for one-shot CLI |

## Version history (behavioral)

| Version | Notable fix |
|---------|-------------|
| 0.1.8 | No auto-activate on CLI; project-scoped `.php-extensions`; skip loaded PECL |
| 0.1.9 | Fix version detection when PHP prints startup warnings |
| 0.1.10 | `ext cleanup`; `get_loaded_extensions()` for `ext list`; ini cleanup on uninstall |
| 0.2.1 | Auto-activate prints version only on switch; restores global when leaving `.php-version` tree |
| 0.2.2 | Fix `phpver use` not updating current shell PATH by removing bash wrapper in `~/.zshrc` |

Check installed: `phpver version` or `head -5 ~/.phpver/lib/phpver.sh | grep PHPVER_VERSION`.
