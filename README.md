<div align="center">

<img src="./assets/atlas-hero.png" alt="atlas-for-engram" width="600" />

<h1>atlas-for-engram</h1>

<p><strong>Curated external knowledge para tu memory layer — companion plugin para <a href="https://github.com/Gentleman-Programming/engram">engram</a>.</strong></p>

<p>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/actions/workflows/ci.yml"><img src="https://github.com/Kirilgitlsiiejah/atlas-for-engram/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases"><img src="https://img.shields.io/github/v/release/Kirilgitlsiiejah/atlas-for-engram" alt="Release"></a>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/stargazers"><img src="https://img.shields.io/github/stars/Kirilgitlsiiejah/atlas-for-engram?style=flat&logo=github&color=yellow" alt="GitHub stars"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
<img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey" alt="Platform">
</p>

</div>

---

## Qué hace

- **Clipear web → engram**: chupa los `.md` que tu Obsidian Web Clipper deja en `atlas-pool/` y los guarda en engram como `type=atlas`, scoped al proyecto donde estás parado.
- **Búsqueda separada**: cada `mem_search` se auto-divide en `own_work` (tus decisiones, bugs, sesiones) vs `atlas` (clips externos) — sin tocar nada vos.
- **Vault auto-detect cross-platform**: cascade de 5 niveles resuelve el vault solo. Funciona en macOS, Linux y Windows Git Bash sin config.

---

## Por qué importa

engram tiene un agujero conceptual: guarda **tu propio trabajo** (decisiones, bugs, conventions) buenísimo, pero no tiene un lugar de primera para **conocimiento externo curado** (artículos, papers, blog posts que clipeaste). Si los mezclás como observaciones normales, tu `mem_search` se ensucia y perdés la línea entre "lo que decidí yo" vs "lo que leí afuera".

Atlas resuelve eso con tres decisiones de diseño:

1. **`type=atlas` mandatory** + `source_url` mandatory → toda observación atlas tiene proveniencia trazable.
2. **PostToolUse hook `compare-with-atlas`** → cada `mem_search` viene pre-segmentado, sin pedirte que lo recordés.
3. **Cross-vault dedup** → el mismo URL clipeado dos veces no genera duplicados; `atlas-cleanup` te lo reporta.

---

## Quickstart (5 minutos)

### 1. Instalá

```bash
claude plugin marketplace add Kirilgitlsiiejah/atlas-for-engram && claude plugin install atlas@atlas-for-engram
```

El marketplace apunta al `.claude-plugin/marketplace.json` de este repo. Claude Code resuelve skills, hooks y scripts desde `${CLAUDE_PLUGIN_ROOT}` automáticamente — cero copies manuales, cero edits a `settings.json`.

Updates posteriores:

```bash
claude plugin update atlas@atlas-for-engram
```

### 2. Setup mínimo

El SessionStart doctor corre en cada sesión y te dice qué falta. Setup típico la primera vez:

```bash
# Crea el atlas-pool dentro de tu vault Obsidian
mkdir -p ~/vault/atlas-pool

# (opcional, recomendado) markeá la raíz del vault para auto-detect zero-config
touch ~/vault/.atlas-pool
```

Configurá tu Obsidian Web Clipper para escribir los clips a `atlas-pool/`. Eso es todo.

### 3. Primer clip

Después de clipear un blog post a `~/vault/atlas-pool/hexagonal-architecture.md`, en Claude Code:

```
inyectá al proyecto dev la info de hexagonal-architecture
```

El skill `inject-atlas` parsea el frontmatter, llama a `mem_save` con `type=atlas`, y regenera `Atlas-Index.md` en la raíz del vault.

### 4. Primera búsqueda

```
mem_search hexagonal architecture
```

El hook `compare-with-atlas` separa results en `own_work` vs `atlas` automáticamente. Vas a ver tus decisiones del proyecto y los clips externos en columnas distintas, con `source_url` visible para los atlas.

Walkthroughs completos end-to-end: ver [EXAMPLES.md](EXAMPLES.md).

---

## Cómo funciona

```
Browser Web Clipper
        |
        v
   ${ATLAS_VAULT}/atlas-pool/<slug>.md  (raw markdown, sin proyecto)
        |  inject-atlas (manual trigger)
        v
   engram type=atlas, project=<auto-detect desde git>
        |
        +--> Atlas-Index.md  (auto-regen en cada inject)
        |
        +--> mem_search → compare-with-atlas hook → own_work vs atlas
        |
        v
   Browse / retrieve desde cualquier markdown editor o claude-code
```

El plugin vive enteramente bajo `${CLAUDE_PLUGIN_ROOT}` post-install:

```
${CLAUDE_PLUGIN_ROOT}/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── hooks/
│   └── hooks.json          # PostToolUse + SessionStart registration
├── scripts/
│   ├── _helpers.sh         # detect_project / resolve_project / detect_vault cascade
│   ├── _doctor.sh          # healthcheck (6 checks)
│   └── session-start.sh    # SessionStart shim → calls _doctor.sh
└── skills/
    ├── inject-atlas/
    ├── atlas-edit/
    ├── atlas-delete/
    ├── atlas-lookup/
    ├── atlas-cleanup/
    ├── atlas-index/
    └── compare-with-atlas/
```

**Project resolution**: mismo algoritmo que engram core — git remote → git root basename → cwd basename → fallback `dev`. Override per-invocation pasando `project` explícito.

---

## Skills

7 skills + 1 hook auto-fired:

| Skill | Trigger | Qué hace |
|---|---|---|
| `inject-atlas` | "inyectá al proyecto X la info de Y" | **CREATE** — parsea atlas-pool .md y guarda a engram como `type=atlas` |
| `atlas-edit` | "editá el atlas X" | **UPDATE** — PATCH `/observations/{id}` con field=value pairs |
| `atlas-delete` | "borrá el atlas X" | **DELETE** — individual + bulk + opcional cleanup del .md crudo |
| `atlas-lookup` | "tengo atlas de URL X?" | **READ** — búsqueda cross-project por URL |
| `atlas-cleanup` | "atlas integrity check" | **INTEGRITY** — orphans / dangling / duplicates / malformed report |
| `atlas-index` | "atlas index" | **BROWSE** — regenera `Atlas-Index.md` en raíz del vault |
| `compare-with-atlas` | auto via PostToolUse hook | **READ** — separa own_work vs atlas results en cada `mem_search` |

> **Nota**: este es un plugin **community / companion** para [engram](https://github.com/Gentleman-Programming/engram). Integra con la HTTP API de engram y sigue las conventions de plugins claude-code, pero **no está oficialmente afiliado, endorsed ni mantenido por el proyecto engram**.

---

## Auto-separación de búsqueda (PostToolUse hook)

Cada `mem_search` que hagas en un proyecto con observaciones atlas se divide automáticamente en dos buckets: **own_work** (tus decisiones, bugs, sesiones) y **atlas** (clips, papers, references). No lo disparás vos — el hook fira después de cada search, lee el JSON tool_response por stdin, y emite un payload `additionalContext` para que el agente presente results con proveniencia. Silent si no hay results atlas.

Matcher: `mcp__plugin_engram_engram__mem_search`. Registrado en `hooks/hooks.json`.

---

## SessionStart doctor (self-check)

Cada sesión y cada `/clear` corre `scripts/_doctor.sh` con timeout de 3s. **6 checks**, cada uno <100ms en env healthy:

1. **engram reachable** — `GET http://${ENGRAM_HOST}/health` con timeout 1s
2. **deps present** — `jq`, `curl`, `rg`, `fd` en PATH
3. **vault resolution report** — siempre reporta el nivel resuelto (L1..L5) y path, incluso healthy, via `additionalContext` (así sabés qué branch del cascade fired)
4. **L5-fallback missing** — si el cascade cayó a `$HOME/vault` (L5) Y ese dir no existe, surface remediation hint
5. **vault layout** — `<resolved-vault>/atlas-pool/` existe (resuelto via [vault cascade](#vault-resolution))
6. **drift detector** — warne si los inline `detect_vault` blocks divergen del canonical en `scripts/_helpers.sh` (previene legacy logic dormido)

Exit codes: `0` siempre (nunca bloquea session start). Stdout vacío → silent OK. Stdout JSON → warnings surfaced como `additionalContext` para el agente.

Ejemplo de output (env unhealthy):

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "atlas-doctor:\n  - engram unreachable at http://127.0.0.1:7437\n  - missing commands: fd\n  - atlas-pool not found at /home/u/vault/atlas-pool\n"
  }
}
```

Run manual cuando quieras:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/_doctor.sh
```

---

## Vault Resolution

Cada skill que toca el `atlas-pool/` resuelve el vault por una **cascada de 5 niveles**. Gana el primero que matchea — los demás se ignoran.

| Nivel | Fuente                                          | Cuándo usarlo                          |
|-------|-------------------------------------------------|-----------------------------------------|
| **L1** | flag `--vault <path>` pasado al script         | Override puntual sin ensuciar env vars |
| **L2** | env var `$ATLAS_VAULT`                          | Default canónico para tu shell         |
| **L3** | env var `$VAULT_ROOT` (**legacy, deprecated**)  | Compat con setups previos — migrá a `ATLAS_VAULT` |
| **L4** | walk-up desde `$PWD` buscando un marker         | Working tree con vault auto-detectado  |
| **L5** | fallback `$HOME/vault`                          | Si todo lo anterior falla              |

Ejemplos copy-pasteables:

```bash
# L4 — auto-detect (recomendado, zero-config)
cd ~/vault-obsidian
atlas-cleanup --scan

# L2 — override explícito por shell
export ATLAS_VAULT=~/otro-vault
atlas-lookup "hexagonal architecture"

# L1 — flag CLI top priority (overridea todo)
atlas-cleanup --vault=/tmp/test-vault
```

### Markers de walk-up (L4)

El walk-up parte de `$PWD` y sube directorio por directorio buscando alguno de estos:

- **`.obsidian/`** — directorio (es el marker nativo de Obsidian, no lo creás vos manualmente)
- **`.atlas-pool`** — archivo regular vacío (lo creás vos con `touch .atlas-pool` en la raíz del vault)

> **Importante**: `.atlas-pool` tiene que ser un **archivo**, no un directorio. Si existe `.atlas-pool/` como directorio (suele pasar por confusión con la carpeta `atlas-pool/` que sí es un dir), el walk-up lo **ignora** y sigue subiendo.

Termination guards: el walk-up para automáticamente al llegar a `/` (POSIX), un drive root tipo `/c` o `C:/` (Windows / Git Bash), o un UNC root tipo `//host/share`. También hay un cap defensivo de 64 iteraciones.

### Migración desde `VAULT_ROOT`

Si tenías esto en tu shellrc:

```bash
export VAULT_ROOT="$HOME/Documents/vault"
```

Cambialo a:

```bash
export ATLAS_VAULT="$HOME/Documents/vault"
```

`VAULT_ROOT` sigue funcionando — emite un warning una sola vez por sesión (`warning: $VAULT_ROOT is deprecated; use $ATLAS_VAULT instead`) y se resuelve igual. Para silenciarlo: migrá a `ATLAS_VAULT`.

### Cómo saber qué nivel se está usando

El doctor (SessionStart) reporta el nivel resuelto en cada sesión:

```
atlas-doctor:
  - vault: L4 (walk-up .obsidian) -> /home/u/projects/notes
```

Cuando el doctor cae a L5 y el path no existe, agrega remediation hint:

```
  - vault path /home/u/vault does not exist — set $ATLAS_VAULT, place .atlas-pool marker, or create the dir
```

---

## Configuración

| Env var | Default | Propósito |
|---|---|---|
| `ENGRAM_HOST` | `http://127.0.0.1:7437` | engram HTTP API URL |
| `ENGRAM_PORT` | `7437` | shorthand si `HOST` no está set |
| `ATLAS_VAULT` | (unset; cascade resuelve) | vault root canónico (parent de `atlas-pool/`). Reemplaza `VAULT_ROOT`. |
| `VAULT_ROOT` | (unset; legacy) | **deprecated** — sigue respetado con warning one-shot. Migrá a `ATLAS_VAULT`. |
| `ATLAS_PROJECTS` | auto-detect | comma-separated list para `atlas-cleanup` cross-project scan |
| `MOVE_RAW_AFTER_INJECT` | `false` | mové `.md` a `atlas-pool/injected/` después de inject |
| `ATLAS_EDIT_CONFIRM_TYPE_CHANGE` | `false` | requiere `=yes` para cambiar type de una obs atlas |

---

## CI

Cuatro jobs corren en cada push y PR a `main`:

- **shellcheck**: lintea bash via `ludeeus/action-shellcheck` pinned a SHA exacto. Severity `warning`. Config: `.shellcheckrc` en root.
- **validate-json**: `jq -e .` sobre `plugin.json`, `marketplace.json`, `hooks.json`.
- **bash-syntax**: `bash -n` sobre todos los `.sh`.
- **version-sync**: chequea que `VERSION` y `plugin.json#version` no estén desincronizados.

### CI failure alerts

Si algún job de CI falla en push a `main`, el workflow `ci-alerts.yml` auto-crea (o comenta sobre la existente) una issue con label `ci-failure`. Notificación al maintainer vía GitHub. Idempotente por commit SHA: re-runs del mismo SHA agregan comentario, no duplican issue. Issues NO se auto-cierran al fixearse — cerrá manualmente como audit trail. PR failures NO disparan alerta (ya son visibles en la UI del PR).

### shellcheck pin policy

El action `ludeeus/action-shellcheck` se pinea a SHA exacto (no tag). Razón: prevenir upgrades silenciosos del action o de la versión de shellcheck que ese action incluye internamente.

**Cómo bumpear**:
1. Chequeá releases en https://github.com/ludeeus/action-shellcheck/releases
2. Resolvé el SHA del commit del release: `gh api repos/ludeeus/action-shellcheck/git/ref/tags/<TAG> --jq .object.sha`
3. Actualizá `.github/workflows/ci.yml` con el nuevo SHA + comment `# corresponds to <TAG>`
4. Abrí PR aislado con título `chore(ci): bump shellcheck action to <SHA>`
5. Si el bump introduce SC codes nuevos: triage en commit aparte dentro del mismo PR
6. Merge sólo si CI pasa verde

---

## Troubleshooting

**engram unreachable**: arrancá engram (`engram serve` o como lo corras) y re-chequeá con `curl -sf http://127.0.0.1:7437/health`. Override host con `ENGRAM_HOST=host:port`.

**missing commands**: instalá lo que el doctor flagged. Windows Git Bash: scoop / chocolatey. macOS: `brew install jq curl ripgrep fd`. Linux: tu package manager (los nombres usuales son `jq curl ripgrep fd-find`).

**atlas-pool not found**: creá el dir (`mkdir -p $HOME/vault/atlas-pool`) y apuntá tu Web Clipper output ahí. Override el parent con `ATLAS_VAULT=/path/to/vault` (o setea walk-up poniendo un `.atlas-pool` empty file en la raíz del vault — ver [Vault Resolution](#vault-resolution)).

**vault detectado en lugar equivocado**: corré el doctor manual (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/_doctor.sh`) — la línea `vault: L? (...) -> <path>` te dice exactamente qué branch del cascade ganó. Si es L5 y no querés esa default, exportá `$ATLAS_VAULT` o poné `.atlas-pool` marker en la raíz correcta.

---

## Compatibility

- **engram**: >= v1.13.0 (usa `/observations`, `/observations/recent`, `/observations/{id}` PATCH/DELETE, `/search`)
- **Claude Code**: cualquier versión que soporte native plugins + skills + PostToolUse + SessionStart hooks
- **OS**: Windows (Git Bash), macOS, Linux
- **Deps**: `bash`, `jq`, `curl`, `rg` (ripgrep), `fd`

---

## Roadmap

Próximas features bajo consideración (ver [issues](https://github.com/Kirilgitlsiiejah/atlas-for-engram/issues) para tracking):

- **`atlas-import`**: bulk import de un dir entero de clips, batch a un proyecto target
- **`atlas-stats`**: report de métricas — total atlas por proyecto, top domains, age distribution
- **`compare-with-atlas` real impl**: por ahora separa results; próxima iteración detecta contradicciones entre own_work y atlas sobre el mismo tema
- **Multi-vault aggregation**: `atlas-cleanup` cross-vault con `--vaults=path1,path2`
- **Web UI opcional**: browser local para `Atlas-Index.md` con search + filters

---

## Resources

- [CHANGELOG.md](CHANGELOG.md) — historial de versiones (Keep a Changelog format)
- [CONTRIBUTING.md](CONTRIBUTING.md) — bash conventions, commit format, SDD workflow
- [EXAMPLES.md](EXAMPLES.md) — 3 walkthroughs end-to-end del workflow completo
- [engram](https://github.com/Gentleman-Programming/engram) — proyecto core upstream
- [Obsidian Web Clipper](https://obsidian.md/clipper) — extensión de browser para clipear

---

<div align="center">

**MIT** — David Villalba — 2026

<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>

</div>
