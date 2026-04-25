---
name: inject-atlas
description: Inyecta un clip del atlas-pool a engram asignándolo a un proyecto específico. Usar cuando el usuario diga "inyectá al proyecto X la info de Y", "agregá conocimiento a engram de Y", "inject Y to project X", o variantes. El skill lee el .md de ${VAULT_ROOT:-$HOME/vault}/atlas-pool\, parsea frontmatter, y llama mem_save con type=atlas asignado al proyecto que el usuario indicó.
---

# inject-atlas

Inyecta un clip crudo del **atlas-pool** (clips de Obsidian Web Clipper sin proyecto asignado) a **engram**, vinculándolo a un proyecto específico. La operación es **no-destructiva**: el `.md` original queda intacto en `${VAULT_ROOT:-$HOME/vault}/atlas-pool\`.

## Modelo conceptual

```
Brave + Web Clipper  →  ${VAULT_ROOT:-$HOME/vault}/atlas-pool\<slug>.md   (crudo, huérfano)
Usuario invoca skill →  mem_save(type=atlas, project=<X>)   (clasificado)
```

El archivo crudo es la fuente de verdad reproducible. La entrada en engram es el índice consultable por proyecto.

**Dependencia**: este skill llama al script `~/.claude/skills/atlas-index/generate.sh` al final de cada inyección exitosa para mantener Atlas-Index.md sincronizado. Si el script no existe o falla, la inyección a engram NO se cancela — solo se emite warning.

## Cuándo activarse

Activarse cuando el usuario pida algo del estilo:
- "inyectá al proyecto **dev** la info de **Karpathy sobre RNN**"
- "agregá a engram del proyecto **vault** ese clip de **martinfowler**"
- "inject **event-sourcing.md** to project **backend**"
- "metele al engram de **X** lo de **Y**"

Si el usuario no especifica proyecto o clip claramente, **PREGUNTAR** antes de actuar.

## Procedimiento

### 1. Parsear el request

Extraer dos cosas del mensaje del usuario:
- **Identificador del clip**: título aproximado, slug, source_url, o filename
- **Proyecto destino**: el nombre del proyecto engram

**Project detection**: si el usuario no especifica proyecto en el trigger ("inyectá al proyecto X"), auto-detectá el proyecto siguiendo el patrón engram:
1. `git remote get-url origin` → último segmento sin `.git`
2. `git rev-parse --show-toplevel` → basename
3. `basename "$PWD"`
4. fallback `"dev"`

Confirmá al usuario qué proyecto detectaste **antes** de inyectar. Ejemplo:

```
Detecté project=<X> desde git remote. ¿Inyecto ahí o querés otro?
```

Si el usuario tampoco da clip claramente, **PREGUNTAR** antes de actuar. Ejemplo: "Dale, ¿qué clip te interesa? ¿Mando los más recientes del pool?"

### 2. Localizar el archivo en atlas-pool

Listar el pool con `fd` (NO usar `find`/`ls`):

```bash
fd -e md . "${VAULT_ROOT:-$HOME/vault}/atlas-pool" --max-depth 1
```

O en PowerShell:
```powershell
Get-ChildItem "${VAULT_ROOT:-$HOME/vault}/atlas-pool\*.md" | Select-Object Name, LastWriteTime
```

Estrategia de match (en orden):
1. Match exacto por filename (con o sin `.md`)
2. Match parcial por filename (substring case-insensitive)
3. Match por `title` en frontmatter
4. Match por `source` / `source_url` en frontmatter

Resultado:
- **0 matches**: mostrar los 5 archivos más recientes y pedir que el usuario clarifique.
- **1 match**: continuar al paso 3.
- **>1 matches**: mostrar lista numerada y pedir que elija. Ejemplo:
  ```
  Encontré varios candidatos para "karpathy":
    1. rnn-effectiveness.md       (clipped 2025-11-12)
    2. software-2-0.md             (clipped 2025-12-03)
    3. neural-networks-zero.md     (clipped 2026-01-08)
  ¿Cuál? (1/2/3)
  ```

### 3. Parsear el .md

Leer el archivo y separar frontmatter YAML del cuerpo. Campos esperables del Web Clipper:
- `source` o `source_url` — URL original
- `title` — título del artículo
- `clipped` o `created` — fecha de captura
- `tags` — lista de tags
- `author` — autor

Si no hay `source_url` ni `source`: advertir ("Este clip no tiene URL de origen, lo trato como manual") pero **continuar**.

### 4. Verificar duplicado (3 capas)

- **Capa 1 — source_url match exacto**: `mem_search` con type=atlas + project=<X> + source_url contains.
  Si match → preguntar `[U]pdate / [S]kip / [C]reate-new` (default Skip).

- **Capa 2 — title match exacto**: si source_url no match, intentar match por title exacto.
  Si match → mostrar al usuario y confirmar si es duplicado real.

- **Capa 3 — content hash match (NUEVO)**: calcular SHA-256 del cuerpo normalizado del .md
  (lowercase, whitespace collapsed, sin frontmatter). Comparar con hashes de obs existentes
  (almacenado como `content_hash` en metadata o re-calculado on-the-fly desde el content de cada obs atlas).
  Si match → ⚠️ WARN explícito: "Mismo contenido detectado en obs #NNN (source_url distinto: <other_url>).
  Posible re-clip del mismo artículo bajo URL alternativa. ¿Continuar igual? [y/N]" (default NO).

Comando para hash (orden de preferencia: Git Bash + Linux primero, macOS después, openssl como fallback universal):

```bash
# Linux + Git Bash (Windows): coreutils incluye sha256sum
sha256sum <file.md> | awk '{print $1}'

# macOS fallback (no tiene sha256sum por default, pero sí shasum)
shasum -a 256 <file.md> | awk '{print $1}'

# Fallback universal (cualquier sistema con OpenSSL)
openssl dgst -sha256 <file.md> | awk '{print $NF}'
```

Las tres producen el **mismo hash** (256-bit SHA-2). El `awk '{print $1}'` extrae solo el hex digest, descartando el filename/etiqueta que cada herramienta agrega al output.

Acciones disponibles tras match (capa 1 o 2):

```
Ya existe en engram (project=<X>):
  obs #<ID>
  topic_key: <existing_topic_key>
  title: <título existente>

¿Qué hago? [U]pdate / [S]kip / [C]reate-new   (default: Skip)
```

- **Update**: usar `mem_update` con el `id` existente, mismo `topic_key`.
- **Skip**: salir sin tocar nada, confirmar al usuario.
- **Create-new**: continuar al paso 5 sufijando el `topic_key` con `-2`, `-3`, etc.

El usuario decide en cada caso. Nunca crear duplicado silencioso.

### 4.5. Validar mínimum metadata (NUEVO)

Después de parsear frontmatter (paso 3) y antes de construir topic_key (paso 5):

- **FAIL si falta title**:

  ```
  ❌ Inyección abortada: el clip no tiene title en frontmatter ni filename utilizable.
  Fix: editá el .md y agregá `title: <título>` en el frontmatter.
  Path: <path al .md>
  ```

  Abortar sin tocar engram.

- **WARN si falta source_url**:

  ```
  ⚠️ Sin source_url — usaré fallback topic_key=atlas/unknown/<slug>.
  Sugerencia: agregá `source_url: <url>` en el frontmatter para mejor categorización.
  ¿Continuar igual? [y/N]
  ```

- **WARN si body < 200 chars**:

  ```
  ⚠️ Body muy corto (<N> chars). Posible clip incompleto.
  Preview: <primeros 100 chars>
  ¿Continuar igual? [y/N]
  ```

El usuario decide. Estas son guards de calidad, no bloqueos rígidos.

### 5. Construir topic_key

Formato: `atlas/<domain>/<slug>`

**Domain**: extraer del `source_url` con regex, limpiar:
- Quitar `www.`
- Lowercase
- Sin puerto ni path

**Slug**: tomar el filename sin `.md`, lowercased, solo alphanumeric + dashes (reemplazar otros chars por `-`, colapsar dashes consecutivos).

Ejemplos:

| source_url | filename | topic_key |
|------------|----------|-----------|
| `https://karpathy.github.io/2015/05/21/rnn-effectiveness/` | `rnn-effectiveness.md` | `atlas/karpathy.github.io/rnn-effectiveness` |
| `https://martinfowler.com/articles/event-driven.html` | `event-driven.md` | `atlas/martinfowler.com/event-driven` |
| `https://www.smashingmagazine.com/2024/css-grid/` | `css-grid-tips.md` | `atlas/smashingmagazine.com/css-grid-tips` |
| (sin URL) | `mis-notas.md` | `atlas/unknown/mis-notas` |

### 6. Llamar mem_save

```
mem_save(
  title: <title del frontmatter, o filename sin .md si no hay>,
  type: "atlas",
  project: "<X del usuario>",
  scope: "project",
  topic_key: "atlas/<domain>/<slug>",
  content: """
**Source**: <source_url o "manual clip">
**Clipped**: <fecha del frontmatter o "unknown">
**Author**: <author si existe, omitir línea si no>
**Tags**: <tags si existen, omitir línea si no>

---

<cuerpo completo del .md, sin el frontmatter>
"""
)
```

Si fue **Update** en el paso 4: usar `mem_update(id: <existing_id>, ...)` con los mismos campos.

### 7. Confirmar al usuario

Output exacto (rioplatense, directo):

```
Listo, inyectado obs #<NNN>
  project:    <X>
  topic_key:  atlas/<domain>/<slug>
  title:      <título>
  source:     <source_url>

El crudo sigue en atlas-pool/<filename>.md (no se borra).
Para retrievar: mem_search "<keyword>" project=<X>
```

### 8. NO borrar el archivo de atlas-pool (default)

El archivo crudo queda en `atlas-pool/<file>.md`. La inyección es no-destructiva por default.

Reglas duras complementarias:

- **NUNCA modificar** el `.md` original (ni siquiera el frontmatter).
- **NO crear** archivos auxiliares, scripts, ni reportes.
- **NO commitear** nada.
- Si algo falla a mitad de camino (archivo corrupto, mem_save error), reportar el error claro y parar — no intentar reparar el `.md` ni reintentar en silencio.

### 8.5. Workflow post-inyección (NUEVO, opt-in)

Si el usuario configuró `MOVE_RAW_AFTER_INJECT=true` (env var o frontmatter del propio SKILL.md), después de inyección exitosa:

```bash
mkdir -p '${VAULT_ROOT:-$HOME/vault}/atlas-pool/injected'
mv '${VAULT_ROOT:-$HOME/vault}/atlas-pool/<file>.md' '${VAULT_ROOT:-$HOME/vault}/atlas-pool/injected/<file>.md'
```

Esto separa visualmente los clips ya procesados de los pendientes en `atlas-pool/`.
La carpeta `injected/` está dentro de atlas-pool/ (mismo scope), no afecta otros skills.

**Primera vez** que el usuario invoque inject-atlas, preguntar:

```
¿Querés que inyecciones futuras muevan el .md raw a atlas-pool/injected/ después de inyectar?
[Y]es (recomendado para keep pool clean) / [N]o (mantener no-destructive) / [A]sk-each-time
```

Persistir la elección en una env var sugerida o en una sección "Preferences" del SKILL.md.

Si la elección es "Ask-each-time", preguntar después de cada inyección.

### 9. Regenerar Atlas-Index.md (auto)

Después de confirmar la inyección al usuario, invocar atomicamente el script de atlas-index:

    bash '$HOME/.claude/skills/atlas-index/generate.sh' <proyecto>

Donde `<proyecto>` es el mismo proyecto al que se inyectó (paso 6).

- **Si la regeneración falla** (engram no responde, jq falta, etc.): NO bloquear. Solo log un warning al usuario:

      ⚠️ Index regeneration failed (no bloqueante). Run `atlas index <proyecto>` manually.

- **Si funciona**: agregar al output de confirmación al usuario:

      📚 Atlas-Index.md actualizado: <total> entries, <domains> sources.

La regeneración es atomic (write a .tmp + rename) — el archivo nunca queda a medias aunque haya error mid-write.

## Convenciones del usuario

- Idioma: rioplatense voseo cuando hablás con el usuario (vos, dale, listo, bien)
- NO usar `cat`/`grep`/`find`/`ls` — usar `bat`/`rg`/`fd`/`eza`
- NO mencionar "Co-Authored-By" en nada
- Tono: directo, sin parrafadas. Decí lo que hiciste y listo.
