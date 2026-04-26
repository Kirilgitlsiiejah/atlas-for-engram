#!/usr/bin/env bash
#
# build.sh — vendor-build the Atlas-branded Obsidian Web Clipper.
#
# Pipeline:
#   1. Clean and recreate dist/
#   2. Shallow-clone upstream at the pinned tag into a tempdir
#   3. Patch upstream sources (default folder: 'Clippings' -> 'atlas-pool')
#   4. Overlay our branded icons into src/icons/
#   5. npm ci (fallback npm install) — first run is slow
#   6. npm run build — produces 3 zips (chrome, firefox, safari)
#   7. Collect zips into dist/ with stable Atlas-prefixed names
#   8. Write NOTICE.md with MIT attribution + modification log
#   9. Print final summary
#
# Idempotent: re-running wipes dist/ and rebuilds from scratch. The temp
# upstream clone is removed via EXIT trap, including on failure.
#
# Notes:
#   - manifest.json files are intentionally NOT modified — keeping the
#     upstream name/version makes it clear this is a derivative work, not
#     a renamed product.
#   - Works on Windows Git Bash and Linux. No cmd.exe, no Windows-only paths.

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

UPSTREAM_REPO="https://github.com/obsidianmd/obsidian-clipper.git"
UPSTREAM_TAG="1.6.2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$SCRIPT_DIR/dist"
ICONS_DIR="$SCRIPT_DIR/icons"

WORK_DIR="$(mktemp -d -t atlas-clipper-XXXXXX)"
UPSTREAM_DIR="$WORK_DIR/upstream"

OLD_FOLDER="Clippings"
NEW_FOLDER="atlas-pool"

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() {
    printf '[build.sh] %s\n' "$*" >&2
}

die() {
    printf '[build.sh] ERROR: %s\n' "$*" >&2
    exit 1
}

# Portable in-place sed (BSD on macOS / Git Bash, GNU on Linux).
# Uses -i.bak then removes the backup so behavior matches everywhere.
portable_sed_inplace() {
    local pattern="$1"
    local file="$2"
    sed -i.bak "$pattern" "$file"
    rm -f "${file}.bak"
}

# Count occurrences of a fixed string in a file. Prefer rg, fall back to grep.
count_matches() {
    local needle="$1"
    local file="$2"
    if command -v rg >/dev/null 2>&1; then
        rg -F --count-matches "$needle" "$file" 2>/dev/null || echo 0
    else
        grep -F -c -- "$needle" "$file" 2>/dev/null || echo 0
    fi
}

# Verify a fixed-string match count in a file. Fail loud on mismatch.
expect_count() {
    local needle="$1"
    local file="$2"
    local expected="$3"
    local actual
    actual="$(count_matches "$needle" "$file")"
    if [ "$actual" -ne "$expected" ]; then
        die "expected $expected occurrence(s) of '$needle' in $file, found $actual"
    fi
}

# -----------------------------------------------------------------------------
# Step 1 — clean dest
# -----------------------------------------------------------------------------

log "Step 1/9: cleaning $DEST_DIR"
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

# -----------------------------------------------------------------------------
# Step 2 — clone upstream at pinned tag
# -----------------------------------------------------------------------------

log "Step 2/9: cloning $UPSTREAM_REPO @ $UPSTREAM_TAG into $UPSTREAM_DIR"
git clone --depth=1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO" "$UPSTREAM_DIR" >&2

# -----------------------------------------------------------------------------
# Step 3 — patch sources
# -----------------------------------------------------------------------------

log "Step 3/9: patching default folder '$OLD_FOLDER' -> '$NEW_FOLDER'"

TEMPLATE_MANAGER="$UPSTREAM_DIR/src/managers/template-manager.ts"
TEMPLATE_UI="$UPSTREAM_DIR/src/managers/template-ui.ts"
SETTINGS_HTML="$UPSTREAM_DIR/src/settings.html"

for f in "$TEMPLATE_MANAGER" "$TEMPLATE_UI" "$SETTINGS_HTML"; do
    [ -f "$f" ] || die "expected file not found: $f"
done

# Pre-patch sanity: confirm the strings we expect ARE present, so we fail
# fast if upstream renamed something between tags.
#
# template-manager.ts has 1 'Clippings' literal (path default).
# template-ui.ts has 2 'Clippings' literals (default + reset path).
# settings.html has 1 placeholder="Clippings".
expect_count "'Clippings'" "$TEMPLATE_MANAGER" 1
expect_count "'Clippings'" "$TEMPLATE_UI" 2
expect_count 'placeholder="Clippings"' "$SETTINGS_HTML" 1

# Apply the replacements.
portable_sed_inplace "s/'Clippings'/'$NEW_FOLDER'/g" "$TEMPLATE_MANAGER"
portable_sed_inplace "s/'Clippings'/'$NEW_FOLDER'/g" "$TEMPLATE_UI"
portable_sed_inplace "s/placeholder=\"Clippings\"/placeholder=\"$NEW_FOLDER\"/g" "$SETTINGS_HTML"

# Post-patch verification: 0 remaining old-string hits in the patched files,
# and the new string is present where expected.
expect_count "'Clippings'" "$TEMPLATE_MANAGER" 0
expect_count "'Clippings'" "$TEMPLATE_UI" 0
expect_count 'placeholder="Clippings"' "$SETTINGS_HTML" 0

expect_count "'$NEW_FOLDER'" "$TEMPLATE_MANAGER" 1
expect_count "'$NEW_FOLDER'" "$TEMPLATE_UI" 2
expect_count "placeholder=\"$NEW_FOLDER\"" "$SETTINGS_HTML" 1

log "Step 3/9: patch verified — $NEW_FOLDER applied in 3 files"

# -----------------------------------------------------------------------------
# Step 4 — overlay branded icons
# -----------------------------------------------------------------------------

log "Step 4/9: overlaying Atlas icons from $ICONS_DIR"

UPSTREAM_ICONS_DIR="$UPSTREAM_DIR/src/icons"
[ -d "$UPSTREAM_ICONS_DIR" ] || die "upstream icons directory missing: $UPSTREAM_ICONS_DIR"

for size in 16 48 128; do
    src="$ICONS_DIR/icon${size}.png"
    dst="$UPSTREAM_ICONS_DIR/icon${size}.png"
    [ -f "$src" ] || die "branded icon missing: $src"
    cp "$src" "$dst"
done

# -----------------------------------------------------------------------------
# Step 5 — install dependencies
# -----------------------------------------------------------------------------

log "Step 5/9: installing npm dependencies (this can take 1-3 minutes)..."

cd "$UPSTREAM_DIR"

if ! npm ci >&2; then
    log "npm ci failed (lockfile mismatch?), falling back to npm install"
    npm install >&2
fi

# -----------------------------------------------------------------------------
# Step 6 — build
# -----------------------------------------------------------------------------

log "Step 6/9: running 'npm run build' (chrome + firefox + safari)"
npm run build >&2

# -----------------------------------------------------------------------------
# Step 7 — collect zips
# -----------------------------------------------------------------------------

log "Step 7/9: collecting zips into $DEST_DIR"

# Upstream zip-webpack-plugin emits all browser zips into a single
# 'builds/' directory at the repo root, with browser-specific filenames
# like obsidian-web-clipper-<version>-<browser>.zip. We rename them with
# the Atlas prefix so consumers get stable filenames regardless of
# upstream version.
BUILDS_DIR="$UPSTREAM_DIR/builds"
[ -d "$BUILDS_DIR" ] || die "expected build output dir missing: $BUILDS_DIR"

collect_zip() {
    local browser="$1"
    local out_name="atlas-clipper-${UPSTREAM_TAG}-${browser}.zip"

    # Match the per-browser zip emitted by upstream webpack config.
    local found
    found="$(find "$BUILDS_DIR" -maxdepth 1 -type f -name "*-${browser}.zip" | head -n 1)"
    if [ -z "$found" ]; then
        die "no zip matching '*-${browser}.zip' found in $BUILDS_DIR"
    fi

    cp "$found" "$DEST_DIR/$out_name"
    log "  -> $out_name"
}

collect_zip "chrome"
collect_zip "firefox"
collect_zip "safari"

# -----------------------------------------------------------------------------
# Step 8 — write NOTICE.md
# -----------------------------------------------------------------------------

log "Step 8/9: writing NOTICE.md"

cat > "$DEST_DIR/NOTICE.md" <<EOF
# NOTICE

This software is derived from Obsidian Web Clipper
(https://github.com/obsidianmd/obsidian-clipper), licensed under the MIT
License. (c) 2024 Obsidian.

## Modifications

- Icons replaced with Atlas branding (icon16.png, icon48.png, icon128.png).
- Default destination folder changed from \`Clippings\` to \`${NEW_FOLDER}\`.

Built from upstream tag ${UPSTREAM_TAG}.
EOF

# -----------------------------------------------------------------------------
# Step 9 — final summary
# -----------------------------------------------------------------------------

log "Step 9/9: build complete. Artifacts in $DEST_DIR:"

# Portable size: prefer wc -c (POSIX), avoids stat flag differences across
# BSD/GNU.
for z in "$DEST_DIR"/*.zip; do
    [ -f "$z" ] || continue
    size_bytes="$(wc -c < "$z" | tr -d ' ')"
    printf '  %s  (%s bytes)\n' "$(basename "$z")" "$size_bytes" >&2
done

log "done."
exit 0
