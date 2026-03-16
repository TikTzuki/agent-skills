---
name: setup
description: >
  Scope-aware plugin setup — auto-detects user vs project scope and installs
  CLAUDE.md, rules, hooks, and memory to the correct locations.
  Run once per project after installing the plugin.
---

# /setup — Scope-Aware Plugin Setup

Auto-detects how the plugin is installed and configures accordingly:

| Scope | When | Instructions go to | Hooks go to | Memory goes to |
|-------|------|-------------------|-------------|---------------|
| **User** | Plugin via marketplace | `~/.claude/` (global) | `~/.claude/settings.json` | `.claude/memory/` (project) |
| **Project** | Plugin repo = project | `.claude/` (project) | `.claude/settings.json` | `.claude/memory/` (project) |

## Run setup now

Use the Bash tool to locate and run the setup script:

```bash
# Find the installed plugin
PLUGIN_DIR="$(find "$HOME/.claude/plugins" -maxdepth 4 -name "setup.sh" \
  -path "*/devco-agent-skills/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {})"

if [ -z "$PLUGIN_DIR" ]; then
  # Fallback: maybe we're in the plugin repo itself
  if [ -f "scripts/setup.sh" ]; then
    PLUGIN_DIR="$(pwd)"
  else
    echo "Plugin not found. Install first: /plugin install devco-agent-skills"
    exit 1
  fi
fi

bash "$PLUGIN_DIR/scripts/setup.sh"
```

## After setup

**User scope** — commit team config so teammates auto-install:
```bash
git add .claude/settings.json .claude/memory/
git commit -m "chore: add Claude Code project context"
```

**Project scope** — commit everything:
```bash
git add .claude/
git commit -m "chore: add Claude Code project context"
```

## Verify

```
/status
```

## Refresh after plugin update

```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --update
```
