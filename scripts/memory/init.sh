#!/usr/bin/env bash
# Initialize structured memory directory for a project
set -euo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MEMORY_DIR="$PROJECT_ROOT/.claude/memory"

mkdir -p "$MEMORY_DIR/sessions"
mkdir -p "$MEMORY_DIR/knowledge"
mkdir -p "$MEMORY_DIR/context"

# Initialize index if not exists
if [ ! -f "$MEMORY_DIR/sessions/index.json" ]; then
  echo '{"sessions":[]}' > "$MEMORY_DIR/sessions/index.json"
fi

# Initialize knowledge files if not exists
for f in decisions.json patterns.json blockers.json; do
  if [ ! -f "$MEMORY_DIR/knowledge/$f" ]; then
    echo '{"entries":[]}' > "$MEMORY_DIR/knowledge/$f"
  fi
done

# Initialize context files
if [ ! -f "$MEMORY_DIR/context/project-state.json" ]; then
  cat > "$MEMORY_DIR/context/project-state.json" <<EOF
{
  "project": "$(basename "$PROJECT_ROOT")",
  "initialized_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "tech_stack": [],
  "active_branch": ""
}
EOF
fi

if [ ! -f "$MEMORY_DIR/context/active-work.json" ]; then
  echo '{"current_task":"","started_at":"","notes":[]}' > "$MEMORY_DIR/context/active-work.json"
fi

# Config
if [ ! -f "$MEMORY_DIR/config.json" ]; then
  cat > "$MEMORY_DIR/config.json" <<EOF
{
  "version": "1.0",
  "max_sessions_in_index": 50,
  "session_retention_days": 90,
  "token_budget": {
    "tier0_index": 50,
    "tier1_context": 200,
    "tier2_full": 500,
    "max_total": 750
  }
}
EOF
fi

echo "Memory directory initialized: $MEMORY_DIR"
