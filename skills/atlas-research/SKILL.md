---
name: atlas-research
description: Captura un research one-shot — escribís contenido + metadata, el script genera el .md en atlas-pool/ y lo inyecta a engram en una sola pasada. Usar cuando el usuario diga "investigá esto", "guardá este research", "metele este artículo al atlas", o variantes. Pool-first write order — si engram cae, el .md queda en disco para recovery via bulk-inject.
---

# atlas-research

One-shot capture-classify: vos le pasás contenido (+ source_url, title opcional), el script lo escribe a `${ATLAS_VAULT}/atlas-pool/<slug>.md` y lo POSTea a engram con `type=atlas`. Pool-first: si engram está caído, el `.md` queda en disco — recovery via `bulk-inject.sh`.

## Cuándo activarse

Activate ante triggers como:
- "investigá esto sobre **<tema>**"
- "guardá este research de **<tema>**"
- "metele al atlas este artículo de **<url>**"
- "agregá esto al atlas: **<contenido>**"

## Cómo invocar

`research.sh` lee JSON por stdin. Pipeá un heredoc:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/atlas-research/research.sh" <<'EOF'
{
  "title": "RNN Effectiveness",
  "source_url": "https://karpathy.github.io/2015/05/21/rnn-effectiveness/",
  "tags": ["rnn", "deep-learning"],
  "body": "# RNN Effectiveness\n\nKarpathy explica por qué...",
  "project": "dev"
}
EOF
```

**Required**: `body`, `project`. Si no pasás `title`, lo deriva (primer H1 del body → último segmento de la URL → falla).

## Output

Single-line JSON a stdout: `{success, wrote_pool, wrote_engram, pool_path, topic_key, obs_id, error?}`. Validá con `jq -e .`.

Exit codes:
- `0` — pool ok + engram ok
- `1` — pool ok, engram fail (`.md` preservado, retry con `bulk-inject.sh`)
- `2` — pool fail (no se contactó engram)

## Convenciones

- Voseo cuando hablás con el usuario.
- NO modificar el `.md` que ya está en pool — re-invocar regenera (idempotente vía topic_key upsert).
- Si engram cae, decile al user: "El .md quedó en pool, dale después a `bulk-inject.sh --project <p>` para sincronizar".
