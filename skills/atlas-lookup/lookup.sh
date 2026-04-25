#!/bin/bash
# atlas-lookup — search engram + atlas-pool/ for a URL or substring.
#
# Usage: lookup.sh '<url-or-substring>'
#
# Output (stdout, single-line JSON):
#   {
#     "success": true,
#     "query": "<q>",
#     "engram_matches": [ {id, project, topic_key, title, content_excerpt, source_url}, ... ],
#     "pool_matches":   [ {path, source_url, title, clipped}, ... ],
#     "scenario": "both" | "engram_only" | "pool_only" | "none",
#     "warnings": [ ... ]
#   }
#
# On failure: {"success": false, "error": "..."} (still exit 0 — never crash the caller).
#
# Env vars:
#   ENGRAM_HOST  default http://127.0.0.1:7437
#   VAULT_ROOT   default $HOME/vault
#   ATLAS_POOL   default ${VAULT_ROOT}/atlas-pool
#
# This script is READ-ONLY. It never writes, deletes, or modifies anything.
#
# Defensive style: NO `set -euo pipefail` (intentional). Errors are caught explicitly
# via `|| true` and explicit checks per ecosystem convention.

# Parse --vault flag (filtered out of $@ before QUERY positional).
VAULT_OVERRIDE=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault)   VAULT_OVERRIDE="${2:-}"; shift 2 ;;
    --vault=*) VAULT_OVERRIDE="${1#--vault=}"; shift ;;
    *)         ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

# Source shared helpers (defensive — fallback inline if missing)
ATLAS_HELPERS="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE%/*}/../..}/scripts/_helpers.sh"
if [[ -f "$ATLAS_HELPERS" ]]; then
  # shellcheck source=/dev/null
  source "$ATLAS_HELPERS"
else
  # Fallback inline: minimal detect_vault (cascade L1→L5).
  detect_vault() {
    local override="${1:-}" v="" lvl=""
    if [[ -n "$override" ]]; then v="$override"; lvl=1
    elif [[ -n "${ATLAS_VAULT:-}" ]]; then v="$ATLAS_VAULT"; lvl=2
    elif [[ -n "${VAULT_ROOT:-}" ]]; then
      [[ -z "${_ATLAS_VAULT_ROOT_WARNED:-}" ]] && \
        printf 'warning: $VAULT_ROOT is deprecated; use $ATLAS_VAULT instead\n' >&2 && \
        export _ATLAS_VAULT_ROOT_WARNED=1
      v="$VAULT_ROOT"; lvl=3
    else
      local d="$PWD" i=0
      while [[ $i -lt 64 ]]; do
        if [[ -d "$d/.obsidian" ]] || [[ -f "$d/.atlas-pool" ]]; then v="$d"; lvl=4; break; fi
        [[ "$d" == "/" || "$d" =~ ^/[a-zA-Z]$ || "$d" =~ ^[A-Za-z]:/?$ ]] && break
        local p; p=$(dirname "$d" 2>/dev/null); [[ -z "$p" || "$p" == "$d" ]] && break
        d="$p"; i=$((i+1))
      done
      [[ -z "$v" ]] && { v="${HOME}/vault"; lvl=5; }
    fi
    export ATLAS_VAULT_RESOLVED="$v" ATLAS_VAULT_RESOLVED_LEVEL="$lvl"
    printf '%s' "$v"
  }
fi

QUERY="${1:-}"
# FIX 14 — ENGRAM_HOST is canonical; ENGRAM_PORT only used as compat shim.
if [[ -z "${ENGRAM_HOST:-}" && -n "${ENGRAM_PORT:-}" ]]; then
  ENGRAM_HOST="http://127.0.0.1:${ENGRAM_PORT}"
fi
ENGRAM_HOST="${ENGRAM_HOST:-http://127.0.0.1:7437}"
VAULT=$(detect_vault "$VAULT_OVERRIDE")
ATLAS_POOL="${ATLAS_POOL:-${VAULT}/atlas-pool}"

WARNINGS=()

err_json() {
  jq -nc --arg msg "$1" '{success:false, error:$msg}'
  exit 0
}

if [[ -z "$QUERY" ]]; then
  err_json "no query provided (usage: lookup.sh '<url-or-substring>')"
fi

# ─── 1. Engram search (global — across ALL projects, type=atlas) ─────────────
ENGRAM_MATCHES="[]"

# Health check (cheap; if engram is down, skip but warn — don't fail)
if curl -sf "${ENGRAM_HOST}/health" --max-time 2 >/dev/null 2>&1; then
  # GET /search?q=<query>&type=atlas&limit=50 — no project filter = global
  SEARCH_RESPONSE=$(curl -sf -G \
    --data-urlencode "q=${QUERY}" \
    --data-urlencode "type=atlas" \
    --data-urlencode "limit=50" \
    "${ENGRAM_HOST}/search" \
    --max-time 5 2>/dev/null) || SEARCH_RESPONSE=""

  if [[ -n "$SEARCH_RESPONSE" ]] && echo "$SEARCH_RESPONSE" | jq -e '. == null or type == "array"' >/dev/null 2>&1; then
    # /search returns `null` (not []) when no rows match — normalize to [] first.
    # Then second-pass filter to keep only matches where the query appears in
    # content OR title OR topic_key (engram's FTS may match on synonyms we don't want).
    # source_url lives inside content as "**Source**: <url>".
    ENGRAM_MATCHES=$(echo "$SEARCH_RESPONSE" | jq -c \
      --arg q "$QUERY" \
      '(. // [])
       | [
           .[]
           | select(
               ((.content // "") | ascii_downcase | contains($q | ascii_downcase))
               or ((.title // "") | ascii_downcase | contains($q | ascii_downcase))
               or ((.topic_key // "") | ascii_downcase | contains($q | ascii_downcase))
             )
           | {
               id:        .id,
               project:   (.project // "unknown"),
               topic_key: (.topic_key // ""),
               title:     (.title // ""),
               source_url: (
                 (.content // "")
                 | capture("\\*\\*Source\\*\\*:\\s*(?<url>\\S+)"; "n")?
                 | (.url // "")
               ),
               content_excerpt: ((.content // "")[0:200])
             }
         ]')
  else
    WARNINGS+=("engram /search returned no usable response")
  fi
else
  WARNINGS+=("engram unreachable at ${ENGRAM_HOST} — skipped engram search")
fi

# ─── 2. atlas-pool/ raw .md scan ─────────────────────────────────────────────
POOL_MATCHES="[]"

if [[ -d "$ATLAS_POOL" ]]; then
  # rg -l returns paths (one per line) of files containing the query, case-insensitive.
  # --type md restricts to markdown. --no-messages silences "no matches" noise.
  MATCHED_FILES=$(rg -l -i --no-messages --type md -- "$QUERY" "$ATLAS_POOL" 2>/dev/null || true)

  if [[ -n "$MATCHED_FILES" ]]; then
    POOL_ENTRIES=()
    while IFS= read -r FILE; do
      [[ -z "$FILE" ]] && continue
      BASE=$(basename "$FILE")
      # Skip the README placeholder
      [[ "$BASE" == "README.md" ]] && continue

      # Extract frontmatter value via rg --replace (no sed, alineado con conventions)
      SOURCE_URL=$(rg -m 1 -N --no-messages '^(source_url|source):\s*' "$FILE" 2>/dev/null \
        | rg --no-messages -o -r '$1' '^(?:source_url|source):\s*"?([^"\r\n]+?)"?\s*$' \
        || true)
      TITLE=$(rg -m 1 -N --no-messages '^title:\s*' "$FILE" 2>/dev/null \
        | rg --no-messages -o -r '$1' '^title:\s*"?([^"\r\n]+?)"?\s*$' \
        || true)
      CLIPPED=$(rg -m 1 -N --no-messages '^(clipped|created|date):\s*' "$FILE" 2>/dev/null \
        | rg --no-messages -o -r '$1' '^(?:clipped|created|date):\s*"?([^"\r\n]+?)"?\s*$' \
        || true)

      ENTRY=$(jq -nc \
        --arg path "$FILE" \
        --arg url "${SOURCE_URL:-}" \
        --arg title "${TITLE:-}" \
        --arg clipped "${CLIPPED:-}" \
        '{path:$path, source_url:$url, title:$title, clipped:$clipped}')
      POOL_ENTRIES+=("$ENTRY")
    done <<< "$MATCHED_FILES"

    if [[ ${#POOL_ENTRIES[@]} -gt 0 ]]; then
      POOL_MATCHES=$(printf '%s\n' "${POOL_ENTRIES[@]}" | jq -s '.')
    fi
  fi
else
  WARNINGS+=("atlas-pool not found at ${ATLAS_POOL}")
fi

# ─── 3. Combine + emit ───────────────────────────────────────────────────────
WARN_JSON=$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s '[.[] | select(. != "")]')

jq -nc \
  --arg query "$QUERY" \
  --argjson engram "$ENGRAM_MATCHES" \
  --argjson pool "$POOL_MATCHES" \
  --argjson warnings "$WARN_JSON" \
  '{
     success: true,
     query: $query,
     engram_matches: $engram,
     pool_matches: $pool,
     warnings: $warnings,
     scenario: (
       if   ($engram | length) > 0 and ($pool | length) > 0 then "both"
       elif ($engram | length) > 0 then "engram_only"
       elif ($pool   | length) > 0 then "pool_only"
       else "none"
       end
     )
   }'

exit 0
