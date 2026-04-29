#!/bin/bash
# atlas-index generator — queries engram HTTP API for type=atlas observations,
# enriches each entry with timestamps + tags, and generates Atlas-Index.md atomically
# with three sections: Recent (last 7d), By Domain, By Tag.
#
# Usage: bash generate.sh [project]
#   project defaults to "dev"
#
# Env vars (optional):
#   ENGRAM_HOST  default http://127.0.0.1:7437
#                (compat: if ENGRAM_PORT is set and ENGRAM_HOST is not, derive from port)
#   ATLAS_VAULT  canonical vault root. Cascade fallback (highest first):
#                --vault flag → $ATLAS_VAULT → $VAULT_ROOT (legacy, warn) →
#                walk-up marker → $HOME/vault.
#   RECENT_DAYS  default 7   (window for "Recent" section)
#
# Flag (optional):
#   --vault <path>   override the resolved vault for this invocation.
#
# Exit code: always 0 (errors signaled via JSON on stderr per ecosystem convention).
#
# Defensive style: NO `set -euo pipefail` (intentional). Errors are caught explicitly.

# Parse --vault flag (filtered out of $@ before positional [project] arg).
# Validate the flag value defensively: missing/empty/flag-looking values are
# rejected with a JSON error (avoids consuming the next positional silently —
# e.g. `generate.sh --vault myproject` would otherwise treat `myproject` as
# the path and lose the project arg).
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

# FIX 4 — trap to clean any leftover .tmp files on any exit path.
INDEX_TMP=""
cleanup_tmp() {
  [[ -n "${INDEX_TMP:-}" && -f "${INDEX_TMP}" ]] && rm -f "$INDEX_TMP" 2>/dev/null
}
trap cleanup_tmp EXIT

# Helper: emit JSON error to stderr and exit 0 (defensive — never crash caller).
emit_err() {
  jq -nc --arg msg "$1" '{success: false, error: $msg}' >&2
  exit 0
}

# FIX 12 — Windows file-lock retry helper. Atlas-Index.md being open in Obsidian
# can hold a file lock that makes `mv -f` fail. Retry up to 3 times w/ 500ms backoff.
mv_with_retry() {
  local src="$1"
  local dst="$2"
  local attempts=3
  local delay=0.5
  local i
  for ((i=1; i<=attempts; i++)); do
    if mv -f "$src" "$dst" 2>/dev/null; then
      return 0
    fi
    if [[ $i -lt $attempts ]]; then
      sleep "$delay"
    fi
  done
  return 1
}

PROJECT=$(resolve_project "${1:-}")

# FIX 14 — ENGRAM_HOST is canonical; ENGRAM_PORT only used as compat shim.
if [[ -z "${ENGRAM_HOST:-}" && -n "${ENGRAM_PORT:-}" ]]; then
  ENGRAM_HOST="http://127.0.0.1:${ENGRAM_PORT}"
fi
ENGRAM_HOST="${ENGRAM_HOST:-http://127.0.0.1:7437}"
VAULT=$(detect_vault "$VAULT_OVERRIDE")
RECENT_DAYS="${RECENT_DAYS:-7}"
INDEX_PATH="${VAULT}/Atlas-Index.md"
INDEX_TMP="${INDEX_PATH}.tmp.$$"

# URL-encode project (safe for names with spaces/specials)
ENCODED_PROJECT=$(printf '%s' "$PROJECT" | jq -sRr @uri 2>/dev/null) || ENCODED_PROJECT="$PROJECT"

# 1. Health check first — fail fast with clear error
if ! curl -sf "${ENGRAM_HOST}/health" --max-time 2 > /dev/null 2>&1; then
  emit_err "engram not reachable at ${ENGRAM_HOST} (health check failed)"
fi

# 2. Fetch all recent observations for the project (server returns JSON array)
#    /observations/recent supports: project, scope, limit; we filter type=atlas client-side
RESPONSE=$(curl -sf "${ENGRAM_HOST}/observations/recent?project=${ENCODED_PROJECT}&limit=500" --max-time 5 2>/dev/null) || RESPONSE=""

if [[ -z "$RESPONSE" ]]; then
  emit_err "empty response from ${ENGRAM_HOST}/observations/recent (project=${PROJECT})"
fi

# Validate JSON shape
if ! echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
  emit_err "unexpected response shape from /observations/recent (expected JSON array)"
fi

NOW_EPOCH=$(date -u +%s)
RECENT_CUTOFF=$((NOW_EPOCH - RECENT_DAYS * 86400))
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 3. Filter type=atlas, enrich each obs with:
#    - _domain   : second segment of topic_key
#    - _ts       : created_at (ISO string, kept as-is)
#    - _ts_epoch : best-effort epoch parse for sorting / recent filter
#    - _ts_date  : YYYY-MM-DD slice of created_at (legible)
#    - _source   : url extracted from "**Source**: <url>" line if present
#    - _tags     : array of normalized tags (lowercase, trimmed) extracted defensively
#                  from yaml-style "tags: [a, b]" or markdown "**Tags**: a, b" lines
#                  also accepts inline "#tag" style (one per line at the top of content)
#
# Epoch parse: created_at format "2026-04-24T12:34:56Z" or with fractional seconds.
# jq's strptime is brittle across builds, so we shell-out per-row with `date -d` for
# correctness. To keep this fast even with 500 rows we batch via awk-friendly format.

ATLAS_RAW=$(echo "$RESPONSE" | jq -c '[.[] | select(.type == "atlas")]')
TOTAL=$(echo "$ATLAS_RAW" | jq 'length')

if [[ "$TOTAL" -eq 0 ]]; then
  # Empty corner case: write minimal index and exit successfully
  {
    echo "<!-- Auto-generated by skill 'atlas-index'. DO NOT EDIT BY HAND — regenerate with the skill. -->"
    echo "<!-- Last regenerated: ${TIMESTAMP} -->"
    echo "<!-- Project: ${PROJECT} | Total: 0 | Domains: 0 | Tags: 0 | Recent (${RECENT_DAYS}d): 0 -->"
    echo ""
    echo "# Atlas Index — project: \`${PROJECT}\`"
    echo ""
    echo "0 entries. Last regenerated ${TIMESTAMP}."
    echo ""
    echo "> Sin entries \`type=atlas\` en este proyecto todavía."
    echo ">"
    echo "> Para inyectar clips del atlas-pool, usá el skill \`inject-atlas\`."
  } > "$INDEX_TMP"
  if ! mv_with_retry "$INDEX_TMP" "$INDEX_PATH"; then
    jq -nc \
      --arg src "$INDEX_TMP" \
      --arg dst "$INDEX_PATH" \
      '{success: false, error: ("mv failed after 3 retries (file lock?). tmp kept for debug: " + $src + " → " + $dst)}' >&2
    trap - EXIT
    exit 0
  fi
  INDEX_TMP=""

  jq -nc \
    --arg path "$INDEX_PATH" \
    --arg project "$PROJECT" \
    --arg timestamp "$TIMESTAMP" \
    '{path: $path, project: $project, total: 0, domains: 0, tags: 0, recent_count: 0, oldest: null, newest: null, timestamp: $timestamp, top3_domains: [], top3_tags: []}'
  exit 0
fi

# Build a TSV of (id, created_at) so we can resolve epochs in one shell loop
TS_LINES=$(echo "$ATLAS_RAW" | jq -r '.[] | [(.id|tostring), (.created_at // "")] | @tsv')

# Resolve epoch per row using `date -d` (GNU date — available on Git Bash/MSYS).
# Fallback: 0 if parse fails. Build EPOCH_MAP as jq object {id_string: epoch_int}.
EPOCH_MAP=$(
  {
    echo '{'
    first=1
    while IFS=$'\t' read -r id ts; do
      if [[ -n "$ts" ]]; then
        e=$(date -u -d "$ts" +%s 2>/dev/null || echo 0)
      else
        e=0
      fi
      if [[ $first -eq 1 ]]; then
        first=0
      else
        echo ','
      fi
      printf '"%s": %s' "$id" "$e"
    done <<< "$TS_LINES"
    echo '}'
  } | jq -c '.'
)

# Enrich the array with computed fields using EPOCH_MAP for _ts_epoch
ATLAS_OBS=$(echo "$ATLAS_RAW" | jq --argjson emap "$EPOCH_MAP" --argjson cutoff "$RECENT_CUTOFF" '
  def extract_tags(content):
    # Accept several markers, defensively. Each branch returns an array of strings.
    [
      # **Tags**: a, b, c   (markdown emphasis)
      ( content | scan("(?im)^[*_]{0,2}[Tt]ags[*_]{0,2}\\s*:\\s*([^\\n]+)") | .[0]
        | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length>0))
      )?,
      # tags: [a, b, c]     (yaml inline array)
      ( content | scan("(?im)^tags\\s*:\\s*\\[([^\\]]+)\\]") | .[0]
        | split(",") | map(gsub("^\\s+|\\s+$|^[\"\\u0027]|[\"\\u0027]$"; "")) | map(select(length>0))
      )?,
      # tags: a, b, c       (yaml inline plain)
      ( content | scan("(?im)^tags\\s*:\\s*([^\\[\\n][^\\n]*)") | .[0]
        | split(",") | map(gsub("^\\s+|\\s+$|^[\"\\u0027]|[\"\\u0027]$"; "")) | map(select(length>0))
      )?
    ]
    | map(select(. != null)) | add // []
    | map(ascii_downcase | gsub("^#"; "") | gsub("^\\s+|\\s+$"; ""))
    | map(select(length>0 and length<64))
    | unique;

  map(
    . as $o
    | . + {
        # _is_atlas: only obs whose topic_key starts with "atlas/" are well-formed
        # for By-Domain grouping. Others go to a _malformed bucket (FIX 3).
        _is_atlas: (($o.topic_key // "") | startswith("atlas/")),
        _domain: (
          if (($o.topic_key // "") | startswith("atlas/")) then
            ($o.topic_key | split("/") | (if length >= 2 then .[1] else "unknown" end)
              | (if . == "" then "unknown" else . end))
          else
            "_malformed"
          end
        ),
        _ts: ($o.created_at // ""),
        _ts_epoch: ($emap[($o.id|tostring)] // 0),
        _ts_date: (($o.created_at // "") | .[0:10]),
        _source: (
          (($o.content // "") | capture("\\*\\*Source\\*\\*:\\s*(?<url>\\S+)"; "n")? // null)
          | if . then .url else "" end
        ),
        _tags: extract_tags($o.content // ""),
        _is_recent: (($emap[($o.id|tostring)] // 0) >= $cutoff)
      }
  )
')

# 4. Domain grouping — only include obs with well-formed topic_key (atlas/<domain>/...).
#    Malformed obs (topic_key not starting with "atlas/") go to a separate bucket
#    rendered at the END of the index — NOT mixed into "By Domain" (FIX 3).
GROUPED=$(echo "$ATLAS_OBS" | jq '
  [.[] | select(._is_atlas)]
  | group_by(._domain)
  | map({
      domain: (.[0]._domain),
      entries: (. | sort_by(-(._ts_epoch), (.title // "")))
    })
  | sort_by(-(.entries | length), .domain)
')
DOMAINS=$(echo "$GROUPED" | jq 'length')

# 4b. Malformed bucket — type=atlas obs whose topic_key is NOT atlas/<domain>/<slug>.
#     Surfaced at end of the index so they're visible without polluting domain groups.
MALFORMED_OBS=$(echo "$ATLAS_OBS" | jq '
  [.[] | select(._is_atlas | not)]
  | sort_by(-(._ts_epoch), (.title // ""))
')
MALFORMED_COUNT=$(echo "$MALFORMED_OBS" | jq 'length')

# 5. Tag grouping — flatten (obs × tag), group by tag, sort by count desc
TAGGED=$(echo "$ATLAS_OBS" | jq '
  [ .[] as $o | $o._tags[]? | {tag: ., obs: $o} ]
  | group_by(.tag)
  | map({
      tag: (.[0].tag),
      entries: (. | map(.obs) | sort_by(-(._ts_epoch), (.title // "")))
    })
  | sort_by(-(.entries | length), .tag)
')
TAGS=$(echo "$TAGGED" | jq 'length')

# 6. Recent slice (within RECENT_DAYS)
RECENT=$(echo "$ATLAS_OBS" | jq '
  [ .[] | select(._is_recent) ]
  | sort_by(-(._ts_epoch))
')
RECENT_COUNT=$(echo "$RECENT" | jq 'length')

# 7. Range stats — oldest / newest by ts_date (filter out empties)
OLDEST=$(echo "$ATLAS_OBS" | jq -r '[.[] | select(._ts_epoch > 0)] | sort_by(._ts_epoch) | (.[0]._ts_date // "")')
NEWEST=$(echo "$ATLAS_OBS" | jq -r '[.[] | select(._ts_epoch > 0)] | sort_by(-(._ts_epoch)) | (.[0]._ts_date // "")')

# 8. Compute days-since-newest for the "no recent entries" message
if [[ -n "$NEWEST" ]]; then
  NEWEST_EPOCH=$(date -u -d "${NEWEST}T00:00:00Z" +%s 2>/dev/null || echo 0)
  if [[ "$NEWEST_EPOCH" -gt 0 ]]; then
    DAYS_SINCE=$(( (NOW_EPOCH - NEWEST_EPOCH) / 86400 ))
  else
    DAYS_SINCE="?"
  fi
else
  DAYS_SINCE="?"
fi

# 9. Top-3 domains and tags as compact JSON for the stdout summary
TOP3_DOMAINS=$(echo "$GROUPED" | jq -c '[.[0:3] | .[] | {domain, count: (.entries | length)}]')
TOP3_TAGS=$(echo "$TAGGED" | jq -c '[.[0:3] | .[] | {tag, count: (.entries | length)}]')

# 10. Write Atlas-Index.md atomically (write to .tmp, then mv -f)
{
  echo "<!-- Auto-generated by skill 'atlas-index'. DO NOT EDIT BY HAND — regenerate with the skill. -->"
  echo "<!-- Last regenerated: ${TIMESTAMP} -->"
  echo "<!-- Project: ${PROJECT} | Total: ${TOTAL} | Domains: ${DOMAINS} | Tags: ${TAGS} | Recent (${RECENT_DAYS}d): ${RECENT_COUNT} | Range: ${OLDEST:-?} → ${NEWEST:-?} -->"
  echo ""
  echo "# Atlas Index — project: \`${PROJECT}\`"
  echo ""
  echo "${TOTAL} entries from ${DOMAINS} unique sources, ${TAGS} unique tags. Last regenerated ${TIMESTAMP}."
  echo ""
  echo "**Range**: ${OLDEST:-?} → ${NEWEST:-?}  "
  echo "**Recent (last ${RECENT_DAYS} days)**: ${RECENT_COUNT}"
  echo ""

  # ── Recent section ────────────────────────────────────────────────────────
  echo "## Recent (last ${RECENT_DAYS} days) — ${RECENT_COUNT} entries"
  echo ""
  if [[ "$RECENT_COUNT" -eq 0 ]]; then
    echo "_Sin entries recientes (última inyección hace ${DAYS_SINCE} días)._"
  else
    echo "$RECENT" | jq -r '.[] |
      "- [#" + (.id|tostring) + "] **" + (.title // "untitled") + "** — `" + (.topic_key // "no-topic") + "`" +
      (if ._source != "" then " — <" + ._source + ">" else "" end) +
      (if ._ts_date != "" then " — _" + ._ts_date + "_" else "" end)
    '
  fi
  echo ""

  # ── By Domain section ─────────────────────────────────────────────────────
  # FIX 9 — wikilinks must match heading text literally. Headings are clean
  # ("### domain") and the count is rendered on the line below.
  echo "## By Domain"
  echo ""
  echo "$GROUPED" | jq -r '.[] |
    "- [[#" + .domain + "|" + .domain + "]] (" + (.entries | length | tostring) + ")"
  '
  echo ""

  echo "$GROUPED" | jq -r '.[] |
    "### " + .domain + "\n" +
    "_" + (.entries | length | tostring) + " entries_\n\n" +
    (
      .entries
      | map(
          "- [#" + (.id|tostring) + "] **" + (.title // "untitled") + "** — `" + (.topic_key // "no-topic") + "`" +
          (if ._source != "" then " — <" + ._source + ">" else "" end) +
          (if ._ts_date != "" then " — _" + ._ts_date + "_" else "" end)
        )
      | join("\n")
    ) +
    "\n"
  '

  # ── By Tag section (only if any tags exist) ───────────────────────────────
  if [[ "$TAGS" -gt 0 ]]; then
    echo "## By Tag"
    echo ""
    echo "$TAGGED" | jq -r '.[] |
      "- #" + .tag + " (" + (.entries | length | tostring) + ")"
    '
    echo ""

    echo "$TAGGED" | jq -r '.[] |
      "### #" + .tag + "\n" +
      "_" + (.entries | length | tostring) + " entries_\n\n" +
      (
        .entries
        | map(
            "- [#" + (.id|tostring) + "] **" + (.title // "untitled") + "** — `" + (.topic_key // "no-topic") + "`"
          )
        | join("\n")
      ) +
      "\n"
    '
  fi

  # ── Malformed bucket — at the END (FIX 3) ─────────────────────────────────
  if [[ "$MALFORMED_COUNT" -gt 0 ]]; then
    echo "## _Malformed (topic_key no es atlas/<domain>/<slug>)"
    echo ""
    echo "_${MALFORMED_COUNT} entries con topic_key no conforme. Considerar editar con \`atlas-edit\` o limpiar con \`atlas-cleanup\`._"
    echo ""
    echo "$MALFORMED_OBS" | jq -r '.[] |
      "- [#" + (.id|tostring) + "] **" + (.title // "untitled") + "** — `" + (.topic_key // "no-topic") + "`" +
      (if ._source != "" then " — <" + ._source + ">" else "" end) +
      (if ._ts_date != "" then " — _" + ._ts_date + "_" else "" end)
    '
    echo ""
  fi
} > "$INDEX_TMP"

# 11. Atomic rename — never leave a partial file (uses mv_with_retry from top).
if ! mv_with_retry "$INDEX_TMP" "$INDEX_PATH"; then
  jq -nc \
    --arg src "$INDEX_TMP" \
    --arg dst "$INDEX_PATH" \
    '{success: false, error: ("mv failed after 3 retries (file lock?). tmp kept for debug: " + $src + " → " + $dst)}' >&2
  # Preserve the tmp for debugging — clear trap so cleanup_tmp does NOT delete it.
  trap - EXIT
  exit 0
fi
# Successful move — clear INDEX_TMP so trap is a no-op.
INDEX_TMP=""

# 12. Emit summary JSON to stdout (consumed by SKILL.md to report to user)
jq -nc \
  --arg path "$INDEX_PATH" \
  --arg project "$PROJECT" \
  --argjson total "$TOTAL" \
  --argjson domains "$DOMAINS" \
  --argjson tags "$TAGS" \
  --argjson recent_count "$RECENT_COUNT" \
  --arg oldest "${OLDEST:-}" \
  --arg newest "${NEWEST:-}" \
  --arg timestamp "$TIMESTAMP" \
  --argjson top3_domains "$TOP3_DOMAINS" \
  --argjson top3_tags "$TOP3_TAGS" \
  '{
    path: $path,
    project: $project,
    total: $total,
    domains: $domains,
    tags: $tags,
    recent_count: $recent_count,
    oldest: (if $oldest == "" then null else $oldest end),
    newest: (if $newest == "" then null else $newest end),
    timestamp: $timestamp,
    top3_domains: $top3_domains,
    top3_tags: $top3_tags
  }'

exit 0
