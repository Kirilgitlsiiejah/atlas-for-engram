#!/bin/bash
# atlas-delete — DELETE atlas observations from engram (individual or bulk)
#
# Defensive script: NO strict mode (no `set -euo pipefail`), exit 0 always,
# errors to stderr as JSON, stdout always parseable JSON when invoked properly.
#
# Modes:
#   --preview [filter args]                : list candidates without deleting
#   --execute <id1> <id2> ... [--with-raw] : delete specific IDs (and optionally raw .md)
#
# Filter args (for --preview):
#   --project=<name>   default "dev"
#   --domain=<domain>  filter by topic_key prefix "atlas/<domain>/"
#   --slug=<pattern>   filter by topic_key suffix or contains "<pattern>"
#   --id=<obs_id>      single ID lookup (returns array of 0 or 1)
#
# Env vars (optional):
#   ENGRAM_HOST  default http://127.0.0.1:7437
#                (compat: if ENGRAM_PORT is set and ENGRAM_HOST is not, derive host from port)
#   VAULT_ROOT   default $HOME/vault
#   ATLAS_POOL   default ${VAULT_ROOT}/atlas-pool
#
# Exit code: always 0 (errors signaled via JSON on stderr).

# Source shared helpers (defensive — fallback inline if missing)
ATLAS_HELPERS="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE%/*}/../..}/scripts/_helpers.sh"
if [[ -f "$ATLAS_HELPERS" ]]; then
  # shellcheck source=/dev/null
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

# FIX 14 — standardize on ENGRAM_HOST. Keep ENGRAM_PORT only as a compat shim
# (derive host from it ONLY if ENGRAM_HOST is not already set).
if [[ -z "${ENGRAM_HOST:-}" && -n "${ENGRAM_PORT:-}" ]]; then
  ENGRAM_HOST="http://127.0.0.1:${ENGRAM_PORT}"
fi
ENGRAM_HOST="${ENGRAM_HOST:-http://127.0.0.1:7437}"
VAULT_ROOT="${VAULT_ROOT:-$HOME/vault}"
ATLAS_POOL="${ATLAS_POOL:-${VAULT_ROOT}/atlas-pool}"

MODE="${1:-}"
shift 2>/dev/null || true

# ─── Helper: emit error JSON to stderr ────────────────────────────────────────
emit_err() {
  local msg="$1"
  jq -nc --arg msg "$msg" '{success: false, error: $msg}' >&2
}

# ─── Helper: health check engram ──────────────────────────────────────────────
engram_alive() {
  curl -sf "${ENGRAM_HOST}/health" --max-time 2 > /dev/null 2>&1
}

# ─── Helper: find raw .md in atlas-pool by slug ───────────────────────────────
# Strategy: extract slug from topic_key (last segment of "atlas/<domain>/<slug>")
# and look for a matching .md file in ATLAS_POOL (recursive).
#
# FIX 10 — safety hardening:
#   1. Validate slug contains ONLY [a-zA-Z0-9_-] before passing to fd
#      (prevents pathological slugs from triggering broad regex matches).
#   2. Match the EXACT filename "<slug>.md" (literal, anchored), not substring.
find_raw_md() {
  local topic_key="$1"
  local slug
  slug=$(echo "$topic_key" | awk -F'/' '{print $NF}')
  if [[ -z "$slug" || "$slug" == "$topic_key" ]]; then
    return 1
  fi
  # Reject slugs with chars that aren't safe identifiers — refuse to search.
  if ! [[ "$slug" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    return 1
  fi
  if [[ ! -d "$ATLAS_POOL" ]]; then
    return 1
  fi
  # Match exactly "<slug>.md" via fd's --glob (anchored to filename).
  local match=""
  local target="${slug}.md"
  if command -v fd > /dev/null 2>&1; then
    # --glob with literal filename + --type f restricts to files only.
    match=$(fd --type f --glob "$target" "$ATLAS_POOL" 2>/dev/null | head -1)
  else
    # Bash glob fallback (case-sensitive). Recursive via shopt globstar.
    shopt -s globstar nullglob 2>/dev/null
    for f in "$ATLAS_POOL"/**/"${target}"; do
      if [[ -f "$f" ]]; then
        match="$f"
        break
      fi
    done
    shopt -u globstar nullglob 2>/dev/null
  fi
  if [[ -n "$match" && -f "$match" ]]; then
    echo "$match"
    return 0
  fi
  return 1
}

# ─── Mode dispatcher ──────────────────────────────────────────────────────────
case "$MODE" in
  --preview)
    PROJECT=""
    DOMAIN=""
    SLUG=""
    OBS_ID=""
    for arg in "$@"; do
      case "$arg" in
        --project=*) PROJECT="${arg#*=}" ;;
        --domain=*)  DOMAIN="${arg#*=}" ;;
        --slug=*)    SLUG="${arg#*=}" ;;
        --id=*)      OBS_ID="${arg#*=}" ;;
      esac
    done
    # Resolve project: respect --project=X if provided, else auto-detect.
    PROJECT=$(resolve_project "$PROJECT")

    if ! engram_alive; then
      emit_err "engram not reachable at ${ENGRAM_HOST}"
      echo "[]"
      exit 0
    fi

    # Special case: single ID lookup → use GET /observations/<id>
    if [[ -n "$OBS_ID" ]]; then
      OBS=$(curl -sf "${ENGRAM_HOST}/observations/${OBS_ID}" --max-time 2 2>/dev/null)
      if [[ -z "$OBS" ]]; then
        echo "[]"
        exit 0
      fi
      # Wrap single obs in array, project minimal fields
      echo "$OBS" | jq -c '[{id, title, topic_key, type, project}] | map(select(.type == "atlas"))'
      exit 0
    fi

    # Bulk preview: GET /observations/recent + client-side filter
    ENCODED_PROJECT=$(printf '%s' "$PROJECT" | jq -sRr @uri)
    URL="${ENGRAM_HOST}/observations/recent?project=${ENCODED_PROJECT}&limit=500"
    RESPONSE=$(curl -sf "$URL" --max-time 5 2>/dev/null)

    if [[ -z "$RESPONSE" ]]; then
      emit_err "empty response from ${URL}"
      echo "[]"
      exit 0
    fi

    if ! echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
      emit_err "unexpected response shape (expected JSON array)"
      echo "[]"
      exit 0
    fi

    # Build filter expression dynamically
    # Always require type=atlas; optionally filter by domain prefix and/or slug substring
    FILTER='.[] | select(.type == "atlas")'
    if [[ -n "$DOMAIN" ]]; then
      FILTER+=" | select((.topic_key // \"\") | startswith(\"atlas/${DOMAIN}/\"))"
    fi
    if [[ -n "$SLUG" ]]; then
      # Match if topic_key contains the slug pattern anywhere
      FILTER+=" | select((.topic_key // \"\") | contains(\"${SLUG}\"))"
    fi

    # Project minimal fields for the preview
    echo "$RESPONSE" | jq -c "[ ${FILTER} | {id, title, topic_key, type, project} ]"
    exit 0
    ;;

  --execute)
    WITH_RAW=false
    IDS=()
    for arg in "$@"; do
      case "$arg" in
        --with-raw) WITH_RAW=true ;;
        --*)        ;;  # ignore unknown flags
        *)          IDS+=("$arg") ;;
      esac
    done

    if [[ ${#IDS[@]} -eq 0 ]]; then
      emit_err "no IDs provided to --execute"
      jq -nc '{success: false, deleted_obs: [], deleted_raw: [], failed: []}'
      exit 0
    fi

    if ! engram_alive; then
      emit_err "engram not reachable at ${ENGRAM_HOST}"
      jq -nc '{success: false, deleted_obs: [], deleted_raw: [], failed: []}'
      exit 0
    fi

    DELETED_OBS=()
    DELETED_RAW=()
    FAILED=()
    # FAILED_REASONS is parallel to FAILED — same indexing, holds reason strings.
    FAILED_REASONS=()
    # Preview of raw files queued for deletion (shown to user before rm).
    RAW_PREVIEW=()

    for id in "${IDS[@]}"; do
      # Skip non-numeric IDs defensively
      if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        FAILED+=("$id")
        FAILED_REASONS+=("non-numeric id")
        continue
      fi

      # FIX 2 — GET the obs FIRST and validate .id != null before DELETE.
      # Engram returns 200 with empty/null body for nonexistent IDs, so HTTP code
      # alone gives false success. The only reliable signal is .id in the body.
      OBS_JSON=$(curl -sf "${ENGRAM_HOST}/observations/${id}" --max-time 2 2>/dev/null)
      if [[ -z "$OBS_JSON" || "$OBS_JSON" == "null" ]]; then
        FAILED+=("$id")
        FAILED_REASONS+=("obs not found")
        continue
      fi
      OBS_ID_FIELD=$(echo "$OBS_JSON" | jq -r '.id // empty' 2>/dev/null)
      if [[ -z "$OBS_ID_FIELD" || "$OBS_ID_FIELD" == "null" ]]; then
        FAILED+=("$id")
        FAILED_REASONS+=("obs not found")
        continue
      fi

      OBS_TOPIC_KEY=""
      if [[ "$WITH_RAW" == true ]]; then
        OBS_TOPIC_KEY=$(echo "$OBS_JSON" | jq -r '.topic_key // ""' 2>/dev/null)
        # Pre-resolve raw path so we can show a preview before any rm.
        if [[ -n "$OBS_TOPIC_KEY" ]]; then
          RAW_PREVIEW_PATH=$(find_raw_md "$OBS_TOPIC_KEY") || true
          [[ -n "$RAW_PREVIEW_PATH" ]] && RAW_PREVIEW+=("$RAW_PREVIEW_PATH")
        fi
      fi

      # Step 2: DELETE the obs (id confirmed to exist)
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        "${ENGRAM_HOST}/observations/${id}" --max-time 2 2>/dev/null)

      if [[ "$HTTP_CODE" == "200" ]]; then
        DELETED_OBS+=("$id")

        # Step 3: optionally delete the raw .md
        if [[ "$WITH_RAW" == true && -n "$OBS_TOPIC_KEY" ]]; then
          RAW_PATH=$(find_raw_md "$OBS_TOPIC_KEY") || true
          if [[ -n "$RAW_PATH" && -f "$RAW_PATH" ]]; then
            if rm -f "$RAW_PATH" 2>/dev/null; then
              DELETED_RAW+=("$(basename "$RAW_PATH")")
            fi
          fi
        fi
      else
        FAILED+=("$id")
        FAILED_REASONS+=("DELETE http=${HTTP_CODE}")
      fi
    done

    # Build a structured failed-array {id, reason} for richer reporting.
    FAILED_JSON="[]"
    if [[ ${#FAILED[@]} -gt 0 ]]; then
      FAILED_TMP=()
      for ((i=0; i<${#FAILED[@]}; i++)); do
        FAILED_TMP+=("$(jq -nc --arg id "${FAILED[$i]}" --arg reason "${FAILED_REASONS[$i]:-unknown}" '{id: $id, reason: $reason}')")
      done
      FAILED_JSON=$(printf '%s\n' "${FAILED_TMP[@]}" | jq -s '.')
    fi

    # Build raw preview JSON (informational — shows what raw files matched).
    RAW_PREVIEW_JSON="[]"
    if [[ ${#RAW_PREVIEW[@]} -gt 0 ]]; then
      RAW_PREVIEW_JSON=$(printf '%s\n' "${RAW_PREVIEW[@]}" | jq -R . | jq -s '.')
    fi

    # Emit summary JSON to stdout — always valid JSON, even if all arrays empty
    jq -nc \
      --argjson deleted "$(printf '%s\n' "${DELETED_OBS[@]}" | jq -R . | jq -s 'map(select(. != ""))')" \
      --argjson raw "$(printf '%s\n' "${DELETED_RAW[@]}" | jq -R . | jq -s 'map(select(. != ""))')" \
      --argjson failed "$FAILED_JSON" \
      --argjson raw_preview "$RAW_PREVIEW_JSON" \
      '{success: (($failed | length) == 0), deleted_obs: $deleted, deleted_raw: $raw, raw_preview: $raw_preview, failed: $failed}'
    exit 0
    ;;

  *)
    emit_err "unknown mode: '${MODE}' (expected --preview or --execute)"
    exit 0
    ;;
esac

exit 0
