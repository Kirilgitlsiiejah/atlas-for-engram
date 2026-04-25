#!/bin/bash
# atlas-cleanup — scan engram + atlas-pool/ for integrity issues
# Usage: cleanup.sh --scan
# Output: JSON {orphans: [...], dangling: [...], duplicates: [...], malformed: [...]}
#
# Env vars (optional):
#   ENGRAM_HOST  default http://127.0.0.1:7437
#   ATLAS_VAULT  canonical vault root (parent of atlas-pool/). Cascade fallback:
#                $ATLAS_VAULT → $VAULT_ROOT (legacy, warn) → walk-up marker → $HOME/vault.
#
# Flag (optional):
#   --vault <path>   override the resolved vault for this invocation (highest precedence).
#
# Defensive: exit 0 always, JSON output to stdout, NEVER modifies anything (read-only).

# Parse --vault flag (filtered out of $@ before MODE dispatch).
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
  # Fallback inline: minimal detect_project + resolve_project + detect_vault.
  detect_project() {
    local proj=""
    if command -v git >/dev/null 2>&1; then
      local remote_url
      remote_url=$(git remote get-url origin 2>/dev/null || true)
      [[ -n "$remote_url" ]] && proj=$(printf '%s\n' "$remote_url" | awk -F'[/:]' '{print $NF}' | awk -F'.git$' '{print $1}')
      if [[ -z "$proj" ]]; then
        local git_root
        git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
        [[ -n "$git_root" ]] && proj=$(basename "$git_root")
      fi
    fi
    [[ -z "$proj" ]] && proj=$(basename "$PWD" 2>/dev/null)
    [[ -z "$proj" ]] && proj="dev"
    printf '%s' "$proj"
  }
  resolve_project() {
    local explicit="${1:-}"
    if [[ -n "$explicit" ]]; then printf '%s' "$explicit"; else detect_project; fi
  }
  # Minimal cascade: L1 override → L2 ATLAS_VAULT → L3 VAULT_ROOT (warn) →
  # L4 walk-up (.obsidian dir or .atlas-pool file) → L5 $HOME/vault.
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

# FIX 14 — ENGRAM_HOST is canonical; ENGRAM_PORT only used as compat shim.
if [[ -z "${ENGRAM_HOST:-}" && -n "${ENGRAM_PORT:-}" ]]; then
  ENGRAM_HOST="http://127.0.0.1:${ENGRAM_PORT}"
fi
ENGRAM_HOST="${ENGRAM_HOST:-http://127.0.0.1:7437}"
VAULT=$(detect_vault "$VAULT_OVERRIDE")
ATLAS_POOL="${VAULT}/atlas-pool"

MODE="${1:-}"

if [[ "$MODE" != "--scan" ]]; then
  echo '{"success": false, "error": "use --scan"}' >&2
  exit 0
fi

# 1. Health check first — fail fast with clear error
if ! curl -sf "${ENGRAM_HOST}/health" --max-time 2 > /dev/null 2>&1; then
  echo '{"success": false, "error": "engram not reachable"}' >&2
  exit 0
fi

# 2. List all atlas obs across known projects.
#    Projects come from ATLAS_PROJECTS env var (comma-separated) or default to auto-detected single project.
#    To override: ATLAS_PROJECTS="dev,personal,backend" bash cleanup.sh --scan
ATLAS_OBS="[]"
ATLAS_PROJECTS_ENV="${ATLAS_PROJECTS:-$(detect_project)}"
IFS=',' read -ra PROJECTS <<< "$ATLAS_PROJECTS_ENV"

for proj in "${PROJECTS[@]}"; do
  ENCODED_PROJECT=$(printf '%s' "$proj" | jq -sRr @uri)
  RESP=$(curl -sf "${ENGRAM_HOST}/observations/recent?project=${ENCODED_PROJECT}&limit=500" --max-time 5 2>/dev/null) || continue
  # Validate JSON shape
  if ! echo "$RESP" | jq -e 'type == "array"' > /dev/null 2>&1; then
    continue
  fi
  PROJ_ATLAS=$(echo "$RESP" | jq -c "[.[] | select(.type == \"atlas\") | . + {project: \"${proj}\"}]")
  ATLAS_OBS=$(echo "$ATLAS_OBS" | jq --argjson new "$PROJ_ATLAS" '. + $new')
done

# 2.5. Enrich each obs with _source_url extracted from content via "**Source**: <url>" pattern.
#      The engram type=atlas obs does NOT have a top-level source_url field — URL is embedded
#      in content (see lookup.sh:78 for canonical pattern).
ATLAS_OBS=$(echo "$ATLAS_OBS" | jq -c '
  map(
    . as $o
    | . + {
        _source_url: (
          (($o.content // "") | capture("\\*\\*Source\\*\\*:\\s*(?<url>\\S+)"; "n")? // null)
          | if . then .url else "" end
        )
      }
  )
')

TOTAL_OBS=$(echo "$ATLAS_OBS" | jq 'length')

# 3. List all .md in atlas-pool/ (skip README.md)
POOL_FILES=()
if [[ -d "$ATLAS_POOL" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    POOL_FILES+=("$f")
  done < <(fd -e md . "$ATLAS_POOL" 2>/dev/null || true)
fi
TOTAL_POOL=${#POOL_FILES[@]}

# 4. Build pool_index: parse frontmatter from each .md to extract source_url
#    Replaces sed -E with awk (forbidden tools include sed).
extract_frontmatter_value() {
  # $1 = file path, $2 = key regex (e.g. "source_url|source")
  local file="$1"
  local key_re="$2"
  rg -m 1 "^(${key_re}):" "$file" 2>/dev/null | awk -v RS='\r?\n' '
    {
      # Strip leading "key:" then surrounding spaces and quotes.
      sub(/^[a-zA-Z_]+:[[:space:]]*/, "")
      # Strip trailing whitespace
      sub(/[[:space:]]+$/, "")
      # Strip surrounding quotes
      if (match($0, /^".*"$/) || match($0, /^'\''.*'\''$/)) {
        $0 = substr($0, 2, length($0)-2)
      }
      print
      exit
    }
  '
}

declare -A POOL_BY_URL
declare -A POOL_BY_FILE
for f in "${POOL_FILES[@]}"; do
  URL=$(extract_frontmatter_value "$f" "source_url|source")
  POOL_BY_FILE["$f"]="$URL"
  [[ -n "$URL" ]] && POOL_BY_URL["$URL"]="$f"
done

# 5. Build pool URL set as JSON array (for jq comparisons)
if [[ ${#POOL_BY_URL[@]} -gt 0 ]]; then
  POOL_URLS_JSON=$(printf '%s\n' "${!POOL_BY_URL[@]}" | jq -R . | jq -s .)
else
  POOL_URLS_JSON="[]"
fi

# 6. Detect ORPHANS: engram obs with _source_url NOT in pool
#    (only counts obs that DO have _source_url — missing _source_url is malformed, not orphan)
ORPHANS=$(echo "$ATLAS_OBS" | jq -c \
  --argjson pool_urls "$POOL_URLS_JSON" \
  '[.[] | select((._source_url // "") != "") | select(._source_url as $u | $pool_urls | index($u) | not)]')

# 7. Detect DANGLING: .md in pool whose source_url is NOT in any engram obs
ENGRAM_URL_SET=$(echo "$ATLAS_OBS" | jq -c '[.[] | ._source_url // empty | select(. != "")]')

DANGLING_LIST=()
for f in "${POOL_FILES[@]}"; do
  URL="${POOL_BY_FILE[$f]}"
  [[ -z "$URL" ]] && continue
  IS_INJECTED=$(echo "$ENGRAM_URL_SET" | jq --arg u "$URL" 'index($u) != null')
  if [[ "$IS_INJECTED" == "false" ]]; then
    TITLE=$(extract_frontmatter_value "$f" "title")
    CLIPPED=$(extract_frontmatter_value "$f" "clipped|created|date")
    ENTRY=$(jq -nc --arg path "$f" --arg url "$URL" --arg title "$TITLE" --arg clipped "$CLIPPED" \
      '{path: $path, source_url: $url, title: $title, clipped: $clipped}')
    DANGLING_LIST+=("$ENTRY")
  fi
done

if [[ ${#DANGLING_LIST[@]} -gt 0 ]]; then
  DANGLING=$(printf '%s\n' "${DANGLING_LIST[@]}" | jq -s '.')
else
  DANGLING="[]"
fi

# 8. Detect DUPLICATES: same _source_url in >1 obs (across projects)
#    Group by _source_url, then drop the empty-URL bucket and singletons.
DUPLICATES=$(echo "$ATLAS_OBS" | jq -c '
  group_by(._source_url // "")
  | map(select(length > 1 and (.[0]._source_url // "") != ""))
  | map({source_url: .[0]._source_url, occurrences: map({id: .id, project: .project, topic_key: .topic_key})})
')

# 9. Detect MALFORMED: missing _source_url OR topic_key not matching atlas/<domain>/<slug>
MALFORMED=$(echo "$ATLAS_OBS" | jq -c '
  [.[] | select(
    (._source_url == null or ._source_url == "") or
    ((.topic_key // "") | test("^atlas/[^/]+/[^/]+$") | not)
  ) | {id: .id, title: (.title // ""), topic_key: (.topic_key // ""), source_url: (._source_url // ""), project: (.project // "")}]
')

# 10. Output combined JSON
jq -nc \
  --argjson orphans "$ORPHANS" \
  --argjson dangling "$DANGLING" \
  --argjson duplicates "$DUPLICATES" \
  --argjson malformed "$MALFORMED" \
  --argjson total_obs "$TOTAL_OBS" \
  --argjson total_pool "$TOTAL_POOL" \
  '{
    success: true,
    total_obs: $total_obs,
    total_pool: $total_pool,
    orphans: $orphans,
    dangling: $dangling,
    duplicates: $duplicates,
    malformed: $malformed
  }'

exit 0
