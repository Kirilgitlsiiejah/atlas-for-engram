---
name: atlas-index
description: >-
  Genera o regenera el catálogo navegable Atlas-Index.md en la raíz del vault Obsidian,
  con todas las observaciones type=atlas del proyecto agrupadas por source_domain.
  Trigger: "atlas index", "mostrame el index del atlas", "qué tengo en atlas <proyecto>",
  "regenerá el atlas index", "atlas index dev". Si no se especifica proyecto, usar 'dev' por default.
---

# atlas-index

Genera un **catálogo navegable** de todas las observaciones `type=atlas` que tenés inyectadas en engram para un proyecto dado, agrupadas por `source_domain` (extraído del `topic_key` `atlas/<domain>/<slug>`).

El output es un único archivo Markdown en la raíz del vault Obsidian (`${ATLAS_VAULT:-$HOME/vault}/Atlas-Index.md`), pensado para ser:

- Linkeable desde otras notas: `[[Atlas-Index]]`
- Navegable por sección de dominio: `[[Atlas-Index#karpathy.github.io]]`
- Regenerable on-demand (idempotente, atomic write)

## Modelo conceptual

```
engram (type=atlas, project=X)  ──[GET /observations/recent]──►  generate.sh
                                                                     │
                                                                     ▼
                                                       ${ATLAS_VAULT:-$HOME/vault}/Atlas-Index.md
                                                       (agrupado por source_domain)
```

Nada se borra, nada se modifica fuera del `Atlas-Index.md`. La generación es 100% derivable del estado actual de engram.

## Cuándo activarse

Activarse cuando el usuario pida algo del estilo:

- "atlas index"
- "regenerá el atlas index"
- "mostrame el index del atlas"
- "qué tengo en atlas dev"
- "atlas index dev"
- "atlas index del proyecto vault"

## Procedimiento

### 1. Parsear el request

Extraer el **proyecto** del mensaje. Patrones:

- "atlas index **dev**" → `project=dev`
- "qué tengo en atlas **vault**" → `project=vault`
- "atlas index del proyecto **backend**" → `project=backend`

Si no se menciona ninguno, usar `dev` por default.

### 2. Invocar el script

```bash
bash '${CLAUDE_PLUGIN_ROOT}/skills/atlas-index/generate.sh' <project>
```

El script:

- Llama a `GET http://127.0.0.1:7437/observations/recent?project=<X>&limit=500`
- Filtra `type=atlas` con jq
- Enriquece cada entry con timestamp (`created_at` → epoch + fecha legible) y tags extraídos del content (`tags: [...]`, `tags: a, b`, o `**Tags**: a, b`)
- Genera tres secciones en orden: **Recent (last 7 days)** ordenado por timestamp desc, **By Domain** (agrupado por `source_domain` del `topic_key`, count desc), y **By Tag** (omitida si no hay tags en ninguna obs)
- Header con stats: total, domains, tags únicos, recent count, oldest/newest dates
- Escribe atómicamente `${ATLAS_VAULT:-$HOME/vault}/Atlas-Index.md`
- Imprime un JSON resumen a stdout: `{path, project, total, domains, tags, recent_count, oldest, newest, timestamp, top3_domains, top3_tags}`
- Exit 0 = OK, exit 1 = engram inalcanzable

Override del window con env var `RECENT_DAYS` (default 7).

### 3. Reportar al usuario

Capturar el JSON de stdout y reportar (rioplatense, directo):

```
Listo, regenerado el Atlas-Index.

  path:       ${ATLAS_VAULT:-$HOME/vault}/Atlas-Index.md
  entries:    <total>
  domains:    <domains>
  top 3:      <domain1> (<n1>), <domain2> (<n2>), <domain3> (<n3>)
  timestamp:  <timestamp UTC>
```

Para sacar el "top 3 domains" leé las primeras secciones del archivo generado (ya viene ordenado descendente por count) o reextraelas del propio output del script.

### 4. Sugerir uso

Cerrar con:

```
Podés abrir el archivo en Obsidian o linkearlo desde otras notas:
  [[Atlas-Index]]

Para sub-secciones por dominio:
  [[Atlas-Index#karpathy.github.io]]
```

## Reglas duras

- **NO modificar** observaciones en engram (este skill es read-only contra engram).
- **NO borrar** archivos del vault (sólo escribe `Atlas-Index.md`).
- **NO commitear** nada.
- Si engram está caído (el script emite JSON `{success:false,...}` a stderr), reportar el error claro y parar — no inventar contenido ni dejar el archivo a medias. El write es atomic en POSIX; en Windows con `Atlas-Index.md` abierto en Obsidian puede requerir retry (el script ya hace 3 intentos con backoff de 500ms; si fallan todos, mantiene el `.tmp` para debug y emite error).
- Si el proyecto no tiene observaciones `type=atlas`, igual generar el archivo con "0 entries" y reportarlo — no fallar.

## Vault resolution

`generate.sh` resuelve el vault con la cascada de 5 niveles del helper compartido (ver `README.md > Vault Resolution`). El `Atlas-Index.md` se escribe en la raíz del vault resuelto.

| Nivel | Fuente |
|-------|--------|
| L1    | `--vault <path>` flag pasado al script (`generate.sh --vault /home/u/notes dev`) |
| L2    | env var `$ATLAS_VAULT` |
| L3    | env var `$VAULT_ROOT` (**deprecated** — emite warning una vez por sesión) |
| L4    | walk-up desde `$PWD` buscando `.obsidian/` (dir) o `.atlas-pool` (archivo) |
| L5    | fallback `$HOME/vault` |

Migración: pasá de `VAULT_ROOT` a `ATLAS_VAULT` para silenciar el warning.

## Convenciones del usuario

- Idioma: rioplatense voseo (vos, dale, listo, bien)
- NO usar `cat`/`grep`/`find`/`ls` — usar `bat`/`rg`/`fd`/`eza`
- NO mencionar "Co-Authored-By" en nada
- Tono: directo, sin parrafadas
