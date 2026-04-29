#!/bin/bash
# bulk-inject — sweep atlas-pool top-level clip .md files and POST each to
# engram in parallel via xargs -P. Idempotent via topic_key upsert (engram native).
#
# Usage:
#   bulk-inject.sh --project <name> [--vault <path>] [--dry-run] [--parallelism N]
#
# Exit:
#   0 = all files succeeded
#   1 = partial (some failed)
#   2 = preflight failure (bad flags, engram unreachable, vault missing, ...)
#
# Stdout: single-line JSON summary. See README "AI-first usage".
# Stderr: human diagnostics (per-file errors, preflight warnings).
#
# Defensive style: NO `set -euo pipefail`. Errors squelched with `2>/dev/null || true`.

# ─── Source shared helpers (with inline byte-identical fallback) ─────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null)" || SCRIPT_DIR="."
ATLAS_HELPERS="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}/scripts/_helpers.sh"
if [[ -f "$ATLAS_HELPERS" ]]; then
  # shellcheck disable=SC1090
  source "$ATLAS_HELPERS"
else
  # === BEGIN INLINE FALLBACK engram_post_observation ===
  engram_post_observation() {
    local payload="${1:-}" host="${ENGRAM_HOST:-127.0.0.1:7437}" attempt=0 max=3
    [[ -z "$payload" ]] && return 1
    while [[ $attempt -lt $max ]]; do
      local raw http body
      raw=$(curl -sS -m 10 -w '\n%{http_code}' -X POST \
        -H 'Content-Type: application/json' -d "$payload" \
        "http://${host}/observations" 2>/dev/null) || { attempt=$((attempt+1)); sleep 0.2; continue; }
      http="${raw##*$'\n'}"; body="${raw%$'\n'*}"
      if [[ "$http" == "200" || "$http" == "201" ]]; then
        local obs_id
        obs_id=$(printf '%s' "$body" | jq -r '.id // empty' 2>/dev/null)
        [[ -n "$obs_id" && "$obs_id" != "null" ]] && { printf '%s' "$obs_id"; return 0; }
        return 1
      fi
      [[ "$http" =~ ^5 ]] || return 1
      attempt=$((attempt+1)); sleep "0.$((1+attempt*2))"
    done
    return 1
  }
  # === END INLINE FALLBACK engram_post_observation ===
  # Minimal detect_vault fallback (cascade L2-L5; no walk-up — ok for bulk worker context).
  detect_vault() {
    local override="${1:-}"
    if [[ -n "$override" ]]; then printf '%s' "$override"; return 0; fi
    [[ -n "${ATLAS_VAULT:-}" ]] && { printf '%s' "$ATLAS_VAULT"; return 0; }
    [[ -n "${VAULT_ROOT:-}" ]] && { printf '%s' "$VAULT_ROOT"; return 0; }
    printf '%s' "${HOME}/vault"
  }
fi

ENGRAM_HOST="${ENGRAM_HOST:-127.0.0.1:7437}"

# ─── Helpers (worker + emitters) ─────────────────────────────────────────────

_bi_emit_summary_and_exit() {
  # $1 = exit_code, $2 = JSON payload
  printf '%s\n' "$2"
  exit "$1"
}

_bi_slugify() {
  # Lowercase, replace non-[a-z0-9-] with -, collapse repeats, trim.
  local s="${1:-}"
  s="${s,,}"
  s="${s//[^a-z0-9-]/-}"
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"; s="${s%-}"
  printf '%s' "$s"
}

_bi_domain_from_url() {
  # Extract host, strip leading www., lowercase. Empty input → "unknown".
  local url="${1:-}"
  [[ -z "$url" ]] && { printf '%s' "unknown"; return 0; }
  local host
  # Strip scheme
  host="${url#*://}"
  # Strip path/query/fragment
  host="${host%%/*}"
  host="${host%%\?*}"
  host="${host%%#*}"
  # Strip port
  host="${host%%:*}"
  # Strip leading www.
  host="${host#www.}"
  host="${host,,}"
  [[ -z "$host" ]] && host="unknown"
  printf '%s' "$host"
}

# Worker invoked by xargs (one .md path per call).
# Reads frontmatter via yq, derives topic_key, POSTs, emits 1 NDJSON line.
# REQUIRES env: ATLAS_BI_SESSION_ID, ATLAS_BI_PROJECT, ATLAS_BI_DRY_RUN.
_bulk_worker() {
  local file="${1:-}"
  if [[ -z "$file" || ! -f "$file" ]]; then
    jq -nc --arg p "$file" '{path: $p, status: "failed", topic_key: null, obs_id: null, error: "file not found"}'
    return 0
  fi

  # yq v4 frontmatter extraction. `--front-matter=extract` reads only the YAML
  # block. Resolve URL canonically as source_url ?? source ?? "" so legacy Web
  # Clipper notes still derive the correct domain/topic_key.
  local fm_title fm_url fm_tags
  fm_title=$(yq --front-matter=extract '.title // ""' "$file" 2>/dev/null) || fm_title=""
  fm_url=$(yq --front-matter=extract '.source_url // .source // ""' "$file" 2>/dev/null) || fm_url=""
  fm_tags=$(yq --front-matter=extract '.tags // []' -o=json "$file" 2>/dev/null) || fm_tags="[]"
  fm_title="${fm_title//$'\n'/}"
  fm_url="${fm_url//$'\n'/}"

  # Derive title fallback chain: frontmatter → first H1 in body → filename.
  local title="$fm_title"
  if [[ -z "$title" ]]; then
    # First H1 from body. Read file via redirection (no cat).
    local first_h1
    first_h1=$(awk '/^# / { sub(/^# +/,""); print; exit }' "$file" 2>/dev/null) || first_h1=""
    title="$first_h1"
  fi
  if [[ -z "$title" ]]; then
    local base
    base=$(basename "$file" .md 2>/dev/null) || base=""
    title="$base"
  fi
  if [[ -z "$title" ]]; then
    jq -nc --arg p "$file" '{path: $p, status: "failed", topic_key: null, obs_id: null, error: "no title (frontmatter, H1, nor filename usable)"}'
    return 0
  fi

  # Slug from title
  local slug
  slug=$(_bi_slugify "$title")
  if [[ -z "$slug" ]]; then
    jq -nc --arg p "$file" '{path: $p, status: "failed", topic_key: null, obs_id: null, error: "slug empty after derivation"}'
    return 0
  fi

  local domain
  domain=$(_bi_domain_from_url "$fm_url")
  local topic_key="atlas/${domain}/${slug}"

  # Read full body (post-frontmatter). Use yq's split: pass the raw file content
  # through awk to strip the leading frontmatter block (--- ... ---).
  local body
  body=$(awk '
    BEGIN { fm_open=0; fm_done=0 }
    NR==1 && /^---[[:space:]]*$/ { fm_open=1; next }
    fm_open && /^---[[:space:]]*$/ { fm_open=0; fm_done=1; next }
    fm_open { next }
    { print }
  ' "$file" 2>/dev/null) || body=""

  # Build content payload
  local clipped_at
  clipped_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || clipped_at=""
  local source_line
  if [[ -n "$fm_url" ]]; then source_line="**Source**: ${fm_url}"; else source_line="**Source**: manual clip"; fi
  local content
  content=$(printf '%s\n**Clipped**: %s\n---\n%s' "$source_line" "$clipped_at" "$body")

  # Dry run path: emit planned action without POST.
  if [[ "${ATLAS_BI_DRY_RUN:-0}" == "1" ]]; then
    jq -nc --arg p "$file" --arg tk "$topic_key" --arg t "$title" \
      '{path: $p, status: "planned", topic_key: $tk, obs_id: null, title: $t, error: null}'
    return 0
  fi

  # Build POST payload.
  local payload
  payload=$(jq -nc \
    --arg sid "${ATLAS_BI_SESSION_ID}" \
    --arg proj "${ATLAS_BI_PROJECT}" \
    --arg t "$title" \
    --arg tk "$topic_key" \
    --arg src "${fm_url:-}" \
    --arg c "$content" \
    --argjson tags "$fm_tags" \
    '{
      session_id: $sid,
      project: $proj,
      type: "atlas",
      title: $t,
      topic_key: $tk,
      source_url: (if $src == "" then null else $src end),
      tags: $tags,
      content: $c
    }') || {
      jq -nc --arg p "$file" '{path: $p, status: "failed", topic_key: null, obs_id: null, error: "payload jq build failed"}'
      return 0
    }

  local obs_id
  obs_id=$(engram_post_observation "$payload") || obs_id=""
  if [[ -z "$obs_id" ]]; then
    jq -nc --arg p "$file" --arg tk "$topic_key" \
      '{path: $p, status: "failed", topic_key: $tk, obs_id: null, error: "engram POST failed"}'
    return 0
  fi

  jq -nc --arg p "$file" --arg tk "$topic_key" --arg id "$obs_id" \
    '{path: $p, status: "ok", topic_key: $tk, obs_id: ($id|tonumber? // $id), error: null}'
  return 0
}

# Export helpers + state for xargs subshells.
export -f engram_post_observation _bulk_worker _bi_slugify _bi_domain_from_url
export ENGRAM_HOST

# ─── Flag parser ─────────────────────────────────────────────────────────────
PROJECT=""
VAULT_FLAG=""
DRY_RUN=0
PARALLELISM=4

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project=*)     PROJECT="${1#--project=}"; shift ;;
    --project)       PROJECT="${2:-}"; shift 2 ;;
    --vault=*)       VAULT_FLAG="${1#--vault=}"; shift ;;
    --vault)         VAULT_FLAG="${2:-}"; shift 2 ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --parallelism=*) PARALLELISM="${1#--parallelism=}"; shift ;;
    --parallelism)   PARALLELISM="${2:-}"; shift 2 ;;
    -h|--help)
      printf '%s\n' "Usage: bulk-inject.sh --project <name> [--vault <path>] [--dry-run] [--parallelism N]" >&2
      exit 2
      ;;
    *)
      printf 'error: unknown flag: %s\n' "$1" >&2
      _bi_emit_summary_and_exit 2 "$(jq -nc --arg f "$1" '{success:false, error: ("unknown flag: " + $f)}')"
      ;;
  esac
done

# Validate --project (required)
if [[ -z "$PROJECT" ]]; then
  printf 'error: --project <name> required\n' >&2
  _bi_emit_summary_and_exit 2 "$(jq -nc '{success:false, error:"--project <name> required"}')"
fi

# Validate --parallelism (positive int, clamp at 8)
if [[ ! "$PARALLELISM" =~ ^[1-9][0-9]*$ ]]; then
  printf 'error: --parallelism must be positive integer (got: %s)\n' "$PARALLELISM" >&2
  _bi_emit_summary_and_exit 2 "$(jq -nc --arg p "$PARALLELISM" '{success:false, error: ("--parallelism must be positive integer (got: " + $p + ")")}')"
fi
if [[ "$PARALLELISM" -gt 8 ]]; then PARALLELISM=8; fi

# ─── Resolve vault ───────────────────────────────────────────────────────────
VAULT=$(detect_vault "$VAULT_FLAG" 2>/dev/null) || VAULT=""
if [[ -z "$VAULT" ]]; then
  _bi_emit_summary_and_exit 2 "$(jq -nc '{success:false, error:"vault unresolved"}')"
fi

POOL_DIR="${VAULT}/atlas-pool"
if [[ ! -d "$POOL_DIR" ]]; then
  _bi_emit_summary_and_exit 2 "$(jq -nc --arg p "$POOL_DIR" '{success:false, error: ("atlas-pool dir missing: " + $p)}')"
fi

# ─── List atlas clip candidates (top-level only, skip README docs) ───────────
shopt -s nullglob
files=("${POOL_DIR}"/*.md)
shopt -u nullglob

clip_files=()
for file in "${files[@]}"; do
  [[ ! -f "$file" ]] && continue
  [[ "${file##*/}" == "README.md" ]] && continue
  clip_files+=("$file")
done

files=("${clip_files[@]}")

TOTAL="${#files[@]}"
if [[ "$TOTAL" -eq 0 ]]; then
  _bi_emit_summary_and_exit 0 "$(jq -nc --arg proj "$PROJECT" --arg v "$VAULT" --argjson dr "$DRY_RUN" \
    '{success:true, project:$proj, vault:$v, dryRun:($dr|tonumber|.>0), total:0, succeeded:0, failed:0, files:[], elapsed_ms:0}')"
fi

# ─── Engram preflight (skip in dry-run) + session preamble ───────────────────
START_MS=$(date +%s%3N 2>/dev/null) || START_MS=0
SESSION_ID=""

if [[ "$DRY_RUN" == "0" ]]; then
  if ! curl -sf "http://${ENGRAM_HOST}/health" --max-time 1 >/dev/null 2>&1; then
    _bi_emit_summary_and_exit 2 "$(jq -nc --arg h "$ENGRAM_HOST" '{success:false, error: ("engram unreachable: http://" + $h)}')"
  fi
  SESSION_ID="atlas-bulk-${PROJECT}-$(date +%s)-$$"
  SESSION_PAYLOAD=$(jq -nc --arg id "$SESSION_ID" --arg p "$PROJECT" '{id:$id, project:$p}')
  if ! curl -sS --fail -m 5 -X POST \
        -H "Content-Type: application/json" \
        -d "$SESSION_PAYLOAD" \
        "http://${ENGRAM_HOST}/sessions" >/dev/null 2>&1; then
    _bi_emit_summary_and_exit 2 "$(jq -nc --arg h "$ENGRAM_HOST" '{success:false, error: ("engram session preamble failed at http://" + $h + "/sessions")}')"
  fi
fi

export ATLAS_BI_SESSION_ID="$SESSION_ID"
export ATLAS_BI_PROJECT="$PROJECT"
export ATLAS_BI_DRY_RUN="$DRY_RUN"

# ─── xargs -P parallel fan-out ───────────────────────────────────────────────
# Use NUL-delimited stream (printf '%s\0') so paths con espacios/newlines no rompen.
NDJSON_TMP="${TMPDIR:-/tmp}/atlas-bulk-$$.ndjson"
: > "$NDJSON_TMP" 2>/dev/null || true

printf '%s\0' "${files[@]}" \
  | xargs -0 -n 1 -P "$PARALLELISM" -I {} bash -c '_bulk_worker "$@"' _ {} \
  >> "$NDJSON_TMP" 2>/dev/null || true

# Aggregate via jq -s
AGG_FILES_JSON="[]"
if [[ -s "$NDJSON_TMP" ]]; then
  AGG_FILES_JSON=$(jq -cs '.' "$NDJSON_TMP" 2>/dev/null) || AGG_FILES_JSON="[]"
fi
rm -f "$NDJSON_TMP" 2>/dev/null || true

SUCCEEDED=$(printf '%s' "$AGG_FILES_JSON" | jq '[.[] | select(.status == "ok" or .status == "planned")] | length' 2>/dev/null) || SUCCEEDED=0
FAILED=$(printf '%s' "$AGG_FILES_JSON" | jq '[.[] | select(.status == "failed")] | length' 2>/dev/null) || FAILED=0

END_MS=$(date +%s%3N 2>/dev/null) || END_MS=0
ELAPSED=$((END_MS - START_MS))
[[ "$ELAPSED" -lt 0 ]] && ELAPSED=0

DRY_RUN_BOOL="false"; [[ "$DRY_RUN" == "1" ]] && DRY_RUN_BOOL="true"
SUCCESS_BOOL="true";  [[ "$FAILED" -gt 0 ]] && SUCCESS_BOOL="false"

SUMMARY=$(jq -nc \
  --argjson succ "$SUCCESS_BOOL" \
  --arg proj "$PROJECT" \
  --arg v "$VAULT" \
  --argjson dr "$DRY_RUN_BOOL" \
  --argjson total "$TOTAL" \
  --argjson sok "$SUCCEEDED" \
  --argjson sfail "$FAILED" \
  --argjson el "$ELAPSED" \
  --argjson files "$AGG_FILES_JSON" \
  '{success:$succ, project:$proj, vault:$v, dryRun:$dr, total:$total, succeeded:$sok, failed:$sfail, files:$files, elapsed_ms:$el}')

printf '%s\n' "$SUMMARY"

if [[ "$FAILED" -eq 0 ]]; then exit 0; else exit 1; fi
