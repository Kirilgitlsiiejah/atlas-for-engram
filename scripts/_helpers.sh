#!/bin/bash
# _atlas-shared/_helpers.sh — funciones compartidas del ecosistema atlas
# Sourceado por: cleanup.sh, lookup.sh, edit.sh, delete.sh, generate.sh, _doctor.sh
# Convención: zero side effects al sourcear, solo definiciones de funciones.
#
# Defensive style: NO `set -euo pipefail` (intentional). Errores se manejan con
# `2>/dev/null || true` y guards explícitos.

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

# resolve_plugin_root — canonical plugin root resolver for all adapters.
# Orden:
#   1. $ATLAS_PLUGIN_ROOT   (canónico, neutral a Claude/OpenCode)
#   2. $CLAUDE_PLUGIN_ROOT  (compatibilidad con installs legacy de Claude)
#   3. relativo al script caller (si se pasa $1)
#   4. relativo a este helper como fallback final
# Output: path al root del repo/plugin, sin newline trailing.
resolve_plugin_root() {
  local caller_path="${1:-}"
  local fallback_root=""

  if [[ -n "${ATLAS_PLUGIN_ROOT:-}" ]]; then
    fallback_root="$ATLAS_PLUGIN_ROOT"
  elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    fallback_root="$CLAUDE_PLUGIN_ROOT"
  elif [[ -n "$caller_path" ]]; then
    local caller_dir=""
    caller_dir=$(cd "$(dirname "$caller_path")" && pwd 2>/dev/null) || caller_dir=""
    if [[ -n "$caller_dir" ]]; then
      fallback_root=$(cd "$caller_dir/../.." && pwd 2>/dev/null) || fallback_root="$caller_dir/../.."
    fi
  fi

  if [[ -z "$fallback_root" ]]; then
    local helper_dir=""
    helper_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null) || helper_dir=""
    if [[ -n "$helper_dir" ]]; then
      fallback_root=$(cd "$helper_dir/.." && pwd 2>/dev/null) || fallback_root="$helper_dir/.."
    fi
  fi

  printf '%s' "$fallback_root"
}

# ─── Vault resolution (REQ-CASCADE-1/2, REQ-WIN-1/2/3, REQ-MARKER-1, REQ-DEPR-1) ──

# _atlas_normalize_path — convierte rutas Windows a forma Unix-style (Git Bash / MSYS2).
# Idempotente (re-aplicar el resultado no cambia el output).
# Ejemplos:
#   C:\foo\bar     → /c/foo/bar
#   C:/foo/bar     → /c/foo/bar
#   /c/foo/bar     → /c/foo/bar
#   C:\foo\bar\    → /c/foo/bar     (sin trailing slash)
#   /home/u/vault/ → /home/u/vault  (sin trailing slash)
#   ""             → ""
_atlas_normalize_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && { printf '%s' ""; return 0; }

  # 1. Convertir backslashes a forward slashes.
  p="${p//\\//}"

  # 2. Convertir prefijo de drive "X:/..." → "/x/..." (lowercase drive letter).
  #    Sólo si la cadena empieza con [A-Za-z]:/ (drive letter explícito + slash).
  #    Drive-relative paths como "D:foo" (sin slash) son ambiguos en Windows
  #    (drive-relative al cwd de ese drive) y NO se soportan deliberadamente —
  #    se dejan pasar tal cual y se tratan como un nombre con dos puntos.
  if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1],,}"  # lowercase
    local rest="${BASH_REMATCH[2]}"
    p="/${drive}/${rest}"
  fi

  # 3. Colapsar dobles slashes (excepto el prefijo UNC //host/share que dejamos como //).
  #    Estrategia: si empieza con //, preservamos los dos primeros chars y colapsamos el resto.
  if [[ "$p" =~ ^// ]]; then
    local head="//"
    local tail="${p:2}"
    # Colapsar // múltiples en el tail
    while [[ "$tail" == *"//"* ]]; do
      tail="${tail//\/\//\/}"
    done
    p="${head}${tail}"
  else
    while [[ "$p" == *"//"* ]]; do
      p="${p//\/\//\/}"
    done
  fi

  # 4. Quitar trailing slash si la cadena tiene >1 char y no es root drive (/c/, /).
  #    "/c/" → "/c" no es deseable (rompe drive root). "/c" tampoco es estándar.
  #    Por simplicidad: si len > 1 y termina en / Y no es exactamente "/X/" (drive root),
  #    quitamos el trailing slash. Drive root preservamos como "/c" (no "/c/").
  if [[ ${#p} -gt 1 && "$p" == */ ]]; then
    # Casos especiales a preservar tal cual:
    #   /        → /         (POSIX root, ya len=1, no entra acá)
    #   //host/  → //host    (UNC root sin share — quitamos /)
    p="${p%/}"
  fi

  printf '%s' "$p"
}

# _atlas_walk_up — busca hacia arriba desde $1 un directorio que tenga
#   `.obsidian/` (dir) o `.atlas-pool` (regular file). Si encuentra, imprime
#   el path absoluto del vault root. Si no, imprime cadena vacía.
#
# Termination guards (REQ-WIN-1):
#   - POSIX root           : /
#   - drive root (Windows) : ^/[a-z]$
#   - drive root literal   : ^[A-Za-z]:/?$
#   - UNC root             : ^//[^/]+/[^/]+$
#   - max iterations       : 64 (defensive infinite-loop guard)
#
# REQ-MARKER-1: `.atlas-pool` debe ser un ARCHIVO regular (no directorio).
# Si existe `.atlas-pool/` como directorio, NO matchea — el walk-up sigue.
_atlas_walk_up() {
  local dir
  dir=$(_atlas_normalize_path "${1:-$PWD}")
  [[ -z "$dir" ]] && { printf '%s' ""; return 0; }

  local i=0
  local max=64

  while [[ $i -lt $max ]]; do
    # Marker check: .obsidian/ (dir) OR .atlas-pool (regular file)
    if [[ -d "$dir/.obsidian" ]] || [[ -f "$dir/.atlas-pool" ]]; then
      printf '%s' "$dir"
      return 0
    fi

    # Termination check (POSIX root, drive root, UNC root)
    if [[ "$dir" == "/" ]]; then return 0; fi
    if [[ "$dir" =~ ^/[a-zA-Z]$ ]]; then return 0; fi
    if [[ "$dir" =~ ^[A-Za-z]:/?$ ]]; then return 0; fi
    if [[ "$dir" =~ ^//[^/]+/[^/]+$ ]]; then return 0; fi

    # Subir un nivel
    local parent
    parent=$(dirname "$dir" 2>/dev/null)
    # Si dirname devuelve lo mismo (ya en root) o cadena vacía, parar.
    if [[ -z "$parent" || "$parent" == "$dir" ]]; then
      return 0
    fi
    dir="$parent"
    i=$((i + 1))
  done

  # Max iterations: salir limpio (defensive)
  return 0
}

# _atlas_warn_legacy — emite warning una sola vez por sesión cuando $VAULT_ROOT
# está seteado. Idempotente. REQ-DEPR-1.
#
# Implementación: doble guard.
#   1. Sentinel in-process ($_ATLAS_VAULT_ROOT_WARNED) — cubre repeticiones en
#      el mismo proceso (cheap, sin syscalls).
#   2. Flag filesystem (DIRECTORY) en $TMPDIR — cubre subshells y procesos
#      hijos creados por command substitution `$()`. El export del sentinel
#      NO se propaga del child al parent, así que el flag es la única forma
#      robusta cross-process.
#
# Por qué directory + mkdir (no file + : >):
#   - mkdir es ATÓMICO (no race window entre check y write — quien gana, gana)
#   - mkdir NO sigue symlinks (file flag con `: >` los seguía y truncaba el
#     target — riesgo de symlink-attack en /tmp multi-usuario)
#   - directory es semánticamente "ya creado" o "no" — no hay estado parcial
#
# Por qué $PPID en el nombre:
#   - En Git Bash for Windows, /tmp mapea a %TEMP% que NUNCA se limpia por OS,
#     así que un flag sin scope persistiría para siempre y romper REQ-DEPR-1
#     ("una vez por sesión"). $PPID hace el flag per-shell-tree (cada terminal
#     o parent shell tiene su propio flag), que es el scope intuitivo.
#
# Username fallback chain ($USER → $USERNAME → $LOGNAME → anon):
#   - Git Bash for Windows NO setea $USER (usa $USERNAME). Sin fallback chain,
#     todos los usuarios Windows colapsarían a "anon" — colisión multi-usuario.
_atlas_warn_legacy() {
  # Guard in-process (mismo proceso, repeated calls).
  if [[ -n "${_ATLAS_VAULT_ROOT_WARNED:-}" ]]; then
    return 0
  fi
  # Guard cross-process via atomic directory flag (mkdir is atomic, won't
  # follow symlinks, won't truncate). Per-shell-tree via $PPID.
  local _flag_dir="${TMPDIR:-/tmp}/_atlas_vault_warned.${USER:-${USERNAME:-${LOGNAME:-anon}}}.${PPID:-0}"
  if mkdir "$_flag_dir" 2>/dev/null; then
    # We won the race — emit the warning.
    printf '%s\n' "warning: \$VAULT_ROOT is deprecated; use \$ATLAS_VAULT instead" >&2
  fi
  # Either we won and warned, or someone else won earlier — mark in-process either way.
  export _ATLAS_VAULT_ROOT_WARNED=1
  return 0
}

# detect_vault — resuelve el vault root usando una cascada de 5 niveles.
# Usage:
#   detect_vault [path_override]
#
# Cascada (primer match gana):
#   L1. $1 (path override explícito, ej. via --vault flag)        → "flag"
#   L2. $ATLAS_VAULT (env var canónica)                           → "env-canonical"
#   L3. $VAULT_ROOT  (env var legacy — emite deprecation warning) → "env-legacy"
#   L4. walk-up desde $PWD buscando .obsidian/ o .atlas-pool      → "marker"
#   L5. fallback $HOME/vault                                      → "fallback"
#
# Side effects:
#   - export ATLAS_VAULT_RESOLVED       (path resuelto)
#   - export ATLAS_VAULT_RESOLVED_LEVEL (1..5)
#
# Output (stdout): path resuelto, sin newline trailing (printf '%s').
# Nunca exit nonzero.
detect_vault() {
  local override="${1:-}"
  local resolved=""
  local level=""

  # L1: override explícito (--vault flag)
  if [[ -n "$override" ]]; then
    resolved=$(_atlas_normalize_path "$override")
    level=1
  # L2: $ATLAS_VAULT
  elif [[ -n "${ATLAS_VAULT:-}" ]]; then
    resolved=$(_atlas_normalize_path "$ATLAS_VAULT")
    level=2
  # L3: $VAULT_ROOT (legacy)
  elif [[ -n "${VAULT_ROOT:-}" ]]; then
    _atlas_warn_legacy
    resolved=$(_atlas_normalize_path "$VAULT_ROOT")
    level=3
  else
    # L4: walk-up desde cwd
    local found
    found=$(_atlas_walk_up "$PWD")
    if [[ -n "$found" ]]; then
      resolved="$found"
      level=4
    else
      # L5: fallback $HOME/vault
      resolved=$(_atlas_normalize_path "${HOME}/vault")
      level=5
    fi
  fi

  export ATLAS_VAULT_RESOLVED="$resolved"
  export ATLAS_VAULT_RESOLVED_LEVEL="$level"

  printf '%s' "$resolved"
}

# ─── engram_post_observation — canonical write primitive ─────────────────────
# Args:    $1 = payload_json (already-built JSON string)
# Stdout:  obs_id on success, empty on failure
# Exit:    0 success, 1 failure
# Notes:   POST /observations REQUIRES session_id, title, content (caller mints
#          session via POST /sessions BEFORE invoking — discovered P0.4 smoke).
# === BEGIN INLINE FALLBACK engram_post_observation ===
engram_post_observation() {
  local payload="${1:-}" host="${ENGRAM_HOST:-127.0.0.1:7437}" attempt=0 max=3
  [[ -z "$payload" ]] && return 1
  while [[ $attempt -lt $max ]]; do
    local raw http body
    raw=$(curl -sS -m 10 -w '\n%{http_code}' -X POST \
      -H 'Content-Type: application/json' -d "$payload" \
      "http://${host}/observations" 2>/dev/null) || { attempt=$((attempt+1)); sleep 0.2; continue; }
    http="${raw##*$'\n'}"; body="${raw%$'\n'*}"
    if [[ "$http" == "200" || "$http" == "201" ]]; then
      local obs_id
      obs_id=$(printf '%s' "$body" | jq -r '.id // empty' 2>/dev/null)
      [[ -n "$obs_id" && "$obs_id" != "null" ]] && { printf '%s' "$obs_id"; return 0; }
      return 1
    fi
    [[ "$http" =~ ^5 ]] || return 1
    attempt=$((attempt+1)); sleep "0.$((1+attempt*2))"
  done
  return 1
}
# === END INLINE FALLBACK engram_post_observation ===
