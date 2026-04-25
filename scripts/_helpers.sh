#!/bin/bash
# _atlas-shared/_helpers.sh — funciones compartidas del ecosistema atlas
# Sourceado por: cleanup.sh, lookup.sh, edit.sh, delete.sh, generate.sh
# Convención: zero side effects al sourcear, solo definiciones de funciones.

# detect_project — resuelve el project actual usando el mismo orden que engram _helpers.sh
# Orden:
#   1. git remote origin URL → último segmento sin .git
#   2. git root basename
#   3. cwd basename
#   4. fallback "dev"
# Output: nombre del proyecto a stdout, sin newline trailing.
detect_project() {
  local proj=""

  # 1. git remote origin
  if command -v git >/dev/null 2>&1; then
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || true)
    if [[ -n "$remote_url" ]]; then
      # Extraer último segmento del URL (post / o :), sin .git
      proj=$(printf '%s\n' "$remote_url" | awk -F'[/:]' '{print $NF}' | awk -F'.git$' '{print $1}')
    fi

    # 2. git root basename si remote falló
    if [[ -z "$proj" ]]; then
      local git_root
      git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
      [[ -n "$git_root" ]] && proj=$(basename "$git_root")
    fi
  fi

  # 3. cwd basename si git no disponible o no estamos en repo
  [[ -z "$proj" ]] && proj=$(basename "$PWD" 2>/dev/null)

  # 4. fallback final
  [[ -z "$proj" ]] && proj="dev"

  printf '%s' "$proj"
}

# resolve_project — wrapper: si $1 está seteado, usalo; sino auto-detect
# Permite a los scripts hacer: PROJECT=$(resolve_project "$1")
resolve_project() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
  else
    detect_project
  fi
}
