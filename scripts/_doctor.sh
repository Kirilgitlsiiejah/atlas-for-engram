#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

WARNINGS=()
ENGRAM_HOST="${ENGRAM_HOST:-127.0.0.1:7437}"

curl -sf "http://${ENGRAM_HOST}/health" --max-time 1 >/dev/null 2>&1 \
  || WARNINGS+=("engram unreachable at http://${ENGRAM_HOST}")

MISSING=()
for cmd in jq curl rg fd; do command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd"); done
[[ ${#MISSING[@]} -gt 0 ]] && WARNINGS+=("missing commands: ${MISSING[*]}")

VAULT="${VAULT_ROOT:-$HOME/vault}"
[[ -d "${VAULT}/atlas-pool" ]] || WARNINGS+=("atlas-pool not found at ${VAULT}/atlas-pool")

if [[ -f "$HOME/.claude/settings.json" ]] && command -v jq >/dev/null 2>&1; then
  jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(test("\\.claude/skills/compare-with-atlas"))' \
    "$HOME/.claude/settings.json" >/dev/null 2>&1 \
    && WARNINGS+=("legacy hook in ~/.claude/settings.json — remove to avoid double-fire")
fi

[[ ${#WARNINGS[@]} -eq 0 ]] && exit 0
MSG=$'atlas-doctor:\n'
for w in "${WARNINGS[@]}"; do MSG+="  - $w"$'\n'; done
jq -n --arg ctx "$MSG" '{continue: true, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
