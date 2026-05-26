---
name: phpver
version: 1.0.0
description: >-
  Operates phpver, the macOS Homebrew-based PHP version manager (nvm-style).
  Load when the task involves phpver, .php-version, .php-extensions, PECL on
  macOS, switching PHP 8.x, Laravel PHP setup with Homebrew, or errors from
  phpver ext install/sync/uninstall/cleanup. Portable agent skill — see
  ai/skills/README.md for integration.
---

# phpver (macOS) — agent skill

Instructions for automated assistants (any vendor). Human docs: repo [README.md](../../../README.md).

phpver manages PHP via **Homebrew `php@X.Y` bottles** — no PHP compile from source.

- **Repo:** https://github.com/robertoporceddu/phpver
- **Install location:** `~/.phpver/` (`lib/phpver.sh`, `bin/phpver`)
- **Shell:** zsh sources hooks; CLI runs `~/.phpver/bin/phpver` (bash)

## Preconditions

Before running phpver commands, verify:

```bash
command -v phpver && phpver version
command -v brew
uname -s   # must be Darwin
```

If missing:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)"
source ~/.zshrc
```

Or: `git clone https://github.com/robertoporceddu/phpver.git && cd phpver && ./install.sh && source ~/.zshrc`.

After updating the repo, copy artifacts:

```bash
cp lib/phpver.sh ~/.phpver/lib/phpver.sh
cp bin/phpver ~/.phpver/bin/phpver
source ~/.zshrc
```

## Decision tree

```
User needs PHP version only?
  → phpver install <ver> → phpver use <ver> -g or -p

User needs PECL extension (imagick, redis, xdebug)?
  → brew deps if needed → phpver ext install <ext> [-p]

Team reproduces env from repo?
  → read .php-version + .php-extensions → phpver use X.Y -p → phpver ext sync

Broken extension / ini warnings after uninstall?
  → phpver ext cleanup <ext> [ver] → grep imagick in conf.d

Untrusted git clone?
  → inspect .php-extensions first; consider PHPVER_AUTO_EXT_SYNC=0
```

## PHP versions

Versions normalize to `MAJOR.MINOR` (`8.4.21` → `8.4`).

| Goal | Command |
|------|---------|
| Install PHP | `phpver install 8.4` |
| Shell only | `phpver use 8.4` |
| Global default | `phpver use 8.4 -g` → writes `~/.phpver/default` |
| Project file | `phpver use 8.4 -p` → writes `.php-version` next to project root logic |
| List / current | `phpver list`, `phpver current`, `phpver which` |

**`.php-version`:** one line, e.g. `8.4`. On `cd`, zsh hook activates it (overrides global default).

**Agent rule:** run `phpver` from the **project root** (where `.php-version` lives) when using `-p` or `ext sync`.

## Extensions

Built into Homebrew PHP (usually no PECL): gd, intl, mbstring, curl, zip, openssl, pdo, xml, bcmath, fileinfo.

Common PECL + brew deps:

| PECL | Homebrew dep |
|------|----------------|
| imagick | `imagemagick` |
| redis | `redis` |
| memcached / memcache | `libmemcached` |
| xdebug | (none) |

| Goal | Command |
|------|---------|
| List modules | `phpver ext list [8.4]` |
| Install (active version) | `phpver ext install imagick` |
| Install for version | `phpver ext install imagick 8.1` |
| Install + project manifest | `phpver ext install imagick -p` |
| Uninstall | `phpver ext uninstall imagick [-p]` |
| Fix stale ini | `phpver ext cleanup imagick [8.1]` |
| Apply `.php-extensions` | `phpver ext sync` |

**`.php-extensions`:** one PECL name per line; `#` comments. Read **only beside `.php-version`** (not `~/.php-extensions` from subdirs).

**Auto-sync:** on `cd`, extensions install automatically unless `PHPVER_AUTO_EXT_SYNC=0` in `~/.zshrc`.

## Standard workflows

### New Laravel project

```bash
cd /path/to/project
phpver install 8.4
phpver use 8.4 -p
phpver ext list
# Only if needed:
phpver ext install imagick -p
php -v
php -m | grep -i intl
```

### Onboard existing repo

```bash
cd /path/to/project
cat .php-version .php-extensions 2>/dev/null
phpver install "$(cat .php-version)"
phpver use "$(cat .php-version)" -p
phpver ext sync
phpver ext list
```

### Upgrade phpver on user machine

```bash
cd /path/to/phpver-clone && git pull
cp lib/phpver.sh ~/.phpver/lib/phpver.sh
cp bin/phpver ~/.phpver/bin/phpver
source ~/.zshrc
phpver version
```

## Agent execution rules

1. **Prefer `phpver` over raw `pecl`** when phpver is installed — it sets `PECL_PHPBIN` and handles ini cleanup on uninstall.
2. **Use explicit version** (`phpver ext install imagick 8.1`) when the project `.php-version` differs from the global default.
3. **Diagnose with** `phpver ext list`, `php --ini`, `type phpver` — not only `php -m` (warnings pollute output).
4. **Do not** run `phpver ext sync` on untrusted repos without reading `.php-extensions` first.
5. **macOS only** — do not suggest phpver on Linux/WSL; use system packages or other version managers instead.
6. **Never** `git config --global` or force-push unless the user explicitly asks.

## Common failures

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| Silent `phpver ext install` + exit 1 | PHP warnings broke version detection (fixed in ≥0.1.9) | Update `~/.phpver/lib/phpver.sh`; retry |
| `already loaded` + PECL 502 | Duplicate ini + network | `phpver ext cleanup imagick`; remove duplicate `conf.d` ini |
| `Unable to load imagick.so` after uninstall | Stale ini | `phpver ext cleanup imagick <ver>` |
| Sync from `~/.php-extensions` in wrong project | Old home manifest | `rm ~/.php-extensions`; use `-p` in project root |
| `[missing]` for gd/curl in ext list | `php -m` polluted by warnings | Use `phpver ext list` (≥0.1.10) |

Full troubleshooting: [reference.md](reference.md)

## Security (agent awareness)

- `.php-extensions` in a cloned repo can trigger **brew/pecl install on `cd`** (auto-sync).
- Treat project manifests as **trusted config**; review before sync on unknown repos.
- Recommend `PHPVER_AUTO_EXT_SYNC=0` for users who frequently clone untrusted code.

## Related docs

- User-facing guide: [README.md](../../../README.md) (repo root)
- Troubleshooting commands: [reference.md](reference.md)
