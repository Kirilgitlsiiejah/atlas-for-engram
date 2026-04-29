---
name: atlas-cleanup
description: >-
  Hace integrity check del ecosistema atlas: detecta orphans (engram sin raw), dangling (raw sin inyectar),
  duplicates (mismo source_url cross-project), malformed (sin source_url o topic_key inválido).
  Reporta hallazgos categorizados y ofrece remediación interactiva. Trigger: "limpiá atlas",
  "buscá orphans", "atlas integrity check", "atlas health", "atlas cleanup".
---

# atlas-cleanup

Operación **READ-ONLY** de auditoría del ecosistema atlas. Escanea **engram** (obs `type=atlas`) cruzado con los clips raw de primer nivel en **`atlas-pool/`** para detectar problemas de integridad. Al leer frontmatter del pool, resuelve la URL canónica con precedencia **`source_url ?? source`**: `source_url` gana si existe; `source` queda como fallback compatible para clips viejos del Web Clipper. Reporta categorizado y, si el usuario lo pide, **coordina** la remediación llamando a otros skills (`atlas-delete`, `inject-atlas`, `atlas-edit`). **Nunca** ejecuta deletes o edits por sí mismo.

Diseñado como contraparte simétrica de `atlas-index` (read-only de presentación). Mismo stack (`bash + curl + jq + rg + fd`), mismo patrón defensivo, mismas convenciones.

## Modelo conceptual

```
                  engram (obs type=atlas)
                          │
                          │  cross-check
                          ▼
             ┌─────────────────────┐
             │  cleanup.sh --scan  │  ← read-only, JSON output
             └─────────────────────┘
                          │
                          ▼
                  atlas-pool/*.md
                          │
                          ▼
            ┌─────────────────────────┐
            │  Reporte categorizado   │
            │  - ORPHANS              │
            │  - DANGLING             │
            │  - DUPLICATES           │
            │  - MALFORMED            │
            └─────────────────────────┘
                          │
                          ▼
            ¿Usuario quiere remediar?
                          │
                ┌─────────┴─────────┐
                ▼                   ▼
        atlas-delete         inject-atlas / atlas-edit
        (otro skill)         (otros skills)
```

## Categorías detectadas

| Categoría | Significado | Causa típica |
|-----------|-------------|--------------|
| **ORPHANS** | obs `type=atlas` en engram cuyo `.md` original ya **NO existe** en `atlas-pool/` | Borraron el raw pero el inject quedó |
| **DANGLING** | clip `.md` en `atlas-pool/` que **NUNCA** se inyectó a ningún proyecto | Web-clippeado y olvidado |
| **DUPLICATES** | Mismo `source_url` aparece en **>1 proyecto** | Puede ser intencional (compartir conocimiento) o accidental |
| **MALFORMED** | obs sin `source_url`, sin `title`, o con `topic_key` que no matchea `atlas/<domain>/<slug>` | Inyección manual rota o test residuals |

## Cuándo activarse

Triggers típicos:
- "limpiá atlas"
- "buscá orphans en atlas"
- "atlas integrity check"
- "atlas health"
- "atlas cleanup"
- "qué atlas están huérfanos"
- "hacé un audit de atlas"

## Procedimiento

### 1. Invocar el script de scan

```bash
bash '${CLAUDE_PLUGIN_ROOT}/skills/atlas-cleanup/cleanup.sh' --scan
```

El script **SOLO escanea**, NO modifica nada. Devuelve por stdout un JSON con esta forma:

```json
{
  "success": true,
  "total_obs": 42,
  "total_pool": 35,
  "orphans": [...],
  "dangling": [...],
  "duplicates": [...],
  "malformed": [...]
}
```

Si `success: false`, parar y reportar el error tal cual al usuario (engram caído, etc.).

### 2. Parsear y mostrar reporte categorizado

Output esperado al usuario (rioplatense, directo):

```
🔍 Atlas Integrity Report
════════════════════════════════════════

📊 Total atlas obs en engram: <N>
📊 Total .md en atlas-pool/: <M>

⚠️ ORPHANS (en engram, raw borrado):
  - obs #1937 — Karpathy RNN — atlas/karpathy.github.io/rnn-effectiveness
    source_url: https://karpathy.github.io/...
    proyecto: dev
    Suggested action: borrar de engram (atlas delete #1937) O re-clipear el source

📥 DANGLING (raw en pool, sin inyectar):
  - atlas-pool/event-sourcing-fowler.md
    source_url: https://martinfowler.com/...
    title: Event Sourcing
    clipped: 2026-04-23
    Suggested action: inyectarlo (inyectá al proyecto X la info de <slug>) O borrarlo del pool

🔀 DUPLICATES (mismo source_url en >1 proyecto):
  - source_url: https://karpathy.github.io/...
    - obs #1937 (proyecto: dev, topic_key: atlas/karpathy.github.io/rnn-effectiveness)
    - obs #1955 (proyecto: personal, topic_key: atlas/karpathy.github.io/rnn-effectiveness)
    Suggested action: revisar si el duplicate cross-project es intencional o accidental

❌ MALFORMED (metadata incompleta o topic_key inválido):
  - obs #1934 — bridge-verify-test-cli — topic_key: bridge-verify-test-cli (NO empieza con atlas/)
    Suggested action: borrar (no es atlas real) O editar para fix topic_key
  - obs #1939 — Atlas Test Legacy — topic_key: atlas/test/legacy — NO tiene source_url
    Suggested action: editar y agregar source_url
════════════════════════════════════════
```

Si una categoría viene vacía: mostrar `(ninguno)` debajo del header en vez de omitir, así el usuario ve que se chequearon las 4.

### 3. Ofrecer remediación interactiva

```
¿Qué hacemos?
[1] Borrar todos los orphans de engram (N obs)
[2] Inyectar todos los dangling al proyecto X (M clips)
[3] Borrar todos los dangling del pool sin inyectar
[4] Revisar duplicates manualmente (uno por uno)
[5] Editar malformed para fix
[6] Salir sin hacer cambios
```

Esperar elección del usuario. Para cada opción:

| Opción | Acción | Skill a invocar |
|--------|--------|-----------------|
| 1 | Borrar orphans de engram (bulk) | `atlas-delete` con los IDs |
| 2 | Inyectar dangling al proyecto que indique el usuario | `inject-atlas` (uno por uno o batch) |
| 3 | Borrar `.md` del pool (sin tocar engram, porque ya no están inyectados) | bash `rm` directo, **PEDIR confirmación obligatoria primero** |
| 4 | Revisar duplicates uno por uno | mostrar cada par, preguntar si borrar uno, cuál, o ambos |
| 5 | Editar malformed | `atlas-edit` por cada ID |
| 6 | Salir | confirmar y no hacer nada |

**Este skill NUNCA ejecuta deletes ni updates por sí mismo, sólo coordina.** El único caso de modificación directa es la opción 3 (borrar `.md` del pool), y SOLO con confirmación explícita del usuario.

### 4. Si el usuario no quiere remediación

Solo reportar y salir. El skill es **read-only por default** — la fase de scan es siempre segura. Confirmar al usuario:

```
Listo, reporte generado. No toqué nada.
```

## Reglas duras

- **NUNCA** modificar `.md` de `atlas-pool/` sin confirmación explícita del usuario.
- **NUNCA** borrar obs de engram desde este skill — siempre delegar a `atlas-delete`.
- **NUNCA** editar obs desde este skill — siempre delegar a `atlas-edit`.
- **NUNCA** inyectar nuevos clips desde este skill — siempre delegar a `inject-atlas`.
- El default de toda confirmación es NO.
- Si engram está caído, parar y reportar — no inventar "todo limpio".
- El script `cleanup.sh` es idempotente: correrlo N veces produce el mismo output (modulo cambios externos).
- NO commitear nada.
- NO crear archivos auxiliares de reporte (la salida va al chat, no a un `.md`).

## Vault resolution

`cleanup.sh` resuelve el vault con la cascada de 5 niveles del helper compartido (ver `README.md > Vault Resolution` para el cuadro completo).

| Nivel | Fuente |
|-------|--------|
| L1    | `--vault <path>` flag pasado al script (`cleanup.sh --vault /home/u/notes --scan`) |
| L2    | env var `$ATLAS_VAULT` |
| L3    | env var `$VAULT_ROOT` (**deprecated** — emite warning una vez por sesión) |
| L4    | walk-up desde `$PWD` buscando `.obsidian/` (dir) o `.atlas-pool` (archivo) |
| L5    | fallback `$HOME/vault` |

Migración: si tenías `VAULT_ROOT` exportado, cambialo a `ATLAS_VAULT` y silenciás el warning.

## Convenciones del usuario

- Idioma: rioplatense voseo (vos, dale, listo, bien, fantástico)
- NO usar `cat`/`grep`/`find`/`ls` — usar `bat`/`rg`/`fd`/`eza`
- NO mencionar "Co-Authored-By" en nada
- Tono: directo, sin parrafadas. Decí lo que encontraste y listo.
