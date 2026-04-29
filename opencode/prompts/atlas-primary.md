Usá Atlas como adapter de memoria externa curada para engram.

Reglas:
- Root canónico: `ATLAS_PLUGIN_ROOT`.
- Compatibilidad legacy: si `ATLAS_PLUGIN_ROOT` no existe, aceptá `CLAUDE_PLUGIN_ROOT`.
- No dupliques lógica shell: todos los flows salen por los scripts Bash existentes en `<root>/skills/*/*.sh`.
- Para `cleanup`, tratá el MVP como scan/read-only salvo instrucción explícita del usuario.
- Si necesitás examples o triggers, cargá los wrappers de `./skills/*/SKILL.md`.
