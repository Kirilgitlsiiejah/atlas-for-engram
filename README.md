<div align="center">

<img src="./assets/atlas-hero.png" alt="atlas-for-engram" width="600" />

<h1>atlas-for-engram</h1>

<p><strong>La capa de conocimiento externo curado para tu memoria persistente — companion plugin de <a href="https://github.com/Gentleman-Programming/engram">engram</a>.</strong></p>

<p>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/actions/workflows/ci.yml"><img src="https://github.com/Kirilgitlsiiejah/atlas-for-engram/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases"><img src="https://img.shields.io/github/v/release/Kirilgitlsiiejah/atlas-for-engram" alt="Release"></a>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/stargazers"><img src="https://img.shields.io/github/stars/Kirilgitlsiiejah/atlas-for-engram?style=flat&logo=github&color=yellow" alt="GitHub stars"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
<img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey" alt="Platform">
</p>

</div>

---

## ¿Qué hace?

Atlas convierte cualquier artículo, paper o blog post que clipeás desde el navegador en **memoria persistente que Claude consulta solo**. Vos clipeás con un click, le decís a Claude *"agregá esto al proyecto X"* y listo — la próxima vez que le preguntes algo relacionado, lo encuentra y lo cita.

Atlas-for-engram **lee** los `.md` que el Web Clipper deja en `atlas-pool/` y los carga en engram como observaciones `type=atlas`, asociadas al proyecto sobre el que estés conversando. No hay comandos que recordar — todo es conversación natural con Claude.

---

## ¿Por qué importa?

Te pasó esto: leés un paper buenísimo sobre arquitectura hexagonal, lo guardás en Obsidian, y dos semanas después estás laburando con Claude y le tenés que **re-explicar todo de cero** porque él no sabe qué leíste. Cada conversación arranca con un Claude amnésico.

engram resolvió la mitad: ahora **tu propio trabajo** (decisiones, bugs, convenciones) sobrevive entre sesiones. Pero el conocimiento externo que vos curás — los artículos que te cambiaron la cabeza, los papers que querés que Claude considere — seguía afuera del loop.

Atlas cierra ese hueco con tres decisiones simples:

1. **`type=atlas` + `source_url` canónico** → siempre sabés de dónde vino cada cosa, pero Atlas sigue leyendo `source` en clips legacy del Web Clipper.
2. **Búsqueda auto-segmentada** → cuando Claude busca algo, separa solo "lo que decidiste vos" de "lo que leíste afuera".
3. **Dedup cross-vault** → el mismo URL clipeado dos veces no se duplica.

---

## Los 4 ingredientes que necesitás

Atlas vive en la intersección de cuatro herramientas. Las instalás **una vez** y después no las tocás más.

### 1. Obsidian

Cualquier vault tuyo sirve — atlas-for-engram detecta el tuyo solo (mirá [Vault Resolution](#vault-resolution) más abajo si querés saber el detalle). Si todavía no usás Obsidian, descargálo de [obsidian.md](https://obsidian.md). Si ya lo usás, no cambia nada.

### 2. Atlas Web Clipper (zip brandeado)

Es el [Obsidian Web Clipper](https://github.com/obsidianmd/obsidian-clipper) oficial pero con el ícono Atlas y default folder `atlas-pool` (en vez de `Clippings`). Lo descargás como zip desde Releases, descomprimís, y hacés "Load unpacked" en tu browser. Detalle completo más abajo en la sección del [Clipper brandeado](#obsidian-web-clipper-brandeado).

### 3. Engram

Es el daemon de memoria persistente — sin él, Atlas no tiene dónde guardar nada. Instalación + setup en el [repo de engram](https://github.com/Gentleman-Programming/engram). Una vez corriendo escucha en `http://127.0.0.1:7437` por default.

### 4. El plugin atlas-for-engram

> _atlas-for-engram hoy tiene dos superficies soportadas: plugin de Claude Code CLI y adapter de OpenCode/GPT. Claude Desktop y la web siguen afuera del scope._

Una sola vez al principio, registrás el marketplace y después instalás el plugin. Son dos comandos encadenados con `&&` para que vaya todo de una:

```bash
/plugin marketplace add github:Kirilgitlsiiejah/atlas-for-engram && /plugin install atlas@atlas-for-engram
```

De ahí en más, **no lo invocás directo** — vive embebido en cada conversación con Claude. El root canónico ahora es `${ATLAS_PLUGIN_ROOT}`; si venís de un install legacy de Claude, `${CLAUDE_PLUGIN_ROOT}` sigue andando como fallback compatible. Cero copies manuales, cero edits a `settings.json`.

#### Actualizar el plugin

Claude Code se auto-actualiza solo, pero si querés forzar la última versión refrescás el marketplace y reinstalás — también dos comandos encadenados:

```bash
/plugin marketplace update atlas-for-engram && /plugin install atlas@atlas-for-engram
```

El re-install pulla la versión refrescada en caliente, así que no hace falta reiniciar Claude Code. Es así de fácil.

---

## AI-first usage

Atlas tiene dos paths para meter conocimiento a engram, dependiendo de dónde está hoy ese conocimiento:

```
¿Los clips ya están en atlas-pool/?  ──►  bulk-inject.sh   (sweep paralelo)
¿Estás investigando algo nuevo?      ──►  atlas-research   (capture+inject one-shot)
```

### bulk-inject (multi-archivo, ya en pool)

Cuando ya tenés un montón de `.md` clipeados en `${ATLAS_VAULT}/atlas-pool/` y querés sincronizarlos todos al engram de un proyecto:

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/inject-atlas/bulk-inject.sh" \
  --project dev [--vault <path>] [--dry-run] [--parallelism N]
```

Procesa los clips `.md` de primer nivel del pool en paralelo (default 4 workers, máximo 8), idempotente vía `topic_key` upsert. No re-ejecutes en loop — engram nativo deduplica.

Contrato de compatibilidad: Atlas **escribe** `source_url` como campo canónico, pero al **leer** markdown del Web Clipper resuelve la URL como `source_url ?? source`. O sea: si un clip viejo trae solo `source`, igual deriva bien el dominio y el `topic_key`.

Output: una línea JSON `{success, project, total, succeeded, failed, files:[...], elapsed_ms}`. Validá con `jq -e .`.

Exit codes: `0` todo ok / `1` algunos fallaron / `2` preflight (engram unreachable, vault inválido, flag malformado).

### atlas-research (one-shot, contenido nuevo)

Cuando estás investigando algo y querés capturar+inyectar de una sola pasada — el script escribe el `.md` al pool **antes** de POSTear a engram, así que si engram cae, el `.md` queda en disco para recovery:

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-research/research.sh" <<'EOF'
{
  "title": "RNN Effectiveness",
  "source_url": "https://karpathy.github.io/2015/05/21/rnn-effectiveness/",
  "tags": ["rnn"],
  "body": "# RNN Effectiveness\n\n...",
  "project": "dev"
}
EOF
```

Required: `body`, `project`. Si no pasás `title`, lo deriva (primer `# H1` del body → último segmento de la URL → falla). Este path AI-first sigue **escribiendo** `source_url` como canónico; la compatibilidad con `source` aplica al path de lectura desde markdown ya clipeado. Output JSON: `{success, wrote_pool, wrote_engram, pool_path, topic_key, obs_id, error?, retry?}`.

Exit codes: `0` pool+engram ok / `1` pool ok pero engram fail (`.md` preservado, te dice cómo reintentar) / `2` pool fail.

### Dependencia: yq v4

Ambos paths usan `yq` v4 para parse/render YAML frontmatter. Instalalo:

- macOS: `brew install yq`
- Debian/Ubuntu: `apt install yq`
- Windows: `choco install yq`

El SessionStart doctor te avisa si falta.

---

## ¿Y después?

Después, **no hay comandos**. Todo es conversación natural con Claude.

Le decís lo que querés en español — *"agregá esto al engram del proyecto dev"*, *"tenés algo sobre WebSockets clipeado?"*, *"mostrame el atlas index"* — y Claude dispara el skill correcto detrás de escena. El plugin existe para que Claude **entienda lo que querés decir** sin que vos tengas que aprender una sintaxis nueva.

---

## Ejemplos de uso real

Estas son cosas que le decís a Claude tal cual, en lenguaje natural. El plugin se encarga del resto.

### Inyectar un clip al engram

> *"agregá al proyecto dev lo que clipeé sobre arquitectura hexagonal"*

Claude busca el `.md` correspondiente en `atlas-pool/`, parsea el frontmatter (título, URL, tags), resuelve la URL como `source_url ?? source`, y lo carga en engram como `type=atlas`, asociado al proyecto que mencionaste. La próxima vez que le preguntes algo relacionado, lo encuentra y lo cita solo.

### Preguntar si ya tenés algo clipeado

> *"tengo algo guardado sobre event sourcing?"*

Claude busca cross-project por URL o por título y te dice qué proyectos lo tienen — útil cuando dudás si ya leíste un paper o no.

### Editar un atlas existente

> *"editá el atlas de hexagonal-architecture y agregale el tag 'ddd'"*

Claude hace el PATCH a engram — sin que tengas que tocar el `.md` ni la API a mano.

### Borrar un clip que ya no querés

> *"borrá del engram el atlas de tal-blog-post"*

Claude lo elimina de engram. Si querés que también borre el `.md` crudo de `atlas-pool/`, se lo decís y listo.

### Ver el catálogo de todo lo que clipeaste

> *"mostrame el atlas index del proyecto dev"*

Claude regenera `Atlas-Index.md` en la raíz de tu vault, agrupado por dominio, con links clicables. Lo abrís en Obsidian y navegás visualmente.

### Pedirle un health check

> *"corré un integrity check del atlas"*

Claude reporta orphans, dangling links, duplicates y atlas malformados — para que mantengas la cosa limpia.

---

## Cómo funciona

```
Browser Web Clipper
        |
        v
   ${ATLAS_VAULT}/atlas-pool/<slug>.md  (raw markdown, sin proyecto)
        |  vos le decís a Claude "inyectá esto al proyecto X"
        v
   engram type=atlas, project=<auto-detect desde git>
        |
        +--> Atlas-Index.md  (auto-regen en cada inject)
        |
        +--> mem_search → separación auto own_work vs atlas
        |
        v
   Browse / retrieve desde Obsidian o Claude Code
```

El core vive bajo `${ATLAS_PLUGIN_ROOT}` cuando lo seteás explícitamente. Si no, Atlas cae a `${CLAUDE_PLUGIN_ROOT}` para installs legacy. Ahí viven hooks, scripts (`_helpers.sh`, `_doctor.sh`, `session-start.sh`) y los 7 skills Bash bajo `skills/`.

## OpenCode / GPT adapter

Si querés usar el mismo core Bash desde OpenCode, no forks nada: apuntás OpenCode al adapter repo-local y listo.

```bash
export ATLAS_PLUGIN_ROOT="/path/to/atlas-for-engram"
export OPENCODE_CONFIG="${ATLAS_PLUGIN_ROOT}/opencode/opencode.json"
export OPENCODE_CONFIG_DIR="${ATLAS_PLUGIN_ROOT}/opencode"
```

Preflight local en Windows/WSL:

- Si corrés validaciones Bash desde WSL sobre un working tree con CRLF, `bash -n` te puede tirar falsos negativos con `$'\r'`. Para validar localmente usá Git for Windows Bash o normalizá a LF ese contenido antes del check.
- Los smokes usan `jq` desde Bash. Tener `jq.exe` visible sólo en PowerShell NO alcanza si después corrés los comandos desde WSL/Git Bash: `jq` tiene que estar en el `PATH` de esa shell también.

Qué trae ese adapter:

- `opencode/opencode.json` — config base del agente Atlas para OpenCode.
- `opencode/prompts/atlas-primary.md` — prompt corto para enrutar a los wrappers correctos.
- `opencode/skills/*/SKILL.md` — wrappers OpenCode que shell-out al mismo core Bash de `skills/`.
- `opencode/manifest.json` — metadata del adapter, versionada igual que `VERSION` y `.claude-plugin/*`.

Tradeoffs del MVP:

- `inject`, `lookup`, `research`, `edit`, `delete`, `index` y `cleanup` usan el mismo core Bash.
- La paridad de hooks automáticos tipo Claude `PostToolUse` NO está resuelta en OpenCode todavía.
- `cleanup` en OpenCode queda como scan/read-only documentado; la remediación sigue siendo manual o coordinada por otros skills.
- No hay build step: todo se valida con `jq`, checks de versiones y `bash -n`.

**Project resolution**: mismo algoritmo que engram core — git remote → git root basename → cwd basename → fallback `dev`.

---

## Skills disponibles

Son 7 skills + 1 hook. No los invocás vos — Claude los dispara solo cuando interpretás lo que pediste. Esta tabla es referencia para que entiendas qué frase activa qué cosa.

| Skill | Frase típica | Qué hace |
|---|---|---|
| `inject-atlas` | *"agregá X al engram del proyecto Y"* | **CREATE** — parsea el `.md` de `atlas-pool/` y lo guarda en engram como `type=atlas` |
| `atlas-edit` | *"editá el atlas X y cambiale Z"* | **UPDATE** — patchea la observación en engram con los campos nuevos |
| `atlas-delete` | *"borrá el atlas X"* | **DELETE** — individual o bulk, con opción de borrar también el `.md` crudo |
| `atlas-lookup` | *"tengo atlas de tal URL?"* | **READ** — búsqueda cross-project por URL o título |
| `atlas-cleanup` | *"corré integrity check"* | **INTEGRITY** — reporta orphans, dangling, duplicates, malformed |
| `atlas-index` | *"mostrame el atlas index"* | **BROWSE** — regenera `Atlas-Index.md` en la raíz del vault |
| `compare-with-atlas` | (auto, no lo invocás) | **READ** — separa results de cada búsqueda en `own_work` vs `atlas` |

> **Nota**: este es un plugin **community / companion** para [engram](https://github.com/Gentleman-Programming/engram). Integra con la HTTP API de engram y sigue las conventions de plugins claude-code, pero **no está oficialmente afiliado, endorsed ni mantenido por el proyecto engram**.

---

## Auto-separación de búsqueda

Cuando le pedís a Claude que busque algo en su memoria, los resultados se dividen automáticamente en dos baldes: **own_work** (tus decisiones, bugs, sesiones de laburo) y **atlas** (clips externos, papers, references). Vos no hacés nada — un PostToolUse hook se dispara después de cada búsqueda, lee el resultado, y lo emite ya segmentado con `source_url` visible para los atlas. Si no hay results atlas, el hook queda silent.

Esto significa que cuando Claude te responde, **siempre sabés** si una afirmación viene de algo que vos decidiste o de algo que clipeaste leyendo afuera.

---

## SessionStart doctor (corre solo)

Cada vez que abrís una sesión nueva o hacés `/clear`, el doctor corre solo en background con timeout de 3s. Nunca bloquea tu sesión. Te avisa si algo está roto y cómo arreglarlo. **6 checks**:

1. **engram reachable** — verifica que el daemon esté arriba
2. **deps present** — chequea que tengas `jq`, `curl`, `rg`, `fd` en PATH
3. **vault resolution** — te dice qué nivel del cascade ganó (L1..L5) y qué path resolvió
4. **L5-fallback missing** — si cae a `$HOME/vault` y no existe, te da remediation
5. **vault layout** — verifica que `<vault>/atlas-pool/` exista
6. **drift detector** — warne si los inline `detect_vault` blocks divergen del canonical en `scripts/_helpers.sh`

Si querés correrlo manual, le decís a Claude *"corré el atlas doctor"* y te tira el reporte.

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

### Cerrá el loop

Una vez que el clip está en `atlas-pool/`, le decís a Claude *"agregá esto al engram del proyecto X"* y él se encarga del resto. A partir de ese momento, cualquier pregunta a Claude que toque ese tema lo encuentra solo.

---

## Vault Resolution

Cada skill que toca el `atlas-pool/` resuelve el vault por una **cascada de 5 niveles**. Gana el primero que matchea — los demás se ignoran.

| Nivel | Fuente                                          | Cuándo se aplica                       |
|-------|-------------------------------------------------|-----------------------------------------|
| **L1** | flag `--vault <path>` pasado al script         | Override puntual sin ensuciar env vars |
| **L2** | env var `$ATLAS_VAULT`                          | Default canónico para tu shell         |
| **L3** | env var `$VAULT_ROOT` (**legacy, deprecated**)  | Compat con setups previos — migrá a `ATLAS_VAULT` |
| **L4** | walk-up desde `$PWD` buscando un marker         | Working tree con vault auto-detectado  |
| **L5** | fallback `$HOME/vault`                          | Si todo lo anterior falla              |

### Markers de walk-up (L4)

El walk-up parte de `$PWD` y sube buscando `.obsidian/` (directorio nativo de Obsidian) o `.atlas-pool` (archivo vacío que creás con `touch .atlas-pool` en la raíz del vault).

> **Importante**: `.atlas-pool` tiene que ser un **archivo**, no un directorio. Si existe como dir, el walk-up lo **ignora** y sigue subiendo. Para automáticamente en `/`, drive roots (`C:/`, `/c`), UNC roots (`//host/share`), o tras 64 iteraciones.

El doctor reporta el nivel resuelto cada sesión (`vault: L4 (walk-up .obsidian) -> /path`) — así sabés exactamente qué branch del cascade ganó.

---

## Configuración

Todas las env vars son **opcionales** — el cascade resuelve solo en la mayoría de los casos. Setealas solo si querés override explícito.

| Env var | Default | Propósito |
|---|---|---|
| `ENGRAM_HOST` | `http://127.0.0.1:7437` | engram HTTP API URL |
| `ENGRAM_PORT` | `7437` | shorthand si `HOST` no está set |
| `ATLAS_VAULT` | (unset; cascade resuelve) | vault root canónico (parent de `atlas-pool/`) |
| `VAULT_ROOT` | (unset; legacy) | **deprecated** — sigue respetado con warning. Migrá a `ATLAS_VAULT` |
| `ATLAS_PROJECTS` | auto-detect | comma-separated list para `atlas-cleanup` cross-project scan |
| `MOVE_RAW_AFTER_INJECT` | `false` | mové `.md` a `atlas-pool/injected/` después de inject |
| `ATLAS_EDIT_CONFIRM_TYPE_CHANGE` | `false` | requiere `=yes` para cambiar type de una obs atlas |

Hooks y skills se registran solos al instalar el plugin — no tocás `settings.json` ni copiás nada a mano.

---

## Troubleshooting

**engram unreachable**: arrancá engram (`engram serve` o como lo corras) y re-chequeá con `curl -sf http://127.0.0.1:7437/health`. Override host con `ENGRAM_HOST=host:port`.

**missing commands**: instalá lo que el doctor flagged. Windows Git Bash: scoop / chocolatey. macOS: `brew install jq curl ripgrep fd`. Linux: `jq curl ripgrep fd-find` con tu package manager.

**atlas-pool not found**: creá el dir (`mkdir -p $HOME/vault/atlas-pool`) y apuntá tu Web Clipper output ahí. Override el parent con `ATLAS_VAULT=/path/to/vault` (o dejá un `.atlas-pool` empty file en la raíz del vault para auto-detect).

**vault detectado en lugar equivocado**: pedíle a Claude *"corré el atlas doctor"* — la línea `vault: L? (...) -> <path>` te dice exactamente qué branch del cascade ganó. Si es L5 y no querés esa default, exportá `$ATLAS_VAULT` o poné `.atlas-pool` marker en la raíz correcta.

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
- [Obsidian Web Clipper](https://obsidian.md/clipper) — extensión oficial de Obsidian (atlas-for-engram incluye un fork brandeado)

---

<div align="center">

**MIT** — David Villalba — 2026

<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>

</div>
