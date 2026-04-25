#!/bin/bash
cat <<'EOF' >&2
================================================================
DEPRECATED: this installer will be removed in v0.2.0.
Recommended: claude plugin marketplace add Kirilgitlsiiejah/atlas-for-engram
             claude plugin install atlas
Continuing with legacy install in 3 seconds...
================================================================
EOF
sleep 3
# atlas-for-engram installer
# Copies skills to $HOME/.claude/skills/ and prints hook snippet for settings.json

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="$HOME/.claude/skills"

if [[ ! -d "$REPO_DIR/skills" ]]; then
  echo "ERROR: $REPO_DIR/skills not found. Run from inside the cloned repo." >&2
  exit 1
fi

mkdir -p "$DST"

echo "Installing atlas-for-engram skills to $DST/"
for skill in "$REPO_DIR/skills"/*/; do
  name=$(basename "$skill")
  if [[ -d "$DST/$name" ]]; then
    echo "  WARN: $name already exists, overwriting"
    rm -rf "$DST/$name"
  fi
  cp -r "$skill" "$DST/"
  echo "  OK: $name"
done

# Make .sh executable (use fd if available, fall back to find)
if command -v fd >/dev/null 2>&1; then
  fd -e sh . "$DST" -x chmod +x {} 2>/dev/null || true
else
  find "$DST" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
fi

echo ""
echo "Skills installed."
echo ""
echo "To activate the auto-compare hook, add this to ~/.claude/settings.json:"
echo ""
cat "$REPO_DIR/settings-hook-snippet.json"
echo ""
echo "Optional configuration via env vars (see README):"
echo "   ENGRAM_HOST, VAULT_ROOT, ATLAS_PROJECTS, MOVE_RAW_AFTER_INJECT"
echo ""
echo "Docs: README.md"
exit 0
