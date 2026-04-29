---
name: atlas-lookup
description: >-
  Busca si una URL ya fue clipeada o inyectada al atlas de engram. Busca en engram
  (type=atlas, todos los proyectos) Y en atlas-pool/ (clips raw sin inyectar).
  Trigger: "tengo atlas de URL X?", "ya clipeé X?", "atlas lookup <url>",
  "buscá atlas por URL", "tenés esto en atlas?". Reporta los 4 escenarios:
  inyectado / sin-inyectar / ambos / ninguno.
---

# atlas-lookup

Pregunta rápida antes de re-clipear: **¿ya tengo esta URL en mi atlas?**

Busca en dos lugares y reporta los 4 escenarios posibles:

| Escenario      | Engram (`type=atlas`) | atlas-pool/ raw |
|----------------|-----------------------|-----------------|
| `both`         | sí                    | sí              |
| `engram_only`  | sí                    | no              |
| `pool_only`    | no                    | sí              |
| `none`         | no                    | no              |

El skill es **read-only** — nunca escribe, borra ni modifica nada. Cuando lee clips raw, trata `source_url` como canónico y `source` como fallback compatible.

> **Nota — cross-project by design**: a diferencia del resto del ecosistema atlas (que auto-detecta `project` desde el git remote / cwd), `lookup` busca en engram **sin filtro de proyecto** para responder "¿tengo esto en algún lado?" globalmente. No requiere ni acepta argumento de proyecto.

## Cuándo activarse

Activate cuando el usuario pregunte cosas como:

- "¿tengo atlas de https://karpathy.github.io/2015/05/21/rnn-effectiveness/?"
- "¿ya clipeé algo de martinfowler.com?"
- "atlas lookup rnn"
- "buscá atlas por URL <url>"
- "¿tenés esto en atlas?" (con URL pegada)
- "antes de clipear esto, fijate si ya lo tengo"

## Procedimiento

### 1. Parsear el request

Extraé del mensaje del usuario:

- **URL completa** (ej: `https://karpathy.github.io/2015/05/21/rnn-effectiveness/`) — el match será exacto + substring.
- **Dominio** (ej: `karpathy.github.io`) — substring search.
- **Keyword** (ej: `rnn`, `event sourcing`) — substring search en title/content/frontmatter.

Si no detectás URL ni keyword en el mensaje, **PREGUNTAR**: "Dale, ¿qué URL o keyword querés buscar?"

### 2. Invocar el script

```bash
bash '${CLAUDE_PLUGIN_ROOT}/skills/atlas-lookup/lookup.sh' '<url-o-substring>'
```

El script devuelve un JSON con esta forma:

```json
{
  "success": true,
  "query": "...",
  "engram_matches": [
    {"id": 123, "project": "dev", "topic_key": "atlas/karpathy.github.io/rnn-effectiveness",
     "title": "RNN Effectiveness", "source_url": "https://...", "content_excerpt": "..."}
  ],
  "pool_matches": [
    {"path": "${ATLAS_VAULT:-$HOME/vault}/atlas-pool/rnn.md", "source_url": "https://...",
     "title": "RNN", "clipped": "2026-04-20"}
  ],
  "scenario": "both",
  "warnings": []
}
```

Si `success: false`, mostrá el error tal cual y parate.

Si vienen `warnings` (ej: engram no responde), mencioná-las breves al final del output.

### 3. Reportar al usuario según `scenario`

#### Escenario `both` — Inyectado en engram + .md en pool

```
✅ Lo tenés en ambos lugares:
- 📚 engram obs #<id> (proyecto: <project>, topic_key: <topic_key>)
- 📥 atlas-pool/<basename(path)> (todavía no borrado del pool)

Acciones posibles:
- Verlo en engram: mem_get_observation <id>
- Borrar el raw del pool (manual): borrá ${ATLAS_VAULT:-$HOME/vault}/atlas-pool/<basename>
- Re-inyectar (si el raw cambió): inyectá al proyecto <project> la info de <slug>
```

Si hay múltiples engram_matches o múltiples pool_matches, listá todos con bullets.

#### Escenario `engram_only` — Solo en engram

```
✅ Está inyectado en engram (raw no presente en pool):
- 📚 obs #<id> (proyecto: <project>, topic_key: <topic_key>)
- source_url: <source_url>

Acciones posibles:
- Verlo: mem_get_observation <id>
- Editarlo: editá el atlas #<id>
- Borrarlo: borrá el atlas #<id>
```

#### Escenario `pool_only` — Solo en atlas-pool, sin inyectar

```
📥 Lo tenés clipeado pero NO inyectado:
- atlas-pool/<basename(path)>
- source_url: <source_url>
- title: <title>
- clipped: <clipped>

Acciones posibles:
- Inyectarlo: inyectá al proyecto X la info de <basename sin .md>
- Verlo: bat '${ATLAS_VAULT:-$HOME/vault}/atlas-pool/<basename>'
```

#### Escenario `none` — No existe en ningún lado

```
❌ No tengo nada con esa URL/keyword.
- Buscado en engram (todos los proyectos, type=atlas): 0 matches
- Buscado en atlas-pool/: 0 matches

Sugerencia: clipealo con Brave (Shift+Alt+O) y después invocá inject-atlas.
```

### 4. Reglas duras

- **Read-only**. Nunca modifiques, borres ni inyectes nada desde este skill.
- **No invoques inject-atlas automáticamente** — solo sugerilo en el output.
- **No invoques atlas-edit ni atlas-index** — este skill solo reporta.
- **Si el script devuelve `success: false`**, mostrá el error tal cual y parate.
- **Si engram está caído**, mencionalo (`warnings` lo va a indicar) pero igual mostrá los `pool_matches` que hayas encontrado.

## Vault resolution

`lookup.sh` resuelve el vault con la cascada de 5 niveles del helper compartido (ver `README.md > Vault Resolution`).

| Nivel | Fuente |
|-------|--------|
| L1    | `--vault <path>` flag pasado al script (`lookup.sh --vault /home/u/notes 'rnn'`) |
| L2    | env var `$ATLAS_VAULT` |
| L3    | env var `$VAULT_ROOT` (**deprecated** — emite warning una vez por sesión) |
| L4    | walk-up desde `$PWD` buscando `.obsidian/` (dir) o `.atlas-pool` (archivo) |
| L5    | fallback `$HOME/vault` |

Migración: pasá de `VAULT_ROOT` a `ATLAS_VAULT` para silenciar el warning.

## Convenciones del usuario

- Idioma: rioplatense voseo cuando hablás con el usuario (vos, dale, listo, fijate).
- NO usar `cat`/`grep`/`find`/`ls` — usar `bat`/`rg`/`fd`/`eza`.
- NO mencionar "Co-Authored-By" en nada.
- Tono: directo. Decí qué tenés y qué hacer al respecto, sin parrafadas.
