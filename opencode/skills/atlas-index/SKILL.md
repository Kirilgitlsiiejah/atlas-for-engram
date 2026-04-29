---
name: atlas-index
description: >
  Regenera Atlas-Index.md desde engram usando el core Bash compartido.
  Trigger: cuando el usuario pida ver, refrescar o reconstruir el atlas index.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Command

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-index/generate.sh" <project>
```

## Notes

- El index se genera desde engram, no desde una implementación paralela.
