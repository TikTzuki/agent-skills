#!/usr/bin/env bash
# Write a structured session to .claude/memory/sessions/
# Usage: write-session.sh <session_id> <branch> <files_modified_count> <user_messages> <tool_calls> <summary_text>
set -euo pipefail

SESSION_ID="${1:?session_id required}"
BRANCH="${2:-unknown}"
FILES_COUNT="${3:-0}"
USER_MESSAGES="${4:-0}"
TOOL_CALLS="${5:-0}"
SUMMARY="${6:-No summary}"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_DIR="$PROJECT_ROOT/.claude/memory"
SESSIONS_DIR="$MEMORY_DIR/sessions"
INDEX_FILE="$SESSIONS_DIR/index.json"

# Ensure directories exist
mkdir -p "$SESSIONS_DIR"
[ -f "$INDEX_FILE" ] || echo '{"sessions":[]}' > "$INDEX_FILE"

DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
DATE_SHORT="$(date '+%Y-%m-%d')"

# JSON-escape a string (no jq dependency)
json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  echo "$s"
}

# Write full session JSON
SESSION_FILE="$SESSIONS_DIR/${SESSION_ID}.json"
cat > "$SESSION_FILE" <<EOF
{
  "id": "$(json_esc "$SESSION_ID")",
  "date": "$DATE",
  "branch": "$(json_esc "$BRANCH")",
  "summary": "$(json_esc "$SUMMARY")",
  "files_modified": $FILES_COUNT,
  "user_messages": $USER_MESSAGES,
  "tool_calls": $TOOL_CALLS
}
EOF

# Update index: prepend new session entry, keep last N sessions
# Read existing index, inject new entry at front using awk/sed (no jq)
NEW_ENTRY="{\"id\":\"$(json_esc "$SESSION_ID")\",\"date\":\"$DATE\",\"branch\":\"$(json_esc "$BRANCH")\",\"summary\":\"$(json_esc "$SUMMARY")\",\"files_modified\":$FILES_COUNT}"

if command -v python3 &>/dev/null; then
  # Use python3 for reliable JSON manipulation
  python3 -c "
import json, sys
idx = json.load(open('$INDEX_FILE'))
entry = json.loads('$NEW_ENTRY')
idx['sessions'].insert(0, entry)
idx['sessions'] = idx['sessions'][:50]  # cap at 50
json.dump(idx, open('$INDEX_FILE','w'), indent=2)
" 2>/dev/null || true
else
  # Fallback: just overwrite with single entry (lossy but safe)
  echo "{\"sessions\":[$NEW_ENTRY]}" > "$INDEX_FILE"
fi

echo "$SESSION_FILE"
