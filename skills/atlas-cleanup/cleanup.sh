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
# Validate the flag value defensively: missing/empty/flag-looking values are
# rejected with a JSON error (avoids consuming the next positional silently —
# e.g. `cleanup.sh --vault --scan` would otherwise treat `--scan` as the path).
VAULT_OVERRIDE=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault=*)
      VAULT_OVERRIDE="${1#--vault=}"
      if [[ -z "$VAULT_OVERRIDE" || "$VAULT_OVERRIDE" == --* ]]; then
        printf '%s\n' '{"success":false,"error":"--vault requires a non-empty path argument"}'
        exit 0
      fi
      shift ;;
    --vault)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        printf '%s\n' '{"success":false,"error":"--vault requires a path argument"}'
        exit 0
      fi
      VAULT_OVERRIDE="$2"; shift 2 ;;
    *)         ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

# Source shared helpers (defensive — fallback inline if missing)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || SCRIPT_DIR="."
ATLAS_ROOT="${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}}"
ATLAS_HELPERS="${ATLAS_ROOT}/scripts/_helpers.sh"
if [[ -f "$ATLAS_HELPERS" ]]; then
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
  # Minimal inline path normalize (F2) — drift prevention vs canonical helper.
  # Only the cases that bite on Windows / Git Bash:
  #   1. backslash → forward slash
  #   2. drive letter prefix C:/ → /c/
  #   3. trailing slash trim (preserve / and //host/share)
  _atlas_normalize_path() {
    local p="${1:-}"
    [[ -z "$p" ]] && { printf '%s' ""; return 0; }
    p="${p//\\//}"
    if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
      p="/${BASH_REMATCH[1],,}/${BASH_REMATCH[2]}"
    elif [[ "$p" =~ ^([A-Za-z]):$ ]]; then
      p="/${BASH_REMATCH[1],,}"
    fi
    if [[ ${#p} -gt 1 && "$p" == */ && "$p" != "//"*/* ]]; then
      p="${p%/}"
    fi
    # Collapse multiple consecutive slashes (preserve UNC //host/share leading double-slash)
    local _prefix=""
    if [[ "$p" == //*/* ]]; then
      # Preserve UNC prefix //host
      _prefix="//"
      p="${p#//}"
    fi
    while [[ "$p" == *"//"* ]]; do
      p="${p//\/\//\/}"
    done
    p="${_prefix}${p}"
    printf '%s' "$p"
  }
  _atlas_warn_legacy() {
    if [[ -n "${_ATLAS_VAULT_ROOT_WARNED:-}" ]]; then return 0; fi
    # Atomic directory flag (mkdir is atomic, won't follow symlinks).
    # Per-shell-tree via $PPID. Username fallback chain handles Git Bash on Windows
    # (no $USER) and edge cases. See _helpers.sh _atlas_warn_legacy for full rationale.
    local _flag_dir="${TMPDIR:-/tmp}/_atlas_vault_warned.${USER:-${USERNAME:-${LOGNAME:-anon}}}.${PPID:-0}"
    if mkdir "$_flag_dir" 2>/dev/null; then
      printf '%s\n' "warning: \$VAULT_ROOT is deprecated; use \$ATLAS_VAULT instead" >&2
    fi
    export _ATLAS_VAULT_ROOT_WARNED=1
    return 0
  }
  # Minimal cascade: L1 override → L2 ATLAS_VAULT → L3 VAULT_ROOT (warn) →
  # L4 walk-up (.obsidian dir or .atlas-pool file) → L5 $HOME/vault.
  detect_vault() {
    local override="${1:-}" v="" lvl=""
    if [[ -n "$override" ]]; then v=$(_atlas_normalize_path "$override"); lvl=1
    elif [[ -n "${ATLAS_VAULT:-}" ]]; then v=$(_atlas_normalize_path "$ATLAS_VAULT"); lvl=2
    elif [[ -n "${VAULT_ROOT:-}" ]]; then
      _atlas_warn_legacy
      v=$(_atlas_normalize_path "$VAULT_ROOT"); lvl=3
    else
      local d
      d=$(_atlas_normalize_path "$PWD")
      local i=0
      while [[ $i -lt 64 ]]; do
        if [[ -d "$d/.obsidian" ]] || [[ -f "$d/.atlas-pool" ]]; then v="$d"; lvl=4; break; fi
        [[ "$d" == "/" || "$d" =~ ^/[a-zA-Z]$ || "$d" =~ ^[A-Za-z]:/?$ ]] && break
        local p; p=$(dirname "$d" 2>/dev/null); [[ -z "$p" || "$p" == "$d" ]] && break
        d="$p"; i=$((i+1))
      done
      [[ -z "$v" ]] && { v=$(_atlas_normalize_path "${HOME}/vault"); lvl=5; }
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

# 3. List top-level clip .md files in atlas-pool/ (skip README/docs)
POOL_FILES=()
if [[ -d "$ATLAS_POOL" ]]; then
  shopt -s nullglob
  CANDIDATES=("${ATLAS_POOL}"/*.md)
  shopt -u nullglob
  for f in "${CANDIDATES[@]}"; do
    [[ ! -f "$f" ]] && continue
    [[ "${f##*/}" == "README.md" ]] && continue
    POOL_FILES+=("$f")
  done
fi
TOTAL_POOL=${#POOL_FILES[@]}

# 4. Build pool_index: parse frontmatter from each clip .md to extract resolved URL
#    Replaces sed -E with awk (forbidden tools include sed).
extract_frontmatter_value() {
  # $1 = file path, $2 = key regex (e.g. "source_url|source")
  local file="$1"
  local key_re="$2"
  rg -m 1 -N "^(${key_re}):[[:space:]]*" "$file" 2>/dev/null | awk -v RS='\r?\n' '
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

resolve_frontmatter_source_url() {
  local file="$1"
  local source_url=""
  local legacy_source=""

  source_url=$(extract_frontmatter_value "$file" "source_url")
  if [[ -n "$source_url" ]]; then
    printf '%s' "$source_url"
    return 0
  fi

  legacy_source=$(extract_frontmatter_value "$file" "source")
  printf '%s' "$legacy_source"
}

declare -A POOL_BY_URL
declare -A POOL_BY_FILE
for f in "${POOL_FILES[@]}"; do
  URL=$(resolve_frontmatter_source_url "$f")
  POOL_BY_FILE["$f"]="$URL"
  [[ -n "$URL" ]] && POOL_BY_URL["$URL"]="$f"
done

# 5. Build pool URL set as JSON array (for jq comparisons)
if [[ ${#POOL_BY_URL[@]} -gt 0 ]]; then
  POOL_URLS_JSON=$(printf '%s\n' "${!POOL_BY_URL[@]}" | jq -R . | jq -s .)
else
  POOL_URLS_JSON="[]"
fi

# 6. Detect ORPHANS: engram obs with resolved source URL NOT in pool
#    (only counts obs that DO have _source_url — missing _source_url is malformed, not orphan)
ORPHANS=$(echo "$ATLAS_OBS" | jq -c \
  --argjson pool_urls "$POOL_URLS_JSON" \
  '[.[] | select((._source_url // "") != "") | select(._source_url as $u | $pool_urls | index($u) | not)]')

# 7. Detect DANGLING: clip .md in pool whose resolved source URL is NOT in any engram obs
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
