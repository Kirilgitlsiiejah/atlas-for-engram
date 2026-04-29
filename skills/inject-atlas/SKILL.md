---
name: inject-atlas
description: Inyecta clips ya presentes en ${ATLAS_VAULT}/atlas-pool/ a engram, en bulk y paralelo. Usar cuando el usuario diga "inyectá al proyecto X la info de Y", "agregá a engram", "inject Y to project X", "metele al engram", o variantes. Bajo el capó shell-out a bulk-inject.sh — todos los .md del pool se procesan, idempotente vía topic_key upsert.
---

# inject-atlas

Wrapper sobre `bulk-inject.sh`. Sweep paralelo de los clips `.md` de primer nivel en `${ATLAS_VAULT}/atlas-pool/` → engram, idempotente.

## Cuándo activarse

Activate cuando el usuario pida ingestar el pool — frases como:
- "inyectá al proyecto **dev** la info de **Karpathy sobre RNN**"
- "agregá a engram del proyecto **vault** ese clip de **martinfowler**"
- "inject **event-sourcing.md** to project **backend**"
- "metele al engram de **X** lo de **Y**"

Si el usuario no especifica proyecto, auto-detect via `git remote` → `git root basename` → `basename "$PWD"` → `"dev"` y confirmá antes de inyectar.

## Cómo invocar

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/inject-atlas/bulk-inject.sh" \
  --project <name> [--vault <path>] [--dry-run] [--parallelism N]
```

Flags:
- `--project <name>` (req)
- `--vault <path>` (override cascade)
- `--dry-run` — preview sin POST
- `--parallelism N` (default 4, max 8)

Output: single-line JSON `{success, project, vault, total, succeeded, failed, files:[...], elapsed_ms}`. Compatibilidad de lectura: si el markdown trae `source:` sin `source_url:`, el script usa igual esa URL para dominio/topic_key. Reportá al user en voseo: "Listo, inyecté N clips al proyecto X (M failed)".

## Modo legacy LLM-driven (DEPRECATED)

El procedimiento prompt-driven anterior (parsear .md uno por uno desde el contexto, calcular sha256 manualmente, prompt-only dedup en 3 capas) está deprecado. Va a removerse en el próximo minor. Si necesitás la versión vieja por algún caso edge: `git log -- skills/inject-atlas/SKILL.md` y agarrá la versión previa al refactor `feat/atlas-ai-first-fast-inject`.

## Convenciones

- Voseo en mensajes al user.
- NO borrar el `.md` original — la inyección es no-destructiva.
- Si `bulk-inject.sh` exit non-zero, mostrale el JSON de errores al user, no reintentes silencioso.
