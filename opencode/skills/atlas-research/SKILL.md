---
name: atlas-research
description: >
  Captura research one-shot, escribe el .md al pool y lo inyecta a engram con el core Bash compartido.
  Trigger: cuando el usuario pida investigar, guardar o meter un artículo nuevo al atlas.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Command

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-research/research.sh" <<'EOF'
{
  "title": "<optional>",
  "source_url": "<optional>",
  "tags": ["optional"],
  "body": "<required>",
  "project": "<required>"
}
EOF
```

## Notes

- Pool-first: si engram falla, el `.md` queda en disco para recovery.
- NO dupliques la lógica de topic_key, slug o POST.
