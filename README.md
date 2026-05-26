# phpver

PHP version manager for **macOS**, inspired by [nvm](https://github.com/nvm-sh/nvm). Uses **Homebrew bottles** (prebuilt binaries) — no compiling PHP from source.

Ideal for [Laravel](https://laravel.com) and everyday PHP development.

## Requirements

| Requirement | Why |
|-------------|-----|
| **macOS** (Apple Silicon or Intel) | phpver uses Homebrew `php@X.Y` formulas |
| **[Homebrew](https://brew.sh)** | Installs and updates PHP and native deps (ImageMagick, Redis, …) |
| **zsh** + `~/.zshrc` | `cd` hooks, auto-activation of `.php-version` / `.php-extensions` |
| **Xcode Command Line Tools** (PECL only) | `xcode-select --install` — needed to build extensions like imagick |

**Recommended (avoid conflicts):** if you previously installed the Homebrew “default” PHP formula (`brew install php`), consider removing it (`brew uninstall php`) before using phpver, so `php` in your `PATH` is consistently managed via `php@X.Y` + phpver (prevents PATH clashes and stale dylib link errors after brew upgrades).

Optional but recommended:

- `brew install composer` for PHP / Laravel projects

phpver does **not** compile PHP from source: it registers Homebrew installs under `~/.phpver/versions/` and prepends the right `bin` to `PATH`.

## Installing phpver

Install with **curl** — no need to clone the repository:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)"
source ~/.zshrc
phpver version
```

This installs files under `~/.phpver/` and adds a `# phpver` block to `~/.zshrc` (once). Review before piping: [tools/install.sh](tools/install.sh).

### Installer options

| Variable | Default | Purpose |
|----------|---------|---------|
| `PHPVER_BRANCH` | `main` | Branch or tag to install |
| `PHPVER_REPO` | `https://github.com/robertoporceddu/phpver.git` | Git clone URL (when git is available) |
| `PHPVER_ROOT` | `~/.phpver` | Install directory |
| `PHPVER_SKIP_ZSHRC` | unset | Set to `1` to skip editing `~/.zshrc` |

## Installing a PHP version

Requires [Homebrew](https://brew.sh). After phpver is installed:

```bash
phpver install 8.4
phpver use 8.4 --global
php -v
```

## Update phpver

Re-run the installer (refreshes `~/.phpver`; does not duplicate the `# phpver` block in `~/.zshrc`):

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robertoporceddu/phpver/main/tools/install.sh)"
source ~/.zshrc
phpver version
```

## PHP versions

Versions are normalized to **MAJOR.MINOR** (`8.4.20` → `8.4`). Each maps to `brew install php@8.4`.

```bash
phpver install 8.4    # brew install php@8.4 + link in ~/.phpver
phpver list           # registered versions and Homebrew formulas
```

### Global default (all shells)

Sets the default in `~/.phpver/default`:

```bash
phpver use 8.4 -g
# or
phpver use 8.4 --global

phpver current
php -v
```

Every new terminal (after `source ~/.zshrc`) uses PHP 8.4 **unless** you `cd` into a directory with `.php-version` (see below).

### Project-scoped (`.php-version`)

At the repository root:

```bash
cd ~/Code/my-laravel
phpver install 8.4      # once per machine
phpver use 8.4 -p       # writes .php-version and activates 8.4 in this shell
```

Typical **`.php-version`** content (single line, no spaces):

```text
8.4
```

Or create it manually:

```bash
echo "8.4" > .php-version
```

**Behavior:** with phpver loaded, walking up the directory tree picks the nearest `.php-version`; it overrides the global default. When you leave that tree (no `.php-version` above you), phpver switches back to the global default (`phpver use … -g`). A version message is printed **only when the active PHP version changes** (not on every `cd` in the same version). Commit `.php-version` so the team shares the same major/minor.

Useful combo:

```bash
phpver use 8.4 -p -g     # project file + global default
```

### Version commands (summary)

| Command | Description |
|---------|-------------|
| `phpver install 8.4` | Install via Homebrew and register in `~/.phpver` |
| `phpver use 8.4` | Activate 8.4 in the current shell only |
| `phpver use 8.4 -g` | Global default (`~/.phpver/default`) |
| `phpver use 8.4 -p` | Write `.php-version` (project root when one already exists upstream) |
| `phpver list` | Registered versions and project files |
| `phpver current` / `phpver which` | Active version / path to `php` |
| `phpver uninstall 8.4` | Remove phpver link (Homebrew package remains) |

## PHP extensions

Homebrew `php@8.x` already ships many extensions (gd, intl, mbstring, curl, zip, openssl, pdo, xml, bcmath, …). Others are installed **per PHP version** via **PECL** (`phpver ext install`).

| Extension | Usually in bottle | Action |
|-----------|-------------------|--------|
| gd, intl, mbstring, curl, zip, openssl, pdo, xml, bcmath, fileinfo | Yes | `phpver ext list` |
| imagick | No | `brew install imagemagick` + `phpver ext install imagick` |
| redis, memcached, xdebug | No | `phpver ext install <name>` (+ `brew install …` if needed) |

PECL installs are **per 8.x line**: imagick on 8.4 is not available on 8.1 until you install it there too.

### List loaded extensions

```bash
phpver use 8.4
phpver ext list
phpver ext list 8.1          # specific version without switching
phpver ext help              # common Homebrew dependencies
```

### Project file: `.php-extensions`

Next to **`.php-version`**, version PECL extensions the team needs in **`.php-extensions`** (one name per line, `#` for comments):

```text
# PECL extensions for this project (phpver)
imagick
redis
```

**Important rules:**

- With `.php-version` in the tree, `.php-extensions` is read **only in that same directory** (not `~/.php-extensions` from subfolders).
- `phpver ext install … -p` writes to the project path (root where `.php-version` lives, not necessarily your cwd in a subfolder).
- List **PECL-only** extensions — not gd/intl (already in the bottle).
- On `cd` into the project, entries are installed automatically (`PHPVER_AUTO_EXT_SYNC=1`, default). Disable with `export PHPVER_AUTO_EXT_SYNC=0` in `~/.zshrc`.

Typical Laravel + imagick setup:

```bash
cd ~/Code/my-laravel
phpver use 8.4 -p
phpver ext install imagick -p
cat .php-extensions
git add .php-version .php-extensions
```

Teammate with a fresh clone:

```bash
phpver install 8.4
phpver use 8.4 -p
phpver ext sync              # install everything in .php-extensions
```

### Scope: shell / per-version vs project

| Operation | Without `-p` | With `-p` |
|-----------|--------------|-----------|
| **Install** `phpver ext install imagick` | PECL for the active version (from `.php-version`, global default, or `phpver use`) | Same **plus** append `imagick` to project `.php-extensions` |
| **Uninstall** `phpver ext uninstall imagick` | Remove from PECL for that PHP version | Same **plus** remove the line from `.php-extensions` |
| **Sync** `phpver ext sync` | — | Install all lines from `.php-extensions` for the project PHP version |

There is no home-level `.php-extensions` used by projects. For ad-hoc work outside a repo, install without `-p` on the version you activated with `phpver use 8.4 -g`.

Examples:

```bash
# This machine / this PHP version only (no project manifest)
phpver use 8.4 -g
phpver ext install imagick

# Project (manifest in the repo)
cd ~/Code/my-laravel
phpver use 8.4 -p
phpver ext install imagick -p
phpver ext install redis -p

# Remove from project manifest and PECL
phpver ext uninstall imagick -p
```

### Extension commands

| Command | Description |
|---------|-------------|
| `phpver ext list [8.4]` | Loaded modules + common Laravel extension check |
| `phpver ext install <ext> [8.4]` | Install via PECL (optional version) |
| `phpver ext install <ext> -p` | Install + add line to `.php-extensions` |
| `phpver ext uninstall <ext> [8.4]` | Uninstall via PECL |
| `phpver ext uninstall <ext> -p` | Uninstall + remove from `.php-extensions` |
| `phpver ext cleanup <ext> [8.4]` | Remove stale `extension=` ini files after a broken uninstall |
| `phpver ext sync [8.4]` | Install all extensions from `.php-extensions` |
| `phpver ext help` | Help and brew dependencies |

After uninstall, if you see `Unable to load dynamic library 'imagick.so'`, a duplicate or stale `.ini` is usually left behind:

```bash
phpver ext cleanup imagick 8.1
php --ini
```

### PHP config paths (per version)

- `php.ini`: `$(brew --prefix)/etc/php/8.4/php.ini`
- PECL drop-ins: `$(brew --prefix)/etc/php/8.4/conf.d/*.ini`

## Laravel

```bash
brew install composer
composer global require laravel/installer
# After the phpver block in ~/.zshrc:
# export PATH="$HOME/.composer/vendor/bin:$PATH"

cd ~/Code
phpver use 8.4 -p
phpver ext sync
laravel new my-app
```

Most Laravel apps do not need imagick (gd/intl from the bottle are enough).

## Layout

```
~/.phpver/
  lib/phpver.sh          # zsh hooks, auto-activate
  bin/phpver             # CLI
  versions/8.4 -> /opt/homebrew/opt/php@8.4
  default               # global version (e.g. "8.4")

project/
  .php-version          # e.g. "8.4"
  .php-extensions       # e.g. imagick, redis (PECL)
```

## Development (this repo)

To hack on phpver itself, clone the repository (not required for normal use):

```bash
git clone https://github.com/robertoporceddu/phpver.git
cd phpver
./install.sh          # installs to ~/.phpver like the curl installer
# or, without installing:
export PATH="$PWD/bin:$PATH"
source "$PWD/lib/phpver.sh"
phpver help
```

### AI agent skills

Portable instructions for coding agents live under [`ai/skills/`](ai/skills/). Start with [`ai/skills/phpver/SKILL.md`](ai/skills/phpver/SKILL.md); see [`ai/skills/README.md`](ai/skills/README.md) for how to wire them into your editor, CLI, or CI agent.

## Uninstall phpver

1. Remove the `# phpver` block from `~/.zshrc`
2. `rm -rf ~/.phpver`
3. Optional: `brew uninstall php@8.4` (and other versions)

## License

MIT
