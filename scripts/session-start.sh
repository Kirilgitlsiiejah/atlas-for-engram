#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCTOR_OUT=$("${SCRIPT_DIR}/_doctor.sh" 2>/dev/null)
[[ -n "$DOCTOR_OUT" ]] && printf '%s\n' "$DOCTOR_OUT"
exit 0
