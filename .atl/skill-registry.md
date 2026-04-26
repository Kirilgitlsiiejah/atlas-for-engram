---
title: Skill Registry — atlas-for-engram
project: atlas-for-engram
updated: 2026-04-25
---

# Skill Registry — atlas-for-engram

This file is consumed by sub-agents via the Skill Resolver Protocol. Compact rules below are injected as `## Project Standards (auto-resolved)` into sub-agent prompts.

## Stack
- Language: bash (POSIX-ish + bashisms)
- Deps runtime: curl, jq, awk
- Deps dev: bat, rg, fd, eza (replace forbidden cat/grep/find/ls)
- Docs: Markdown SKILL.md + YAML frontmatter
- OS targets: Windows Git Bash, macOS, Linux
- License: MIT

## Compact Rules

### Bash style
- NEVER `set -euo pipefail` — use defensive `2>/dev/null || true` per-call
- Always quote variable expansions: `"$var"`, never bare `$var`
- Use `[[ ... ]]` for tests, never `[ ... ]`
- Parameter expansion preferred over external tools: `${var//pattern/replacement}` over `sed`
- Heredocs `<<'EOF'` (single-quoted) when no interpolation needed
- `printf '%s'` over `echo` for safety (no trailing newline drift)

### Forbidden tools
- `sed` — use bash parameter expansion or `awk`
- `cat` — use bash redirection or `bat` (user-facing)
- `grep` — use bash `[[ =~ ]]` or `rg`
- `find` — use bash globs or `fd`
- `ls` — use bash globs or `eza`

### JSON handling
- `jq` for ALL parse/construct — never manual string concat
- Hooks emit valid JSON or `{"continue": true}` — validate via `jq -e .` before exit

### Hooks contract
- `exit 0` ALWAYS — no failure modes propagate to Claude harness
- Stdout: JSON or empty
- Stderr: human-readable diagnostics (warnings, etc.)

### Commits
- Conventional commits: `<type>(<scope>): <subject>`
- Types: `feat`, `fix`, `refactor`, `docs`, `test`, `ci`, `chore`
- BREAKING CHANGE footer for breaking changes
- NEVER `Co-Authored-By` or `🤖 Generated with` or any AI attribution
- Author: David Villalba <villalbadavid05@gmail.com>

### Docs
- Voseo rioplatense en docs user-facing (README.md, SKILL.md, CONTRIBUTING.md): `migrá`, `pasá`, `tenés`, `cambialo`, `dale`
- Inglés técnico OK en code comments
- Cross-references concretos: paths absolutos o `<repo-root>/relative/path`

### Helper pattern (CRITICAL)
- Shared helpers en `scripts/_helpers.sh` (sourced)
- EVERY consumer script MUST have inline ~25 LOC fallback copy of helper functions it uses, in case `_helpers.sh` is missing
- Inline fallback MUST be byte-identical across all consumers (sha1sum verifiable)
- Drift between canonical and inline = bug, period

### Vault marker discipline
- `.obsidian/` is a DIRECTORY (`-d` test)
- `.atlas-pool` is a regular FILE (`-f` test) — NEVER conflate
- `.atlas-pool/` directory must be IGNORED, walk-up continues

### Vault detection cascade (5 levels)
- L1: `--vault <path>` flag
- L2: `$ATLAS_VAULT` env (preferred)
- L3: `$VAULT_ROOT` env (legacy, one-shot warning per shell tree)
- L4: walk-up `.obsidian/` or `.atlas-pool` from `$PWD`
- L5: `$HOME/vault` fallback
- Implementation: `_helpers.sh::detect_vault [path_override]`

### Cross-process sentinels
- File-based sentinels MUST use `mkdir "$flag" 2>/dev/null` (atomic, symlink-safe)
- NEVER `: > "$flag"` (follows symlinks, race-prone)
- Scope per shell tree: include `${PPID}` in sentinel name
- Username fallback chain: `${USER:-${USERNAME:-${LOGNAME:-anon}}}` (Git Bash Windows has no `$USER`)

### CI / shellcheck
- shellcheck via `ludeeus/action-shellcheck` pinned to SHA (no tags)
- `.shellcheckrc` is single source of truth — no inline `# shellcheck source=/dev/null` directives
- Severity: `warning` (no `style`/`info`)
- Bumps in isolated PRs: `chore(ci): bump shellcheck action to <SHA>`

## User Skills (for orchestrator routing)

| Trigger context | Skill to load |
|-----------------|---------------|
| Editing `.sh` files in atlas-for-engram | this registry's compact rules above |
| Creating new atlas skill | `~/.claude/skills/skill-creator/SKILL.md` + helper pattern rules above |
| SDD phase work in atlas-for-engram | this registry + sdd-* skill-specific rules |

## Pointers

- SDD cycle history: `mem_search query="sdd/" project="atlas-for-engram"`
- Judgment day cycles: `mem_search query="judgment-day-rounds" project="atlas-for-engram"`
- Project bootstrap: `sdd-init/atlas-for-engram` in engram (obs #1965)
- Repo: https://github.com/Kirilgitlsiiejah/atlas-for-engram
- Local: `C:\Dev\atlas-for-engram\`
