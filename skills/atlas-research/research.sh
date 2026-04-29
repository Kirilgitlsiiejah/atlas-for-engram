#!/bin/bash
# atlas-research — capture-classify one-shot. Reads stdin JSON con keys:
#   { "title"?, "source_url"?, "tags"?, "body" (req), "project" (req) }
# Pool-first write order: escribe ${ATLAS_VAULT}/atlas-pool/<slug>.md ANTES de
# POSTear a engram. Si engram cae, el .md persiste para recovery via bulk-inject.
#
# Exit:
#   0 = pool ok + engram ok
#   1 = pool ok + engram fail (.md preservado)
#   2 = pool fail (no engram contact)
#
# Stdout (single-line JSON):
#   {success, wrote_pool, wrote_engram, pool_path, topic_key, obs_id, error}
#
# Defensive: NO `set -euo pipefail`. Errors squelched + reported via JSON.

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
  detect_vault() {
    local override="${1:-}"
    if [[ -n "$override" ]]; then printf '%s' "$override"; return 0; fi
    [[ -n "${ATLAS_VAULT:-}" ]] && { printf '%s' "$ATLAS_VAULT"; return 0; }
    [[ -n "${VAULT_ROOT:-}" ]] && { printf '%s' "$VAULT_ROOT"; return 0; }
    printf '%s' "${HOME}/vault"
  }
fi

ENGRAM_HOST="${ENGRAM_HOST:-127.0.0.1:7437}"

_ar_emit_and_exit() {
  # $1 = exit_code, $2 = JSON
  printf '%s\n' "$2"
  exit "$1"
}

_ar_slugify() {
  local s="${1:-}"
  s="${s,,}"
  s="${s//[^a-z0-9-]/-}"
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"; s="${s%-}"
  printf '%s' "$s"
}

_ar_domain_from_url() {
  local url="${1:-}"
  [[ -z "$url" ]] && { printf '%s' "unknown"; return 0; }
  local host
  host="${url#*://}"
  host="${host%%/*}"
  host="${host%%\?*}"
  host="${host%%#*}"
  host="${host%%:*}"
  host="${host#www.}"
  host="${host,,}"
  [[ -z "$host" ]] && host="unknown"
  printf '%s' "$host"
}

# ─── Read + validate stdin JSON ──────────────────────────────────────────────
INPUT=""
if [[ -t 0 ]]; then
  _ar_emit_and_exit 2 "$(jq -nc '{success:false, wrote_pool:false, wrote_engram:false, error:"stdin tty: expected JSON via pipe"}')"
fi
INPUT=$(jq -c . 2>/dev/null) || INPUT=""
if [[ -z "$INPUT" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc '{success:false, wrote_pool:false, wrote_engram:false, error:"stdin not valid JSON"}')"
fi

PROJECT=$(printf '%s' "$INPUT" | jq -r '.project // ""' 2>/dev/null)
BODY=$(printf '%s' "$INPUT" | jq -r '.body // ""' 2>/dev/null)
IN_TITLE=$(printf '%s' "$INPUT" | jq -r '.title // ""' 2>/dev/null)
SOURCE_URL=$(printf '%s' "$INPUT" | jq -r '.source_url // ""' 2>/dev/null)
TAGS_JSON=$(printf '%s' "$INPUT" | jq -c '.tags // []' 2>/dev/null) || TAGS_JSON="[]"
VAULT_FLAG=$(printf '%s' "$INPUT" | jq -r '.vault // ""' 2>/dev/null)

if [[ -z "$PROJECT" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc '{success:false, wrote_pool:false, wrote_engram:false, error:"missing required field: project"}')"
fi
if [[ -z "$BODY" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc '{success:false, wrote_pool:false, wrote_engram:false, error:"missing required field: body"}')"
fi

# ─── Derive title (input → first H1 → URL last segment) ──────────────────────
TITLE="$IN_TITLE"
if [[ -z "$TITLE" ]]; then
  TITLE=$(printf '%s' "$BODY" | awk '/^# / { sub(/^# +/,""); print; exit }' 2>/dev/null) || TITLE=""
fi
if [[ -z "$TITLE" && -n "$SOURCE_URL" ]]; then
  # Last URL path segment, strip query/fragment, decode minimal.
  local_path="${SOURCE_URL#*://}"
  local_path="${local_path#*/}"
  local_path="${local_path%%\?*}"
  local_path="${local_path%%#*}"
  local_path="${local_path%/}"
  TITLE="${local_path##*/}"
fi
if [[ -z "$TITLE" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc '{success:false, wrote_pool:false, wrote_engram:false, error:"could not derive title (input.title empty, no H1 in body, no source_url)"}')"
fi

# ─── Slug + topic_key ────────────────────────────────────────────────────────
SLUG=$(_ar_slugify "$TITLE")
if [[ -z "$SLUG" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc '{success:false, wrote_pool:false, wrote_engram:false, error:"slug empty after derivation"}')"
fi
DOMAIN=$(_ar_domain_from_url "$SOURCE_URL")
TOPIC_KEY="atlas/${DOMAIN}/${SLUG}"

# ─── Resolve vault + pool path ───────────────────────────────────────────────
VAULT=$(detect_vault "$VAULT_FLAG" 2>/dev/null) || VAULT=""
if [[ -z "$VAULT" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc --arg tk "$TOPIC_KEY" '{success:false, wrote_pool:false, wrote_engram:false, topic_key:$tk, error:"vault unresolved"}')"
fi
POOL_DIR="${VAULT}/atlas-pool"
POOL_PATH="${POOL_DIR}/${SLUG}.md"

# ─── Build .md with frontmatter ──────────────────────────────────────────────
CLIPPED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || CLIPPED_AT=""

# YAML frontmatter via yq (handles escaping). Build a tiny JSON, convert to YAML.
FM_JSON=$(jq -nc \
  --arg t "$TITLE" \
  --arg s "${SOURCE_URL:-}" \
  --arg c "$CLIPPED_AT" \
  --argjson tags "$TAGS_JSON" \
  '{title:$t} + (if $s == "" then {} else {source_url:$s} end) + {clipped:$c, tags:$tags}')
FM_YAML=$(printf '%s' "$FM_JSON" | yq -p=json -o=yaml 2>/dev/null) || FM_YAML=""
if [[ -z "$FM_YAML" ]]; then
  _ar_emit_and_exit 2 "$(jq -nc --arg tk "$TOPIC_KEY" '{success:false, wrote_pool:false, wrote_engram:false, topic_key:$tk, error:"yq frontmatter render failed"}')"
fi

# ─── Pool-first write (atomic via .tmp + mv) ─────────────────────────────────
if ! mkdir -p "$POOL_DIR" 2>/dev/null; then
  _ar_emit_and_exit 2 "$(jq -nc --arg p "$POOL_DIR" --arg tk "$TOPIC_KEY" '{success:false, wrote_pool:false, wrote_engram:false, topic_key:$tk, error:("could not create pool dir: " + $p)}')"
fi

TMP_PATH="${POOL_PATH}.tmp.$$"
# Ensure FM_YAML ends with a newline so the closing --- starts on its own line.
[[ "${FM_YAML: -1}" != $'\n' ]] && FM_YAML+=$'\n'
{
  printf -- '---\n%s---\n\n%s\n' "$FM_YAML" "$BODY"
} > "$TMP_PATH" 2>/dev/null
WRITE_RC=$?
if [[ $WRITE_RC -ne 0 || ! -s "$TMP_PATH" ]]; then
  rm -f "$TMP_PATH" 2>/dev/null || true
  _ar_emit_and_exit 2 "$(jq -nc --arg p "$POOL_PATH" --arg tk "$TOPIC_KEY" '{success:false, wrote_pool:false, wrote_engram:false, pool_path:$p, topic_key:$tk, error:"pool write failed"}')"
fi
if ! mv -f "$TMP_PATH" "$POOL_PATH" 2>/dev/null; then
  rm -f "$TMP_PATH" 2>/dev/null || true
  _ar_emit_and_exit 2 "$(jq -nc --arg p "$POOL_PATH" --arg tk "$TOPIC_KEY" '{success:false, wrote_pool:false, wrote_engram:false, pool_path:$p, topic_key:$tk, error:"pool atomic rename failed"}')"
fi

# ─── Engram POST (after pool is durable) ─────────────────────────────────────
# Health preflight: skip if engram down, but pool .md is preserved → exit 1.
if ! curl -sf "http://${ENGRAM_HOST}/health" --max-time 1 >/dev/null 2>&1; then
  _ar_emit_and_exit 1 "$(jq -nc --arg p "$POOL_PATH" --arg tk "$TOPIC_KEY" --arg h "$ENGRAM_HOST" \
    '{success:false, wrote_pool:true, wrote_engram:false, pool_path:$p, topic_key:$tk, error:("engram unreachable: http://" + $h), retry:"bulk-inject.sh --project <project>"}')"
fi

# Session preamble (engram requires session_id on POST /observations).
SESSION_ID="atlas-research-${PROJECT}-$(date +%s)-$$"
SESSION_PAYLOAD=$(jq -nc --arg id "$SESSION_ID" --arg p "$PROJECT" '{id:$id, project:$p}')
if ! curl -sS --fail -m 5 -X POST \
      -H "Content-Type: application/json" \
      -d "$SESSION_PAYLOAD" \
      "http://${ENGRAM_HOST}/sessions" >/dev/null 2>&1; then
  _ar_emit_and_exit 1 "$(jq -nc --arg p "$POOL_PATH" --arg tk "$TOPIC_KEY" \
    '{success:false, wrote_pool:true, wrote_engram:false, pool_path:$p, topic_key:$tk, error:"engram session preamble failed", retry:"bulk-inject.sh --project <project>"}')"
fi

CONTENT=$(printf '**Source**: %s\n**Clipped**: %s\n---\n%s' "${SOURCE_URL:-manual clip}" "$CLIPPED_AT" "$BODY")
PAYLOAD=$(jq -nc \
  --arg sid "$SESSION_ID" \
  --arg proj "$PROJECT" \
  --arg t "$TITLE" \
  --arg tk "$TOPIC_KEY" \
  --arg src "${SOURCE_URL:-}" \
  --arg c "$CONTENT" \
  --argjson tags "$TAGS_JSON" \
  '{
    session_id:$sid, project:$proj, type:"atlas",
    title:$t, topic_key:$tk,
    source_url:(if $src=="" then null else $src end),
    tags:$tags, content:$c
  }')

OBS_ID=$(engram_post_observation "$PAYLOAD") || OBS_ID=""
if [[ -z "$OBS_ID" ]]; then
  _ar_emit_and_exit 1 "$(jq -nc --arg p "$POOL_PATH" --arg tk "$TOPIC_KEY" \
    '{success:false, wrote_pool:true, wrote_engram:false, pool_path:$p, topic_key:$tk, error:"engram POST failed", retry:"bulk-inject.sh --project <project>"}')"
fi

OBS_ID_NUM=$(printf '%s' "$OBS_ID" | jq -R 'tonumber? // .' 2>/dev/null) || OBS_ID_NUM="\"$OBS_ID\""
_ar_emit_and_exit 0 "$(jq -nc --arg p "$POOL_PATH" --arg tk "$TOPIC_KEY" --argjson id "$OBS_ID_NUM" \
  '{success:true, wrote_pool:true, wrote_engram:true, pool_path:$p, topic_key:$tk, obs_id:$id, error:null}')"
