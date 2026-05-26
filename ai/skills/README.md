# AI agent skills (phpver)

Portable instructions for **any** coding agent (CLI, IDE, or cloud). Not tied to a single vendor.

## Layout

```
ai/skills/
├── README.md           # this file — how to load skills
└── phpver/
    ├── SKILL.md        # primary instructions (read this)
    └── reference.md    # diagnostics and paths
```

## Skill format

Each skill is a folder with a **`SKILL.md`** file:

- **YAML frontmatter** (`name`, `description`) — optional metadata for tools that index skills automatically
- **Markdown body** — the actual instructions; works if you paste it into any system prompt or rules file

Tools that ignore frontmatter can use the body only (everything below the closing `---`).

## How to enable (by environment)

| Environment | Suggested setup |
|-------------|-----------------|
| **Project rules** | Add to `AGENTS.md`, `CLAUDE.md`, or your tool’s “project instructions”: *“When working with PHP on macOS, follow `ai/skills/phpver/SKILL.md`.”* |
| **Global rules** | Copy or symlink `ai/skills/phpver` into your tool’s global skills/rules directory (see that product’s docs). |
| **One-off task** | `@`-mention or attach `ai/skills/phpver/SKILL.md` in the chat, or paste the file into the system prompt. |
| **CI / headless agent** | Export `SKILL.md` content into an env var or prompt template before the job runs. |

Examples (paths are illustrative — use your tool’s equivalent):

```bash
# Symlink for tools that load ~/.cursor/skills, ~/.claude/skills, etc.
ln -sf "$(pwd)/ai/skills/phpver" ~/.your-agent/skills/phpver

# Or copy into repo root for agents that read AGENTS.md
# (add one line in AGENTS.md pointing to ai/skills/phpver/SKILL.md)
```

## When agents should load `phpver`

Use the skill when the task involves:

- phpver, `.php-version`, `.php-extensions`
- PHP version switching on **macOS** via Homebrew
- PECL extensions (imagick, redis, xdebug, …)
- Laravel PHP environment setup on a Mac

Do **not** use phpver on Linux/WSL — suggest apt/dnf, `asdf`, or `phpenv` instead.

## Maintaining skills

After changing phpver behavior, update `ai/skills/phpver/SKILL.md` (and `reference.md` if paths or flags changed) in the same PR as code changes.
