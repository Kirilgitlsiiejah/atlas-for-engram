---
name: atlas-delete
description: >-
  Elimina observaciones type=atlas de engram. Soporta delete individual por obs ID,
  o bulk por filter (domain, project, slug pattern). Opcionalmente borra también el .md crudo
  de atlas-pool/. SIEMPRE pide confirmación con preview antes de borrar. Trigger:
  "borrá el atlas X", "eliminá atlas de dominio Y", "limpiá atlas de proyecto Z",
  "atlas delete <id-or-filter>".
---

# atlas-delete

Operación **DELETE** del ecosistema atlas. Borra observaciones `type=atlas` de engram (individual o bulk) y, opcionalmente, también los `.md` crudos del `atlas-pool/`.

Diseñado como contraparte simétrica de `inject-atlas` (creación) y `atlas-index` (lectura). Mismas convenciones, mismo stack (`bash + curl + jq`), mismo patrón defensivo.

## Modelo conceptual

```
Usuario pide delete (id o filter)
        │
        ▼
delete.sh --preview <filter>  ──►  lista candidatos
        │
        ▼
Confirmación obligatoria (default NO)
        │
        ▼
delete.sh --execute <ids> [--with-raw]
        │
        ├──► DELETE /observations/<id> a engram (loop)
        └──► (opcional) borrar .md de atlas-pool/
        │
        ▼
atlas-index/generate.sh <project>  ──►  Atlas-Index.md regenerado
```

**Nada se borra sin confirmación explícita del usuario.** El default de toda confirmación es NO.

## Cuándo activarse

Triggers típicos:

- "borrá el atlas #1937"
- "eliminá atlas de dominio karpathy.github.io"
- "limpiá atlas de proyecto dev"
- "borrá atlas que empiecen con test-"
- "atlas delete <id>"
- "borrá los atlas de testing del proyecto vault"

## Procedimiento

### 1. Parsear el request — identificar modo

| Modo | Patrón | Ejemplo de filter |
|------|--------|-------------------|
| **Individual** | obs ID explícito | `--id=1937` |
| **Bulk por domain** | "dominio X", "de X.com" | `--domain=karpathy.github.io` |
| **Bulk por proyecto** | "proyecto X" sin más | `--project=dev` |
| **Bulk por slug pattern** | "que empiecen con", "que contengan" | `--slug=test-` |
| **Combinado** | proyecto + domain | `--project=dev --domain=karpathy.github.io` |

Si el usuario no especifica proyecto, default = `dev`.

### 2. Listar candidatos (preview obligatorio)

```bash
bash '${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-delete/delete.sh' --preview <filter_args>
```

El script devuelve por stdout un JSON array con los obs candidatos:

```json
[
  {"id": 1937, "title": "Karpathy RNN", "topic_key": "atlas/karpathy.github.io/rnn-effectiveness"},
  {"id": 1942, "title": "Karpathy Software 2.0", "topic_key": "atlas/karpathy.github.io/software-2"}
]
```

Mostrar al usuario:

```
Candidatos a borrar (4 obs):
  #1937 — Karpathy RNN — atlas/karpathy.github.io/rnn-effectiveness
  #1942 — Karpathy Software 2.0 — atlas/karpathy.github.io/software-2
  ...
```

Si el preview viene vacío, decirlo claro y parar — no avanzar a confirmación.

### 3. Confirmación obligatoria

```
Vas a borrar 4 observaciones de engram.
Confirmás? [y/N]
```

**Default = NO.** Si el usuario no responde `y`/`yes`/`sí`, abortar sin tocar nada.

### 4. Preguntar sobre el .md crudo

```
Tambien borro los .md crudos de ${ATLAS_VAULT:-$HOME/vault}/atlas-pool/? [y/N]
```

**Default = NO.** La inyección original fue no-destructiva, mantener simetría — el `.md` del pool puede sobrevivir al borrado de la obs sin problema.

### 5. Ejecutar delete

```bash
bash '${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-delete/delete.sh' --execute <id1> <id2> ... [--with-raw]
```

El script devuelve por stdout un JSON resumen:

```json
{
  "success": true,
  "deleted_obs": ["1937", "1942"],
  "deleted_raw": ["karpathy-rnn.md"],
  "failed": []
}
```

### 6. Regenerar Atlas-Index (si hubo deletes)

```bash
bash '${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-index/generate.sh' <project>
```

Solo si `deleted_obs` no está vacío.

### 7. Reportar al usuario

```
Borradas 4 obs: #1937, #1942, #1948, #1950
.md crudos borrados: 2 (otros 2 ya no existian en pool)
Atlas-Index.md regenerado: <total> entries
```

Si hubo `failed`, listarlos también con su motivo presunto (404, server error, etc.).

## Reglas duras

- **NUNCA** borrar sin `--execute` explícito ni sin confirmación del usuario.
- **NUNCA** borrar sin haber mostrado el preview primero.
- El default de toda confirmación es NO.
- Si engram está caído, parar — no inventar deletes "exitosos".
- Si el script devuelve `failed`, NO reintentar automáticamente: reportar al usuario y dejar que decida.
- El `.md` crudo solo se borra si el usuario lo pide explícitamente (`--with-raw`).
- NO borrar `Atlas-Index.md` — eso es regenerable.
- NO modificar otros skills, NO commitear nada.

## Vault resolution

`delete.sh` resuelve el vault con la cascada de 5 niveles del helper compartido (ver `README.md > Vault Resolution`).

| Nivel | Fuente |
|-------|--------|
| L1    | `--vault <path>` flag pasado al script (`delete.sh --vault /home/u/notes --execute 1937 --with-raw`) |
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
