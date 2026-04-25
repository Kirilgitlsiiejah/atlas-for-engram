---
name: atlas-edit
description: >-
  Edita una observación type=atlas existente en engram. Permite cambiar title, source_url,
  content, tags, o re-inyectar contenido fresco desde el .md crudo en atlas-pool/.
  Trigger: "editá el atlas X", "cambiá el título de atlas X", "actualizá el source_url de Y",
  "re-inyectá X", "atlas edit <id-or-title>". Preserva el obs ID y topic_key (no crea duplicado).
---

# atlas-edit

Edita una observación `type=atlas` ya existente en engram **sin perder el ID ni el topic_key**. Es la operación UPDATE del ecosistema atlas plug-and-play (CREATE = `inject-atlas`, READ = `atlas-index` / `compare-with-atlas`).

## Modelo conceptual

```
inject-atlas  →  CREATE  (obs nueva)
atlas-index   →  READ    (lista materializada)
compare-...   →  READ    (diff pool vs engram)
atlas-edit    →  UPDATE  ← este skill
```

La edición es **solo a engram**. El `.md` crudo en `${ATLAS_VAULT:-$HOME/vault}/atlas-pool/` queda intacto — si el usuario quiere editar el raw, lo hace a mano en Obsidian.

## Cuándo activarse

Activarse si el usuario pide algo como:
- "editá el atlas #1936"
- "cambiá el título de atlas Karpathy a 'RNN Effectiveness (revisado)'"
- "actualizá el source_url de event-driven a https://..."
- "re-inyectá rnn-effectiveness" (= leer .md crudo y refrescar `content` en engram)
- "atlas edit bridge-health-check"

Si falta el identificador del obs o no queda claro qué cambiar, **PREGUNTAR** antes de actuar.

## Procedimiento

### 1. Parsear el request

Identificar tres cosas:
- **Cuál obs editar**: por ID (`#NNN`), por título exacto, o por slug del topic_key.
- **Qué campos cambiar**: title / source_url (va dentro de content) / content / tags / topic_key / project / scope / type.
- **Modo de edición**: field-level edit (cambios puntuales) vs re-inject from raw (refrescar todo el content desde el `.md`).

### 2. Localizar la obs

- Si el usuario dio **obs ID** (`#NNN`): hacer GET directo.
  ```bash
  curl -sf "${ENGRAM_HOST:-http://127.0.0.1:7437}/observations/<ID>"
  ```
- Si el usuario dio **título o slug**: usar `mem_search` con keywords + filtrar por `type=atlas`. Mostrar matches numerados:
  ```
  Encontré varios atlas para "karpathy":
    1. #1812 — RNN Effectiveness        (atlas/karpathy.github.io/rnn-effectiveness)
    2. #1934 — Software 2.0             (atlas/karpathy.github.io/software-2-0)
  ¿Cuál? (1/2)
  ```
- Si **0 matches**: avisar, no inventar.

### 3. Mostrar estado actual

Antes de cambiar nada, mostrar:
```
Editando obs #NNN:
  title:      <current>
  type:       <current>
  topic_key:  <current>
  project:    <current>
  scope:      <current>
  content (preview, 200 chars):
    <...>
```

### 4. Decidir el modo de edición

**Field-level edit** — usuario dijo "cambiá el title a X":
- Solo ese field. El resto queda igual.

**Re-inject from raw** — usuario dijo "re-inyectá X":
- Localizar el `.md` correspondiente en `atlas-pool/` (matchear por topic_key, title, o source_url).
- Leer el archivo, parsear frontmatter + cuerpo (mismo formato que `inject-atlas`).
- Calcular hash del nuevo content vs el actual en engram.
- Si **idéntico**: avisar "no hay cambios, salgo sin hacer nada" y parar.
- Si **diferente**: armar nuevo `content` con el formato canonical (Source / Clipped / Author / Tags / --- / body) y mandarlo como update.

**Multi-field edit** — usuario dio JSON o lista:
- Mandar todos los campos a la vez en el mismo PATCH.

### 5. Confirmar antes de ejecutar

Mostrar diff y pedir OK explícito:
```
Cambios a aplicar a obs #NNN:
  - title:      "<old>" → "<new>"
  - source_url: "<old>" → "<new>"   (embebido en content)
¿Confirmar? [Y/n]
```

Si el usuario dice no, salir limpio.

### 6. Ejecutar via PATCH

Invocar el script:
```bash
bash '${CLAUDE_PLUGIN_ROOT}/skills/atlas-edit/edit.sh' <obs_id> <project> <field=value> [<field=value> ...]
```

Campos soportados (alineados con engram `UpdateObservationParams`):
- `title=...`
- `type=...`
- `content=...`
- `project=...`
- `scope=...`
- `topic_key=...`

El script construye el JSON body con `jq` y hace `PATCH /observations/<id>`. Si engram responde **405 Method Not Allowed** (versión vieja sin PATCH), el script cae al fallback DELETE + POST preservando topic_key (upsert vía mem_save semantics).

**Importante**: para `source_url` el campo está dentro del cuerpo de `content` (no es un field separado en engram). Para cambiarlo, el modelo construye el nuevo content completo y lo manda como `content=...`.

### 7. Regenerar Atlas-Index

Después del PATCH exitoso:
```bash
bash '${CLAUDE_PLUGIN_ROOT}/skills/atlas-index/generate.sh' <project>
```

- Si falla: warning no-bloqueante (`⚠️ Index regeneration failed. Run manually.`).
- Si funciona: sumar al output `📚 Atlas-Index.md regenerado: <total> entries`.

### 8. Confirmar al usuario

Output (rioplatense, directo):
```
✅ Obs #NNN actualizada
   Cambios:
     - title:      <old> → <new>
   📚 Atlas-Index.md regenerado: <total> entries
```

## Reglas duras

- **NUNCA modificar** el `.md` crudo en `atlas-pool/`. La edición es solo a engram.
- **NUNCA crear obs nueva**. Si el ID no existe, parar y avisar — no fallback a `mem_save`.
- **NUNCA cambiar el topic_key sin pedir confirmación explícita** — rompe la trazabilidad atlas-pool ↔ engram.
- Si el PATCH falla por causa que no es 405 (404, 500, etc.): reportar el error claro y parar. No intentar fallback ciego.
- No commitear, no crear archivos auxiliares, no escribir reportes.

## Vault resolution

Este skill **no tiene flag `--vault`** porque no toca el `atlas-pool/` ni el filesystem del vault — la edición es solo a engram. Las referencias a `${ATLAS_VAULT:-$HOME/vault}/atlas-pool/` en este SKILL.md son informativas (el modelo puede leer el raw para re-inyectar, pero esa lectura usa la misma cascada que el resto del ecosistema — ver `README.md > Vault Resolution`).

Migración: si tenías `VAULT_ROOT` exportado, cambialo a `ATLAS_VAULT`.

## Convenciones del usuario

- Idioma: rioplatense voseo (vos, dale, listo, bien, fantástico).
- NO usar `cat`/`grep`/`find`/`ls` — usar `bat`/`rg`/`fd`/`eza`.
- NO mencionar "Co-Authored-By" en nada.
- Tono: directo, sin parrafadas.
