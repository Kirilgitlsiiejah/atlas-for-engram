# Manual smoke — OpenCode adapter

## Objetivo

Validar que el adapter OpenCode use el mismo core Bash que Claude sin build step ni bump de versión.

## Preflight

```bash
export ATLAS_PLUGIN_ROOT="/path/to/atlas-for-engram"
export OPENCODE_CONFIG="${ATLAS_PLUGIN_ROOT}/opencode/opencode.json"
export OPENCODE_CONFIG_DIR="${ATLAS_PLUGIN_ROOT}/opencode"
```

Notas para Windows/WSL:

- Si este checkout quedó con CRLF, el `bash -n` local puede dar falsos negativos con `$'\r'`. En ese caso validá desde Git for Windows Bash o sobre contenido normalizado a LF.
- Estos smokes llaman `jq` desde Bash. Si sólo lo tenés disponible como `jq.exe` en PowerShell, WSL/Git Bash puede no verlo. Confirmá `command -v jq` en la shell donde vas a correr el smoke.

Compatibilidad legacy:

```bash
unset ATLAS_PLUGIN_ROOT
export CLAUDE_PLUGIN_ROOT="/path/to/atlas-for-engram"
```

## Smoke steps

### 1. Root resolution canónica

- Con `ATLAS_PLUGIN_ROOT` y `CLAUDE_PLUGIN_ROOT` seteados, el root efectivo TIENE que ser `ATLAS_PLUGIN_ROOT`.
- Con `ATLAS_PLUGIN_ROOT` unset y `CLAUDE_PLUGIN_ROOT` seteado, Claude compatibility TIENE que seguir andando.
- Check rápido:

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts/session-start.sh"
```

### 2. Inject dry-run

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/inject-atlas/bulk-inject.sh" \
  --project dev --dry-run
```

Esperado: JSON válido y sin writes a engram.

### 3. Lookup

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-lookup/lookup.sh" "atlas"
```

Esperado: JSON válido con `scenario` y arrays consistentes.

### 4. Cleanup scan/stub

```bash
bash "${ATLAS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/atlas-cleanup/cleanup.sh" --scan
```

Esperado: JSON válido. En MVP OpenCode esto cubre el caso soportado; la remediación sigue manual/coordinada.

### 5. Claude compatibility smoke

- Dejando sólo `CLAUDE_PLUGIN_ROOT`, corré otra vez:
  - `scripts/session-start.sh`
  - `skills/inject-atlas/bulk-inject.sh --project dev --dry-run`
- Esperado: mismos entrypoints, mismo core, sin path rotos.

## Validaciones estáticas recomendadas

```bash
jq -e . .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json opencode/opencode.json opencode/manifest.json
v_file=$(< VERSION)
v_claude=$(jq -r .version .claude-plugin/plugin.json)
v_market=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
v_open=$(jq -r .version opencode/manifest.json)
[[ "$v_file" == "$v_claude" && "$v_file" == "$v_market" && "$v_file" == "$v_open" ]]
git ls-files '*.sh' | xargs -r -n1 bash -n
```

## Limitaciones del MVP

- No hay hook parity automática con Claude `PostToolUse`.
- No hay build step ni release bump en este smoke.
