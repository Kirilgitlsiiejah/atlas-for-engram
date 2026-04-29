#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || SCRIPT_DIR="."
ATLAS_ROOT="${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}}"
DOCTOR_OUT=$("${ATLAS_ROOT}/scripts/_doctor.sh" 2>/dev/null)
[[ -n "$DOCTOR_OUT" ]] && printf '%s\n' "$DOCTOR_OUT"
exit 0
