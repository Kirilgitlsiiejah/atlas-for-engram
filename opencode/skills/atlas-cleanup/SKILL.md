---
name: atlas-cleanup
description: >
  Corre un integrity scan read-only sobre atlas usando el core Bash compartido.
  Trigger: cuando el usuario pida cleanup, audit, health o integrity check.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Command

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-cleanup/cleanup.sh" --scan
```

## Notes

- En MVP OpenCode, cleanup queda documentado como scan/read-only.
- Si el usuario quiere remediar, coordiná con `atlas-delete`, `atlas-edit` o `inject-atlas`.
