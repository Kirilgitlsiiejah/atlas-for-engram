# Contributing to atlas-for-engram

¡Buenísimo que quieras contribuir! Este repo sigue **Spec-Driven Development (SDD)** + conventional commits + bash defensive. Antes de tirar el primer PR, leé esta guía completa — te ahorra rebotes en review.

## Quickstart

1. Forkeá + cloneá el repo
2. `git checkout -b feat/mi-feature`
3. Hacé tus cambios siguiendo las convenciones de abajo
4. `git commit` con conventional message (ver sección)
5. `git push` y abrí PR contra `main`
6. Esperá que CI pase verde (4 jobs)
7. Te respondo en review

## Stack

- **Lenguaje**: bash (POSIX-ish + bashisms)
- **Deps runtime**: `curl`, `jq`, `awk`
- **Deps dev**: `bat`, `rg`, `fd`, `eza` (reemplazan `cat`/`grep`/`find`/`ls`)
- **OS targets**: Windows Git Bash, macOS, Linux
- **License**: MIT

## Convenciones de código

### Bash defensive (CRÍTICO)

- **NUNCA** uses `set -euo pipefail`. Si querés error handling, manejalo per-call con `2>/dev/null || true`.
- Siempre quoteá variables: `"$var"`, nunca `$var` pelado
- `[[ ... ]]` no `[ ... ]`
- Parameter expansion antes que external tools
- `printf '%s'` antes que `echo`

### Tools prohibidos (en bash interno)

| Prohibido | Usá en su lugar |
|-----------|-----------------|
| `sed` | bash parameter expansion o `awk` |
| `cat` | redirección o `bat` (user-facing) |
| `grep` | `[[ =~ ]]` o `rg` |
| `find` | bash globs o `fd` |
| `ls` | bash globs o `eza` |

### JSON

- `jq` para TODO parse/construct — no string concat manual
- Hooks emiten JSON válido o `{"continue": true}` — validá con `jq -e .` antes de hacer exit

### Hooks contract

- `exit 0` SIEMPRE
- Stdout: JSON o vacío
- Stderr: diagnósticos human-readable

### Helper pattern (CRÍTICO)

- Helpers compartidos en `scripts/_helpers.sh` (sourced)
- CADA consumer script TIENE QUE tener un inline fallback (~25 LOC) de las funciones que use
- Los inline fallbacks tienen que ser **byte-idénticos** entre consumers (verificable con `sha1sum`)
- Drift entre canonical e inline = bug. El doctor (`scripts/_doctor.sh`) tiene un check automático que warne si esto pasa.

### Vault markers (gotcha clave)

- `.obsidian/` es un **directorio** (chequeá con `-d`)
- `.atlas-pool` es un **archivo regular** (chequeá con `-f`)
- Si existe `.atlas-pool/` como directorio, **se ignora** — el walk-up continúa

### Cross-process sentinels

- `mkdir "$flag" 2>/dev/null` (atomic, symlink-safe)
- NUNCA `: > "$flag"` (sigue symlinks, race-prone)
- Scope per shell tree: incluí `${PPID}` en el nombre
- Username fallback chain: `${USER:-${USERNAME:-${LOGNAME:-anon}}}` (Git Bash en Windows no setea `$USER`)

### Docs

- **Voseo rioplatense** en TODO doc user-facing (README, SKILL.md, CONTRIBUTING)
- Inglés técnico OK en code comments
- Cross-references con paths absolutos o `<repo-root>/relative/path`

## Conventional Commits

Formato: `<type>(<scope>): <subject>`

| Type | Cuándo |
|------|--------|
| `feat` | Nueva feature user-visible |
| `fix` | Bug fix |
| `refactor` | Cambio de código sin cambio de behavior |
| `docs` | Sólo docs |
| `test` | Sólo tests |
| `ci` | Cambios en CI/workflows |
| `chore` | Maintenance (deps, formatting, etc.) |

**BREAKING CHANGE** footer cuando rompés API (o `!` después del scope, ej: `feat(install)!:`).

**NUNCA** agregues `Co-Authored-By`, `🤖 Generated with`, ni ningún tipo de AI attribution. David Villalba firma todos los commits.

## SDD workflow (para cambios significativos)

Cambios chicos (1-2 archivos, 1 concept) → PR directo.

Cambios significativos (multi-file, multi-capability, decisiones arquitecturales) → SDD cycle:

1. **Explore**: investigá el codebase, listá approaches, recomendá uno
2. **Propose**: scope IN/OUT, capabilities, risks, rollback
3. **Spec**: REQs MUST/SHALL + scenarios Given/When/Then
4. **Design**: arquitectura técnica, file changes, interfaces
5. **Tasks**: breakdown phaseado con acceptance criteria
6. **Apply**: implementá, commits conventional
7. **Verify**: validá empíricamente cada REQ, audit gates
8. **Archive**: cerrá el cycle, próximos pasos sugeridos

Documentá cada fase como markdown en el PR description (o como observations en engram si tenés acceso al sistema).

## Antes del PR

- [ ] `bash -n` clean en todos los `.sh` modificados
- [ ] `rg "shellcheck source=/dev/null"` en `.sh` files retorna 0 hits
- [ ] CI verde local si tenés shellcheck (`shellcheck --rcfile=.shellcheckrc <files>`)
- [ ] Commit messages conventional, sin AI attribution
- [ ] Inline fallbacks (si tocaste consumer scripts) byte-idénticos via sha1sum
- [ ] Voseo en docs user-facing tocadas

## CI

GitHub Actions corre 4 jobs en cada push/PR a `main`:

- **shellcheck**: `ludeeus/action-shellcheck` SHA-pinned, severity warning, config en `.shellcheckrc`
- **validate-json**: `jq -e .` sobre `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`
- **bash-syntax**: `bash -n` sobre todos los `.sh` en `scripts/` y `skills/`
- **version-sync**: `VERSION` ↔ `.claude-plugin/plugin.json#version`

Si CI falla en `main`, el workflow `ci-alerts.yml` auto-crea issue con label `ci-failure`. NO se auto-cierra al fixearse — cerrala manual como audit trail.

## Preguntas

- Issues: https://github.com/Kirilgitlsiiejah/atlas-for-engram/issues
- Discusiones: usá GitHub Discussions si necesitás algo más amplio que un bug

¡Dale! 🎯
