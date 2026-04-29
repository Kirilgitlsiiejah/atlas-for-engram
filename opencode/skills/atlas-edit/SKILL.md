---
name: atlas-edit
description: >
  Edita una observación atlas existente en engram usando el core Bash compartido.
  Trigger: cuando el usuario pida corregir metadata o contenido de un atlas ya inyectado.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Command

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-edit/edit.sh" <obs_id> <project> <field=value> [<field=value> ...]
```

## Notes

- Reusá el script Bash existente.
- Si cambia el contenido visible, sugerí regenerar el index si aplica.
