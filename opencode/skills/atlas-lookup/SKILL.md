---
name: atlas-lookup
description: >
  Busca si una URL o keyword ya existe en engram atlas o atlas-pool usando el core Bash compartido.
  Trigger: cuando el usuario pregunte si ya tiene algo guardado o clipeado.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Command

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-lookup/lookup.sh" "<url-o-substring>"
```

## Notes

- Es read-only.
- Si el script devuelve `success: false`, reportalo tal cual.
