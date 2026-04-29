---
name: atlas-delete
description: >
  Previsualiza o elimina observaciones atlas usando el core Bash compartido.
  Trigger: cuando el usuario pida borrar un atlas o revisar candidatos antes de borrarlos.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Commands

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-delete/delete.sh" --preview <filter_args>
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-delete/delete.sh" --execute <id1> <id2> ... [--with-raw]
```

## Notes

- Confirmá deletes destructivos antes de ejecutar.
- Para cleanup MVP, usalo sólo cuando el usuario pida remediación explícita.
