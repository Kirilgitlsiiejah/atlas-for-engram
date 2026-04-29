---
name: inject-atlas
description: >
  Inyecta clips ya presentes en atlas-pool a engram usando el core Bash compartido.
  Trigger: cuando el usuario pida inyectar, agregar o sincronizar clips al proyecto.
license: MIT
metadata:
  author: Kirilgitlsiiejah
  version: "0.3.1"
allowed-tools: Bash
---

## Command

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/inject-atlas/bulk-inject.sh" \
  --project <name> [--vault <path>] [--dry-run] [--parallelism N]
```

## Notes

- `ATLAS_PLUGIN_ROOT` manda; `CLAUDE_PLUGIN_ROOT` queda de fallback.
- Reusá el script Bash existente. NO reimplementes inject en el prompt.
