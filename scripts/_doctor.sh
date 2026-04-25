#!/bin/bash
# atlas-doctor — SessionStart healthcheck for the atlas plugin.
# Always exits 0; emits hookSpecificOutput JSON only when warnings exist.
# Defensive: NO `set -euo pipefail`, errors squelched with `2>/dev/null || true`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

WARNINGS=()
ENGRAM_HOST="${ENGRAM_HOST:-127.0.0.1:7437}"

curl -sf "http://${ENGRAM_HOST}/health" --max-time 1 >/dev/null 2>&1 \
  || WARNINGS+=("engram unreachable at http://${ENGRAM_HOST}")

MISSING=()
for cmd in jq curl rg fd; do command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd"); done
[[ ${#MISSING[@]} -gt 0 ]] && WARNINGS+=("missing commands: ${MISSING[*]}")

# Resolve the vault via the 5-level cascade and report which level fired.
# Levels:
#   1 = --vault flag (n/a here — doctor takes no flags)
#   2 = $ATLAS_VAULT canonical
#   3 = $VAULT_ROOT legacy (emits deprecation warning via the helper)
#   4 = walk-up marker (.obsidian/ dir or .atlas-pool file)
#   5 = $HOME/vault fallback
detect_vault >/dev/null
VAULT_LEVEL="${ATLAS_VAULT_RESOLVED_LEVEL:-?}"
VAULT_PATH="${ATLAS_VAULT_RESOLVED:-}"

case "$VAULT_LEVEL" in
  1) VAULT_LABEL="--vault flag" ;;
  2) VAULT_LABEL="ATLAS_VAULT" ;;
  3) VAULT_LABEL="VAULT_ROOT-legacy" ;;
  4)
    # Differentiate which marker matched (re-test from the resolved path).
    if [[ -d "${VAULT_PATH}/.obsidian" ]]; then
      VAULT_LABEL="walk-up .obsidian"
    elif [[ -f "${VAULT_PATH}/.atlas-pool" ]]; then
      VAULT_LABEL="walk-up .atlas-pool"
    else
      VAULT_LABEL="walk-up"
    fi
    ;;
  5) VAULT_LABEL="fallback" ;;
  *) VAULT_LABEL="unknown" ;;
esac

# REQ-OBS-2: when the cascade falls all the way to L5 AND that path doesn't
# exist, surface a remediation warning so the user knows what to set.
if [[ "$VAULT_LEVEL" == "5" && ! -d "$VAULT_PATH" ]]; then
  WARNINGS+=("vault path ${VAULT_PATH} does not exist — set \$ATLAS_VAULT, place .atlas-pool marker, or create the dir")
fi

# Existing pool check — keep semantics, but anchored to the resolved vault.
# Guard with VAULT_PATH non-empty: when detect_vault returns empty (regression
# defensive branch), we'd otherwise emit "atlas-pool not found at /atlas-pool"
# which masks the real problem (the unresolved-vault line above already signals it).
if [[ -n "$VAULT_PATH" ]]; then
  [[ -d "${VAULT_PATH}/atlas-pool" ]] || WARNINGS+=("atlas-pool not found at ${VAULT_PATH}/atlas-pool")
fi

if [[ -f "$HOME/.claude/settings.json" ]] && command -v jq >/dev/null 2>&1; then
  jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(test("\\.claude/skills/compare-with-atlas"))' \
    "$HOME/.claude/settings.json" >/dev/null 2>&1 \
    && WARNINGS+=("legacy hook in ~/.claude/settings.json — remove to avoid double-fire")
fi

# Always include the vault resolution line in stdout so the user can see
# which branch was taken even when nothing else is wrong (REQ-OBS-1).
# If the resolution returned an empty path (regression / detect_vault broken),
# render an explicit "(unresolved) -> (unknown)" so silence never masks a bug.
if [[ -n "$VAULT_PATH" ]]; then
  VAULT_LINE="vault: L${VAULT_LEVEL} (${VAULT_LABEL}) -> ${VAULT_PATH}"
else
  VAULT_LINE="vault: L? (unresolved) -> (unknown)"
fi

MSG=$'atlas-doctor:\n  - '"$VAULT_LINE"$'\n'
for w in "${WARNINGS[@]}"; do MSG+="  - $w"$'\n'; done
jq -n --arg ctx "$MSG" '{continue: true, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
