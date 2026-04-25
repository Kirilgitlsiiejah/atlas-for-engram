#!/bin/bash
# atlas-edit — PATCH an existing atlas observation in engram.
#
# Usage:
#   edit.sh <obs_id> <project> <field=value> [<field=value> ...]
#
# Supported fields (passthrough to engram UpdateObservationParams):
#   title, type, content, project, scope, topic_key
#
# Behavior:
#   - PATCH /observations/<id> with JSON body built from field=value pairs.
#   - On 405 Method Not Allowed: fallback to DELETE + POST preserving topic_key
#     (upsert semantics via session reuse). Emits warning on stderr.
#   - On 404 / 500 / network error: returns JSON error on stderr, exit 0.
#
# Output: single-line JSON on stdout (success or error).
# Defensive: never crashes the host shell; always exits 0; errors on stderr.

# Source shared helpers (defensive — fallback inline if missing)
ATLAS_HELPERS="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE%/*}/../..}/scripts/_helpers.sh"
if [[ -f "$ATLAS_HELPERS" ]]; then
  source "$ATLAS_HELPERS"
else
  # Fallback inline: minimal detect_project + resolve_project
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
fi

OBS_ID="${1:-}"
shift 2 2>/dev/null || true

# FIX 14 — ENGRAM_HOST is canonical; ENGRAM_PORT only used as compat shim.
if [[ -z "${ENGRAM_HOST:-}" && -n "${ENGRAM_PORT:-}" ]]; then
  ENGRAM_HOST="http://127.0.0.1:${ENGRAM_PORT}"
fi
ENGRAM_HOST="${ENGRAM_HOST:-http://127.0.0.1:7437}"

# ─── Validate obs_id ──────────────────────────────────────────────────────────
if [[ -z "$OBS_ID" || ! "$OBS_ID" =~ ^[0-9]+$ ]]; then
  jq -nc --arg msg "invalid or missing obs_id (must be positive integer)" \
    '{success: false, error: $msg}' >&2
  exit 0
fi

# ─── Health check ─────────────────────────────────────────────────────────────
if ! curl -sf "${ENGRAM_HOST}/health" --max-time 2 >/dev/null 2>&1; then
  jq -nc --arg host "$ENGRAM_HOST" \
    '{success: false, error: ("engram not reachable at " + $host)}' >&2
  exit 0
fi

# ─── Build PATCH body from field=value args ───────────────────────────────────
BODY="{}"
FIELD_LIST="[]"
ALLOWED_FIELDS="title type content project scope topic_key"

while [[ $# -gt 0 ]]; do
  PAIR="$1"
  shift

  # Must contain '='
  if [[ "$PAIR" != *"="* ]]; then
    jq -nc --arg p "$PAIR" \
      '{success: false, error: ("invalid field assignment (expected key=value): " + $p)}' >&2
    exit 0
  fi

  KEY="${PAIR%%=*}"
  VAL="${PAIR#*=}"

  # Whitelist field name (FIX 11 — pure-bash check, no grep).
  case " $ALLOWED_FIELDS " in
    *" $KEY "*) ;;
    *)
      jq -nc --arg k "$KEY" --arg allowed "$ALLOWED_FIELDS" \
        '{success: false, error: ("field not allowed: " + $k + " (allowed: " + $allowed + ")")}' >&2
      exit 0
      ;;
  esac

  # Append to JSON body and field list (jq handles escaping)
  BODY=$(echo "$BODY" | jq --arg k "$KEY" --arg v "$VAL" '. + {($k): $v}' 2>/dev/null) || {
    jq -nc --arg k "$KEY" '{success: false, error: ("jq failed encoding field: " + $k)}' >&2
    exit 0
  }
  FIELD_LIST=$(echo "$FIELD_LIST" | jq --arg k "$KEY" '. + [$k]' 2>/dev/null) || true
done

# Require at least one field
if [[ "$BODY" == "{}" ]]; then
  jq -nc '{success: false, error: "no fields provided (need at least one key=value)"}' >&2
  exit 0
fi

# ─── Verify obs exists (FIX 8) ────────────────────────────────────────────────
# Engram returns HTTP 200 with empty/null body for nonexistent IDs (no 404).
# So we MUST parse the body and validate .id != null — HTTP code alone lies.
GET_TMP=$(mktemp 2>/dev/null || echo "/tmp/atlas-edit-get-$$.json")
GET_HTTP=$(curl -s -o "$GET_TMP" -w "%{http_code}" \
  "${ENGRAM_HOST}/observations/${OBS_ID}" --max-time 3 2>/dev/null) || GET_HTTP="000"
GET_BODY=""
if [[ -f "$GET_TMP" ]]; then
  GET_BODY=$(<"$GET_TMP")
  rm -f "$GET_TMP" 2>/dev/null
fi

if [[ "$GET_HTTP" != "200" ]]; then
  jq -nc --arg id "$OBS_ID" --arg code "$GET_HTTP" \
    '{success: false, error: ("could not fetch obs #" + $id + ", http=" + $code)}' >&2
  exit 0
fi

# Validate body has .id != null (engram quirk: 200 + empty/null body = nonexistent)
if [[ -z "$GET_BODY" || "$GET_BODY" == "null" ]]; then
  jq -nc --arg id "$OBS_ID" \
    '{success: false, error: ("observation not found: #" + $id + " (empty body)")}' >&2
  exit 0
fi
RESOLVED_ID=$(echo "$GET_BODY" | jq -r '.id // empty' 2>/dev/null)
if [[ -z "$RESOLVED_ID" || "$RESOLVED_ID" == "null" ]]; then
  jq -nc --arg id "$OBS_ID" \
    '{success: false, error: ("observation not found: #" + $id + " (no .id in body)")}' >&2
  exit 0
fi

# ─── FIX 16 — block silent type changes for atlas obs ────────────────────────
# If the user is changing `type` on an obs that is currently type=atlas, require
# an explicit confirmation env var. Otherwise the obs disappears from atlas
# tooling without warning (atlas-index, compare-with-atlas, atlas-cleanup all
# filter on type=atlas).
CURRENT_TYPE=$(echo "$GET_BODY" | jq -r '.type // ""' 2>/dev/null)
NEW_TYPE=$(echo "$BODY" | jq -r '.type // empty' 2>/dev/null)
if [[ "$CURRENT_TYPE" == "atlas" && -n "$NEW_TYPE" && "$NEW_TYPE" != "atlas" ]]; then
  if [[ "${ATLAS_EDIT_CONFIRM_TYPE_CHANGE:-}" != "yes" ]]; then
    jq -nc \
      --arg id "$OBS_ID" \
      --arg new_type "$NEW_TYPE" \
      '{success: false,
        error: ("⚠️ Estás cambiando el type de atlas a \"" + $new_type + "\" (obs #" + $id + "). La obs deja de ser atlas y otros skills (atlas-index, atlas-cleanup, compare-with-atlas) no la van a ver. Para confirmar, re-invocá con env: ATLAS_EDIT_CONFIRM_TYPE_CHANGE=yes")}' >&2
    exit 0
  fi
fi

# ─── PATCH the observation ────────────────────────────────────────────────────
PATCH_TMP=$(mktemp 2>/dev/null || echo "/tmp/atlas-edit-patch-$$.json")
PATCH_HTTP=$(curl -s -o "$PATCH_TMP" -w "%{http_code}" \
  -X PATCH \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  --max-time 10 \
  "${ENGRAM_HOST}/observations/${OBS_ID}" 2>/dev/null) || PATCH_HTTP="000"

PATCH_BODY=""
[[ -f "$PATCH_TMP" ]] && PATCH_BODY=$(<"$PATCH_TMP")
rm -f "$PATCH_TMP" 2>/dev/null || true

# ─── Success path ─────────────────────────────────────────────────────────────
if [[ "$PATCH_HTTP" == "200" ]]; then
  RESULT_ID=$(echo "$PATCH_BODY" | jq -r '.id // empty' 2>/dev/null)
  jq -nc \
    --argjson id "${RESULT_ID:-$OBS_ID}" \
    --argjson fields "$FIELD_LIST" \
    --arg method "PATCH" \
    '{success: true, id: $id, updated_fields: $fields, method: $method}'
  exit 0
fi

# ─── Fallback: 405 → POST-then-DELETE (preserve topic_key, no data loss) ─────
# FIX 6 — original implementation had three problems:
#   1. DELETE-then-POST window of data loss if POST failed.
#   2. Field loss via hardcoded whitelist of 7 fields.
#   3. ID change broke SKILL.md contract.
# Solution: POST first (engram upserts on topic_key), validate the new obs
# exists via GET, ONLY THEN hard-delete the original. Field preservation uses
# native jq merge ($current * $patch) instead of a whitelist.
if [[ "$PATCH_HTTP" == "405" ]]; then
  echo "atlas-edit: PATCH returned 405, attempting POST-then-DELETE fallback (data-loss-safe)" >&2

  # We already have GET_BODY from the verify step above — reuse it.
  CURRENT="$GET_BODY"
  if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
    # Defensive re-fetch in case GET_BODY was lost.
    CURRENT=$(curl -sf "${ENGRAM_HOST}/observations/${OBS_ID}" --max-time 3 2>/dev/null) || {
      jq -nc '{success: false, error: "fallback aborted: cannot re-fetch current obs"}' >&2
      exit 0
    }
  fi

  # Native jq merge — patch wins on overlapping keys, all other fields preserved.
  # Strip server-managed fields (id, created_at, updated_at) so POST creates fresh.
  MERGED=$(echo "$CURRENT" | jq --argjson patch "$BODY" \
    '(. * $patch)
     | del(.id, .created_at, .updated_at)
    ' 2>/dev/null) || {
    jq -nc '{success: false, error: "fallback aborted: jq merge failed"}' >&2
    exit 0
  }

  # Need topic_key to be present for upsert semantics.
  MERGED_TOPIC_KEY=$(echo "$MERGED" | jq -r '.topic_key // empty' 2>/dev/null)
  if [[ -z "$MERGED_TOPIC_KEY" || "$MERGED_TOPIC_KEY" == "null" ]]; then
    jq -nc '{success: false, error: "fallback aborted: merged obs has no topic_key (cannot upsert)"}' >&2
    exit 0
  fi

  # Step 1 — POST the merged obs FIRST. If engram supports topic_key upsert,
  # this either replaces in-place or creates a sibling (depending on backend).
  POST_TMP=$(mktemp 2>/dev/null || echo "/tmp/atlas-edit-post-$$.json")
  POST_HTTP=$(curl -s -o "$POST_TMP" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$MERGED" \
    --max-time 10 \
    "${ENGRAM_HOST}/observations" 2>/dev/null) || POST_HTTP="000"

  POST_RESP=""
  [[ -f "$POST_TMP" ]] && POST_RESP=$(<"$POST_TMP") && rm -f "$POST_TMP" 2>/dev/null

  if [[ "$POST_HTTP" != "201" && "$POST_HTTP" != "200" ]]; then
    jq -nc --arg code "$POST_HTTP" --arg body "$POST_RESP" \
      '{success: false, error: ("fallback POST failed, http=" + $code + " — original obs preserved (no DELETE issued)"), body: $body}' >&2
    exit 0
  fi

  NEW_ID=$(echo "$POST_RESP" | jq -r '.id // empty' 2>/dev/null)
  if [[ -z "$NEW_ID" || "$NEW_ID" == "null" ]]; then
    jq -nc --arg body "$POST_RESP" \
      '{success: false, error: "fallback POST returned no .id — original obs preserved (no DELETE issued)", body: $body}' >&2
    exit 0
  fi

  # Step 2 — VERIFY new obs exists via GET. Only proceed if confirmed.
  VERIFY_BODY=$(curl -sf "${ENGRAM_HOST}/observations/${NEW_ID}" --max-time 3 2>/dev/null)
  VERIFY_ID=$(echo "$VERIFY_BODY" | jq -r '.id // empty' 2>/dev/null)
  if [[ -z "$VERIFY_ID" || "$VERIFY_ID" == "null" ]]; then
    jq -nc --arg new_id "$NEW_ID" \
      '{success: false, error: ("fallback aborted: new obs #" + $new_id + " not retrievable — original obs preserved")}' >&2
    exit 0
  fi

  # Step 3 — only NOW is it safe to hard-delete the original (if NEW_ID != OBS_ID).
  # If engram's upsert reused the same ID (NEW_ID == OBS_ID), there's nothing to delete.
  if [[ "$NEW_ID" != "$OBS_ID" ]]; then
    DEL_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE \
      --max-time 5 \
      "${ENGRAM_HOST}/observations/${OBS_ID}?hard=true" 2>/dev/null) || DEL_HTTP="000"
    # If DELETE fails, the new obs is still there — log warning but report success.
    if [[ "$DEL_HTTP" != "200" ]]; then
      jq -nc \
        --arg new_id "$NEW_ID" \
        --arg old_id "$OBS_ID" \
        --arg del_code "$DEL_HTTP" \
        --argjson fields "$FIELD_LIST" \
        '{
          success: true,
          id: ($new_id | tonumber? // $new_id),
          old_id: ($old_id | tonumber? // $old_id),
          updated_fields: $fields,
          method: "POST-then-DELETE",
          warning: ("new obs #" + $new_id + " created OK, but DELETE of old #" + $old_id + " failed (http=" + $del_code + "). Manual cleanup required.")
        }'
      exit 0
    fi
  fi

  jq -nc \
    --arg new_id "$NEW_ID" \
    --arg old_id "$OBS_ID" \
    --argjson fields "$FIELD_LIST" \
    '{
      success: true,
      id: ($new_id | tonumber? // $new_id),
      old_id: ($old_id | tonumber? // $old_id),
      updated_fields: $fields,
      method: "POST-then-DELETE",
      warning: (if $new_id == $old_id then "engram upsert preserved the ID" else "PATCH unsupported by this engram version; obs ID changed but no data was lost" end)
    }'
  exit 0
fi

# ─── Other failure modes ──────────────────────────────────────────────────────
jq -nc \
  --arg code "$PATCH_HTTP" \
  --arg body "$PATCH_BODY" \
  --arg id "$OBS_ID" \
  '{success: false, error: ("PATCH /observations/" + $id + " failed, http=" + $code), body: $body}' >&2
exit 0
