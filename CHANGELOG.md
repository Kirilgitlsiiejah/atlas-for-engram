# Changelog

All notable changes to atlas-for-engram are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

(features in develop, no concrete release yet)

## [0.2.0] - 2026-04-25

Major hardening release tras 4 SDD cycles + 2 rondas de adversarial judgment-day.

### Added
- **Vault auto-detect cross-platform** (`detect_vault` 5-level cascade): `--vault` flag → `$ATLAS_VAULT` → `$VAULT_ROOT` (legacy) → walk-up `.obsidian/` o `.atlas-pool` → `$HOME/vault`. Multi-vault setups funcionan zero-config (SDD #3, commits `5def26c`, `3e2a037`)
- **Doctor reporta vault resolution level** en cada SessionStart con label de qué nivel ganó (SDD #3, commit `6a685c1`)
- **`.atlas-pool` marker file** convention para vaults sin Obsidian (SDD #3)
- **Inline-fallback drift detector** — `scripts/_doctor.sh` warne si los inline `detect_vault` blocks divergen del canonical en `scripts/_helpers.sh` (SDD #7, commit `c0df35e`)
- **CI failure alerts** — auto-create GitHub issue cuando CI falla en `main`, label `ci-failure`, idempotente (SDD #8, commit `0387263`)
- **`.shellcheckrc`** centralizado en repo root con `disable=SC1090,SC1091` (SDD #4, commit `1a43fa6`)
- **`.atl/skill-registry.md`** para auto-resolución de project standards en sub-agents (commit `5845812`)
- **CONTRIBUTING.md** con conventions completas (DOC-1)
- **CHANGELOG.md** (este archivo) (DOC-2)
- **EXAMPLES.md** con 3 walkthroughs end-to-end (DOC-3)

### Changed
- **CI shellcheck**: migrado de `apt-get install shellcheck` floating a `ludeeus/action-shellcheck` pinned a SHA `00cae500b08a931fb5698e11e79bfbd38e612a38` (v2.0.0). Bumps en PRs aislados con conventional commit (SDD #4, commit `1a43fa6`)
- **Sentinel pattern**: `_atlas_warn_legacy` ahora usa `mkdir` atomic en `${TMPDIR:-/tmp}/_atlas_vault_warned.${USER:-${USERNAME}}.${PPID}` — symlink-safe, race-free, per-shell-tree scope (SDD #3 Round 2, commit `5104875`)
- **Path normalization** maneja `D:foo` (drive-relative no soportado, falls through), `//host/share` UNC, `C:\foo`, `C:/foo`, `/c/foo` — todos a forma canonical (SDD #3 Round 2, commit `5104875`)
- **Doctor siempre emite vault line** (sin guard `[[ -n VAULT_PATH ]]`) — observabilidad por defecto (SDD #3 Round 2, commit `3907411`)
- **VAULT_ROOT deprecation warning** persiste cross-subshell via sentinel file en `${TMPDIR:-/tmp}` (commit `17a6161`)

### Fixed
- **`--vault` flag UX bug**: `lookup.sh --vault foo` ya NO consume `foo` como vault path silently. Ahora rejected con JSON error si el valor falta o parece otro flag (SDD #3 Round 2, commit `558de80`)
- **`--vault=` empty form**: validación equivalente a `--vault` bare — empty value rejected (SDD #3 Round 2, commit `5104875`)
- **`$USER` empty en Git Bash Windows**: cascade `${USER:-${USERNAME:-${LOGNAME:-anon}}}` previene collision multi-user en `/tmp` flag (SDD #3 Round 2, commit `5104875`)
- **`SC2034`** unused `PROJECT_ARG` en `skills/atlas-edit/edit.sh` (SDD #4.1, commit `6e3a7c5`)
- **`SC1078`** unmatched single-quote class en `skills/atlas-index/generate.sh` — reemplazado `[\"'']` por `[\"']` (jq unicode escape transparente al shell parser) (SDD #4.1, commit `6e3a7c5`)
- **`SC1090/SC1091`** consolidados en `.shellcheckrc` `disable=` — eliminados inline `# shellcheck source=/dev/null` directives (SDD #4, commit `f106ea1`)
- **Doctor warning newlines** preservados (antes mangled a single line) (commit `80ab630`)

### Removed
- **`install.sh`** (deprecated installer) — usá `claude plugin install Kirilgitlsiiejah/atlas-for-engram` desde el marketplace (SDD #5, commit `f0dc835`, BREAKING CHANGE)
- **`ignore_names: install.sh`** del shellcheck job (innecesario tras SDD #5) (SDD #5)
- **Inline `# shellcheck source=/dev/null`** disables — reemplazados por `.shellcheckrc` global (SDD #4, commits `1a43fa6` + `f106ea1`)
- **`ignore_paths`** invalid directive del shellcheck job (commit `b74a004`)

### Security
- shellcheck action SHA-pinned previene supply-chain compromise via tag mutation
- Sentinel via `mkdir` atomic previene symlink truncation attack en `/tmp` multi-user (Linux)

## [0.1.4] - 2026-04-25

### Added
- GitHub stars badge en README (commit `2435fe5`)

## [0.1.3] - 2026-04-25

### Changed
- README: dropped legacy install instructions, enlarged hero image (commit `61e767e`)

## [0.1.2] - 2026-04-25

### Added
- README hero image + gentle-ai format (commit `fc1c160`)

## [0.1.1] - 2026-04-25

### Changed
- One-liner install como primary install method en README (commit `509ef52`)

## [0.1.0] - 2026-04-25

Initial public release. Atlas plugin para Claude Code, companion al engram MCP server.

### Added
- 7 skills atlas: `inject-atlas`, `atlas-edit`, `atlas-cleanup`, `atlas-delete`, `atlas-lookup`, `atlas-index`, `compare-with-atlas` (commit `c70f61a`)
- `inject-atlas` reads markdown clips desde `<vault>/atlas-pool/` y los inyecta a engram con `type=atlas`, `source_url` mandatory
- `atlas-edit` patches existing atlas observations via engram HTTP API
- `atlas-cleanup` integrity check: orphans, dangling, duplicates, malformed
- `atlas-delete` por obs ID o filter (domain, project, slug pattern)
- `atlas-lookup` busca clips por URL en engram + atlas-pool
- `atlas-index` genera `Atlas-Index.md` navegable
- `compare-with-atlas` PostToolUse hook para separar resultados de `mem_search` en own work vs engram_atlas
- `atlas-doctor` (en `scripts/_doctor.sh`) SessionStart hook con healthchecks (commit `8409c85`)
- CI workflow con 4 jobs: shellcheck, validate-json, bash-syntax, version-sync (commit `4353bab`)
- Plugin manifest en `.claude-plugin/plugin.json`, marketplace en `.claude-plugin/marketplace.json`, hooks en `hooks/hooks.json` (commit `8a1d10c`)
- `${CLAUDE_PLUGIN_ROOT}` paths en SKILL.md (commit `078b513`)
- README + 7 SKILL.md + plugin.json + marketplace.json + hooks.json + VERSION

[Unreleased]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.4...v0.2.0
[0.1.4]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/tag/v0.1.0
