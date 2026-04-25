#!/bin/bash
# compare-with-atlas — PostToolUse hook for mem_search
#
# Reads the JSON hook input on stdin (Claude Code convention for PostToolUse),
# extracts the mem_search results from tool_response, separates them by
# observation type (own_work vs engram_atlas), and emits an additionalContext
# string so the agent presents the results with provenance.
#
# Convention alignment with engram plugin (Gentleman-Programming/engram):
#   - shebang: /bin/bash
#   - defensive style: 2>/dev/null + || true, no `set -euo pipefail`
#   - jq for all JSON parsing and construction
#   - MUST exit 0 always — Claude Code blocks the tool result if the hook fails
#   - MUST emit valid JSON to stdout (or empty {} for no-op)

# Read full stdin (no `cat` per project conventions)
INPUT=$(</dev/stdin)

# Default: no-op output. Claude Code accepts {} or {"continue": true} as silent.
NOOP='{"continue": true}'

# Bail silently if jq is unavailable
if ! command -v jq >/dev/null 2>&1; then
  echo "$NOOP"
  exit 0
fi

# Extract tool_response. Engram's mem_search returns its payload here.
# The payload may be a JSON object/array (under .content[0].text as a string),
# or it may be a plain string. Try both shapes.
RAW=$(echo "$INPUT" | jq -r '.tool_response // empty' 2>/dev/null)

if [ -z "$RAW" ] || [ "$RAW" = "null" ]; then
  echo "$NOOP"
  exit 0
fi

# FIX R2-2 — Extract + re-parse the inner text body (MCP convention:
# content[0].text) in a SINGLE jq pass to avoid the decode-then-re-encode trap.
#
# The previous approach extracted with `jq -r` (which decodes escaped \n into
# literal newlines) and then tried to re-parse with jq — but once \n becomes a
# raw newline in the shell, jq can never re-parse it as a JSON string (control
# chars must be escaped in JSON). The text-mode fallback then ran with already
# decoded data the regex couldn't match, so the hook silently no-op'd on every
# multi-line atlas content.
#
# Strategy: do the extract + JSON-decode + re-encode in one jq pipeline:
#   - try `(.tool_response.content[0].text | fromjson)` → if .text is a JSON
#     string containing an array, decode it and emit compact JSON via -c.
#   - fallback to .tool_response.output / .tool_response if the MCP shape is
#     absent (engram in non-MCP form).
# When that pipeline fails (text isn't valid JSON), capture the raw string with
# `jq -r` ONLY for the text-mode branch, never re-fed back into jq.
COMPACT=$(echo "$INPUT" | jq -c '
  (.tool_response?.content?[0]?.text? | fromjson?)
  // .tool_response?.output?
  // .tool_response?
  // empty
' 2>/dev/null)

# Fast early-exit BEFORE the type check: if the compact body has no atlas-typed
# obs (in ANY form — direct, escaped JSON, or YAML-style), skip everything.
# We check escaped form too because COMPACT may be the un-decoded outer object
# when fromjson failed and we fell through to .tool_response.
if [ -n "$COMPACT" ] \
   && [[ "$COMPACT" != *'"type":"atlas"'* \
         && "$COMPACT" != *'"type": "atlas"'* \
         && "$COMPACT" != *'\"type\":\"atlas\"'* \
         && "$COMPACT" != *'\"type\": \"atlas\"'* \
         && "$COMPACT" != *'type: atlas'* ]]; then
  echo "$NOOP"
  exit 0
fi

if [ -n "$COMPACT" ] && echo "$COMPACT" | jq -e 'type == "array"' >/dev/null 2>&1; then
  BODY="$COMPACT"
  PARSED_TYPE="array"
else
  # Text-mode fallback: extract the raw .text (or whole tool_response) WITHOUT
  # any further jq parsing — the regex below scans it as a plain string.
  RAW=$(echo "$INPUT" | jq -r '.tool_response.content[0].text // .tool_response.output // .tool_response // empty' 2>/dev/null)
  if [ -z "$RAW" ] || [ "$RAW" = "null" ]; then
    echo "$NOOP"
    exit 0
  fi
  # Same fast early-exit, applied to RAW for the text-mode path. After jq -r
  # decoded the JSON-string, escapes are unescaped — so we check the plain
  # forms here, not the backslash-escaped ones.
  if [[ "$RAW" != *'"type":"atlas"'* && "$RAW" != *'"type": "atlas"'* \
        && "$RAW" != *'type: atlas'* && "$RAW" != *'type:atlas'* ]]; then
    echo "$NOOP"
    exit 0
  fi
  BODY="$RAW"
  PARSED_TYPE="text"
fi

OWN_WORK=""
ATLAS=""

if [ "$PARSED_TYPE" = "array" ]; then
  # JSON array path — split into own_work and atlas via jq.
  # source_url is NOT a top-level field on type=atlas obs — it lives inside content
  # as "**Source**: <url>". Extract via capture() (same pattern as lookup.sh:78).
  ATLAS=$(echo "$BODY" | jq -r '
    [.[] | select(.type == "atlas")]
    | if length == 0 then ""
      else
        map(
          . as $o
          | (($o.content // "") | capture("\\*\\*Source\\*\\*:\\s*(?<url>\\S+)"; "n")? // null) as $cap
          | ($cap | if . then .url else "" end) as $src_url
          | "- [\($o.id // "?")] \($o.title // "(untitled)")"
            + (if $src_url != "" then " — \($src_url)" else "" end)
            + (if $o.snippet then " — \($o.snippet | tostring | .[0:160])" else "" end)
        )
        | join("\n")
      end
  ' 2>/dev/null)

  OWN_WORK=$(echo "$BODY" | jq -r '
    [.[] | select(.type != "atlas")]
    | if length == 0 then ""
      else
        map("- [\(.id // "?")] \(.title // "(untitled)") — \(.snippet // "" | tostring | .[0:160]) (type: \(.type // "?"), project: \(.project // "?"))")
        | join("\n")
      end
  ' 2>/dev/null)
else
  # Text-mode fallback (BODY is a raw string — possibly multi-line content that
  # broke jq re-parse, or a YAML-style payload). Best-effort extraction:
  #   1) Match BOTH JSON style (`"type":"atlas"`) AND YAML/text style
  #      (`type: atlas` / `type:atlas`) — POSIX classes, no PCRE2 needed.
  #   2) If we see at least one atlas hit, extract `**Source**: <url>` lines so
  #      the emitted additionalContext carries provenance even without structure.
  ATLAS_HITS=$(printf '%s\n' "$BODY" | rg -i '"type"[[:space:]]*:[[:space:]]*"atlas"|type:[[:space:]]*atlas' 2>/dev/null || true)
  if [ -n "$ATLAS_HITS" ]; then
    SOURCE_URLS=$(printf '%s\n' "$BODY" | rg -o -i '\*\*Source\*\*:[[:space:]]*(\S+)' --replace '$1' 2>/dev/null || true)
    if [ -n "$SOURCE_URLS" ]; then
      ATLAS=$(printf '%s\n' "$SOURCE_URLS" | rg -v '^[[:space:]]*$' 2>/dev/null \
        | rg --no-line-number '.+' --replace '- $0' 2>/dev/null || true)
    else
      ATLAS="$ATLAS_HITS"
    fi
  fi
  # OWN_WORK in text mode is the rest — but without structure it's noisy. Skip.
  OWN_WORK=""
fi

# Silent intelligence: if both sections are empty, no-op
if [ -z "$ATLAS" ] && [ -z "$OWN_WORK" ]; then
  echo "$NOOP"
  exit 0
fi

# Silent intelligence: if ONLY own_work has results, no-op
# (mem_search already showed those results to the agent — no value in re-listing).
if [ -z "$ATLAS" ] && [ -n "$OWN_WORK" ]; then
  echo "$NOOP"
  exit 0
fi

# Build the markdown context. We include both sections only when atlas has results,
# so the agent can present them with provenance.
CONTEXT=""
if [ -n "$OWN_WORK" ]; then
  CONTEXT="**From engram (your work):**
${OWN_WORK}

"
fi

if [ -n "$ATLAS" ]; then
  CONTEXT="${CONTEXT}**From engram atlas (already injected):**
${ATLAS}
"
fi

# Emit JSON with hookSpecificOutput.additionalContext
# Use jq -n with --arg so it handles all escaping safely
OUTPUT=$(jq -n --arg ctx "$CONTEXT" '{
  continue: true,
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}' 2>/dev/null)

if [ -z "$OUTPUT" ]; then
  echo "$NOOP"
  exit 0
fi

printf '%s\n' "$OUTPUT"
exit 0
