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

1. **`type=atlas` + `source_url` mandatory** → siempre sabés de dónde vino cada cosa.
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

Una sola vez al principio, instalás el plugin desde el marketplace de Claude Code apuntando a `Kirilgitlsiiejah/atlas-for-engram`:

```bash
/plugin install atlas@github:Kirilgitlsiiejah/atlas-for-engram
```

De ahí en más, **no lo invocás directo** — vive embebido en cada conversación con Claude. Skills, hooks y scripts se resuelven solos desde `${CLAUDE_PLUGIN_ROOT}`. Cero copies manuales, cero edits a `settings.json`.

#### Actualizar el plugin

Claude Code se auto-actualiza solo, pero si querés forzar la última versión refrescás el marketplace y reiniciás:

```bash
/plugin marketplace update github:Kirilgitlsiiejah/atlas-for-engram
```

Cerrá y abrí Claude Code de nuevo — la nueva versión queda activa al arrancar. Es así de fácil.

---

## ¿Y después?

Después, **no hay comandos**. Todo es conversación natural con Claude.

Le decís lo que querés en español — *"agregá esto al engram del proyecto dev"*, *"tenés algo sobre WebSockets clipeado?"*, *"mostrame el atlas index"* — y Claude dispara el skill correcto detrás de escena. El plugin existe para que Claude **entienda lo que querés decir** sin que vos tengas que aprender una sintaxis nueva.

---

## Ejemplos de uso real

Estas son cosas que le decís a Claude tal cual, en lenguaje natural. El plugin se encarga del resto.

### Inyectar un clip al engram

> *"agregá al proyecto dev lo que clipeé sobre arquitectura hexagonal"*

Claude busca el `.md` correspondiente en `atlas-pool/`, parsea el frontmatter (título, URL, tags), y lo carga en engram como `type=atlas`, asociado al proyecto que mencionaste. La próxima vez que le preguntes algo relacionado, lo encuentra y lo cita solo.

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

El plugin vive bajo `${CLAUDE_PLUGIN_ROOT}` post-install: hooks, scripts (`_helpers.sh`, `_doctor.sh`, `session-start.sh`) y los 7 skills bajo `skills/`.

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
