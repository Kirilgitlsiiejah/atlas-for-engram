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

engram guarda **tu propio trabajo** (decisiones, bugs, conventions) excelente, pero no tiene un lugar de primera para **conocimiento externo curado** (artículos, papers, blog posts). Si los mezclás como observaciones normales, tu `mem_search` se ensucia y perdés la línea entre "lo que decidí yo" vs "lo que leí afuera".

Atlas resuelve eso con tres decisiones:

1. **`type=atlas` + `source_url` mandatory** → proveniencia trazable.
2. **PostToolUse hook `compare-with-atlas`** → cada `mem_search` viene pre-segmentado.
3. **Cross-vault dedup** → mismo URL clipeado dos veces no duplica; `atlas-cleanup` lo reporta.

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

El plugin vive bajo `${CLAUDE_PLUGIN_ROOT}` post-install: hooks, scripts (`_helpers.sh`, `_doctor.sh`, `session-start.sh`) y los 7 skills bajo `skills/`.

**Project resolution**: mismo algoritmo que engram core — git remote → git root basename → cwd basename → fallback `dev`. Override pasando `project` explícito.

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

Cada `mem_search` se divide automáticamente en dos buckets: **own_work** (tus decisiones, bugs, sesiones) y **atlas** (clips, papers, references). El hook fira después de cada search, lee el JSON tool_response por stdin, y emite `additionalContext` con proveniencia. Silent si no hay results atlas.

Matcher: `mcp__plugin_engram_engram__mem_search`. Registrado en `hooks/hooks.json`.

---

## SessionStart doctor (self-check)

Cada sesión y cada `/clear` corre `scripts/_doctor.sh` con timeout de 3s. Nunca bloquea la sesión (exit `0` siempre). **6 checks**:

1. **engram reachable** — `GET ${ENGRAM_HOST}/health`
2. **deps present** — `jq`, `curl`, `rg`, `fd` en PATH
3. **vault resolution report** — reporta el nivel resuelto (L1..L5) y path, así sabés qué branch del cascade ganó
4. **L5-fallback missing** — si cae a `$HOME/vault` y no existe, da remediation hint
5. **vault layout** — `<resolved-vault>/atlas-pool/` existe
6. **drift detector** — warne si los inline `detect_vault` blocks divergen del canonical en `scripts/_helpers.sh` (previene legacy logic dormido)

Run manual: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/_doctor.sh`.

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

El walk-up parte de `$PWD` y sube buscando `.obsidian/` (directorio nativo de Obsidian) o `.atlas-pool` (archivo vacío que creás con `touch .atlas-pool` en la raíz del vault).

> **Importante**: `.atlas-pool` tiene que ser un **archivo**, no un directorio. Si existe como dir (confusión con la carpeta `atlas-pool/` que sí es dir), el walk-up lo **ignora** y sigue subiendo. Para automáticamente en `/`, drive roots (`C:/`, `/c`), UNC roots (`//host/share`), o tras 64 iteraciones.

### Migración desde `VAULT_ROOT`

`VAULT_ROOT` sigue respetado pero emite un warning one-shot por sesión. Migrá renombrando la export en tu shellrc:

```bash
export ATLAS_VAULT="$HOME/Documents/vault"
```

El doctor reporta el nivel resuelto cada sesión (`vault: L4 (walk-up .obsidian) -> /path`) — así sabés exactamente qué branch del cascade ganó.

---

## Obsidian Web Clipper brandeado

<table>
<tr>
<td width="140" valign="top">
<img src="./assets/atlas-clipper-icon.png" alt="Atlas Clipper icon" width="120">
</td>
<td>

Atlas-for-engram incluye una versión brandeada del [Obsidian Web Clipper](https://github.com/obsidianmd/obsidian-clipper) oficial: ícono Atlas en la toolbar y default folder `atlas-pool` (en vez de `Clippings` upstream). Todo lo demás sigue al upstream — settings, templates, behavior. Es un patch, no un rebrand.

</td>
</tr>
</table>

### Descargá el zip de tu browser

Pre-buildeados, listos para `Load unpacked`:

- 🌐 **Chrome / Edge / Brave** → [atlas-clipper-1.6.2-chrome.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-chrome.zip)
- 🦊 **Firefox** → [atlas-clipper-1.6.2-firefox.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-firefox.zip)
- 🧭 **Safari** → [atlas-clipper-1.6.2-safari.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-safari.zip)

### Quickstart Chrome

1. Descargá el `.zip`, descomprimilo a una carpeta estable
2. `chrome://extensions` → activá Developer Mode → "Load unpacked" → seleccioná la carpeta
3. Click en el ícono Atlas (violeta) en la toolbar → Settings → seteá tu vault Obsidian
4. Clipeá una página → el `.md` aparece en `<vault>/atlas-pool/`

### Cierra el loop

Una vez que el clip está en `atlas-pool`, lo inyectás a Engram para que Claude lo recuerde:

```
/atlas:inject-atlas <tu-proyecto> <slug-del-clip>
```

A partir de ahí, cualquier pregunta a Claude que toque ese tema lo encuentra solo via `mem_search`.

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

- **shellcheck**: lintea bash via `ludeeus/action-shellcheck` pinned a SHA exacto (severity `warning`).
- **validate-json**: `jq -e .` sobre `plugin.json`, `marketplace.json`, `hooks.json`.
- **bash-syntax**: `bash -n` sobre todos los `.sh`.
- **version-sync**: chequea que `VERSION` y `plugin.json#version` no estén desincronizados.

Si algún job falla en push a `main`, el workflow `ci-alerts.yml` auto-crea (o comenta sobre la existente) una issue con label `ci-failure`. Idempotente por commit SHA. PR failures no disparan alerta (ya visibles en la UI del PR).

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
