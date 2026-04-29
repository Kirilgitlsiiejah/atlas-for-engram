# Changelog

All notable changes to atlas-for-engram are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

(features in develop, no concrete release yet)

## [0.4.0] — 2026-04-29

### Added
- Adapter OpenCode para usar Atlas con stack GPT/OpenCode reutilizando el mismo core Bash que Claude Code.
- `ATLAS_PLUGIN_ROOT` como root canónico del plugin, con fallback compatible a `CLAUDE_PLUGIN_ROOT` para instalaciones Claude existentes.
- Artefactos OpenCode bajo `opencode/`: config, manifest, prompt primario y wrappers `SKILL.md` para inject, lookup, cleanup, research, edit, delete e index.
- Smoke manual `tests/manual-opencode-adapter-smoke.md` para validar root resolution, inject dry-run, lookup, cleanup y compatibilidad Claude.

### Changed
- CI valida JSON/version sync también para `opencode/manifest.json`.
- Docs explican instalación/uso de Atlas en OpenCode, incluyendo preflight Windows/WSL para CRLF y `jq` visible desde Bash.

## [0.3.1] — 2026-04-29

### Fixed
- Atlas readers ahora documentan explícitamente el contrato `source_url ?? source` para clips legacy del Web Clipper; `source_url` sigue siendo el campo canónico de escritura.
- `bulk-inject`, `atlas-lookup` y `atlas-cleanup` limitan el scan a clips `.md` de primer nivel en `atlas-pool/` y saltean `README.md`, así docs internas no se confunden con clips.

## [0.3.0] — 2026-04-29

### Added
- `skills/atlas-research/` — AI-first ingestion path. Claude investiga (web/research), pasa stdin JSON `{content, source_url, project, tags?}`, el skill escribe `.md` al `atlas-pool/` Y lo inyecta a engram en una sola invocación. Pool-first write order (si engram falla, el `.md` queda preservado).
- `skills/inject-atlas/bulk-inject.sh` — script paralelo que sweep `atlas-pool/*.md` a engram via `xargs -P 4`. ~640x más rápido que el SKILL.md prompt-only que reemplaza (4 .md baja de ~15 min a ~1.4s).
- `scripts/_helpers.sh::engram_post_observation()` — primitivo único de write a engram con retry-on-5xx (3 intentos, 0.3/0.5/0.7s linear backoff) para mitigar SQLite WAL contention bajo concurrent writes.
- `scripts/_doctor.sh::_doctor_check_yq()` — verifica `yq` v4 presente; warning con OS-specific install hint cuando missing.
- README "AI-first usage" section documentando los dos paths.

### Changed
- `skills/inject-atlas/SKILL.md` simplificado de 304 → 43 líneas. Ahora es un thin wrapper que delega a `bulk-inject.sh`. Triggers preservados ("inyectá al proyecto X", "agregá a engram", "inject Y to project X", "metele al engram").

### Deprecated
- Inline LLM-driven procedure en `skills/inject-atlas/SKILL.md` queda DEPRECATED. Será removido en próxima minor.

### Dependencies
- NEW: `yq` v4 (YAML frontmatter parsing). Doctor warns con install hint si missing. Atlas no auto-instala.

### Discoveries
- Engram `POST /observations` requiere `session_id` explícito (no auto-create). Bulk-inject y research mintean sesión via `POST /sessions` preamble.
- Engram retorna 500 SQLite 517 lock bajo concurrent writes incluso con distinct topic_keys. Mitigación cliente-side via retry-on-5xx. Upstream fix recomendado: bump `busy_timeout` o serialize upsert path.

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

[Unreleased]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.4...v0.2.0
[0.1.4]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/tag/v0.1.0
