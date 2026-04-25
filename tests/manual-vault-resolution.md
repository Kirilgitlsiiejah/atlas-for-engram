# Manual smoke runbook — vault resolution cascade

Cubre los 5 niveles de la cascada `detect_vault` + el walk-up con cada marker
(`.obsidian/` y `.atlas-pool`). Pensado para ejecutarse a mano antes de
mergear cambios al helper `_helpers.sh` o a sus consumers.

> Setup: cada escenario crea sus fixtures temporales en `/tmp/atlas-smoke/`
> y los limpia al final. Asume Git Bash en Windows o bash en macOS/Linux.

```bash
# Helper de runbook — re-cargá el helper desde fuente y limpiá sentinels.
reload() {
  unset ATLAS_VAULT VAULT_ROOT \
        _ATLAS_VAULT_ROOT_WARNED \
        ATLAS_VAULT_RESOLVED ATLAS_VAULT_RESOLVED_LEVEL
  source "$(git rev-parse --show-toplevel)/scripts/_helpers.sh"
}

# Limpia fixtures (correr al inicio y al final).
clean_fixtures() {
  rm -rf /tmp/atlas-smoke 2>/dev/null
}

clean_fixtures
mkdir -p /tmp/atlas-smoke
```

---

## Escenario 1 — L1 override (`--vault` flag) gana sobre todo

**Setup**
```bash
clean_fixtures
mkdir -p /tmp/atlas-smoke/by-flag /tmp/atlas-smoke/by-env
reload
export ATLAS_VAULT=/tmp/atlas-smoke/by-env  # esto NO debería ganar
```

**Comando**
```bash
detect_vault /tmp/atlas-smoke/by-flag
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL"
```

**Expected**
```
/tmp/atlas-smoke/by-flag
level=1
```

**Resultado** — [PASS]

---

## Escenario 2 — L2 `$ATLAS_VAULT` gana sobre legacy y walk-up

**Setup**
```bash
clean_fixtures
mkdir -p /tmp/atlas-smoke/canonical /tmp/atlas-smoke/legacy
reload
export ATLAS_VAULT=/tmp/atlas-smoke/canonical
export VAULT_ROOT=/tmp/atlas-smoke/legacy   # NO debería ganar ni emitir warning
```

**Comando**
```bash
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL"
echo "warned=${_ATLAS_VAULT_ROOT_WARNED:-no}"
```

**Expected**
```
/tmp/atlas-smoke/canonical
level=2
warned=no
```

**Resultado** — [PASS]

---

## Escenario 3 — L3 `$VAULT_ROOT` legacy emite deprecation warning UNA sola vez

**Setup**
```bash
clean_fixtures
mkdir -p /tmp/atlas-smoke/legacy
reload
export VAULT_ROOT=/tmp/atlas-smoke/legacy
```

**Comando**
```bash
echo "--- first call ---"
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL"
echo "--- second call (no warning expected) ---"
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL"
```

**Expected** (la línea de warning aparece UNA SOLA VEZ a stderr)
```
--- first call ---
warning: $VAULT_ROOT is deprecated; use $ATLAS_VAULT instead
/tmp/atlas-smoke/legacy
level=3
--- second call (no warning expected) ---
/tmp/atlas-smoke/legacy
level=3
```

**Resultado** — [PASS]

---

## Escenario 4 — L4 walk-up encuentra `.obsidian/` (directorio)

**Setup**
```bash
clean_fixtures
mkdir -p /tmp/atlas-smoke/proj/.obsidian
mkdir -p /tmp/atlas-smoke/proj/sub/deeper
reload
unset ATLAS_VAULT VAULT_ROOT
cd /tmp/atlas-smoke/proj/sub/deeper
```

**Comando**
```bash
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL"
```

**Expected**
```
/tmp/atlas-smoke/proj
level=4
```

**Resultado** — [PASS]

---

## Escenario 5 — L4 walk-up encuentra `.atlas-pool` archivo (NO directorio)

**Setup**
```bash
clean_fixtures
mkdir -p /tmp/atlas-smoke/file-marker/sub
touch /tmp/atlas-smoke/file-marker/.atlas-pool   # ARCHIVO regular vacío
mkdir -p /tmp/atlas-smoke/dir-marker/sub
mkdir -p /tmp/atlas-smoke/dir-marker/.atlas-pool # DIRECTORIO — debe ser IGNORADO
reload
unset ATLAS_VAULT VAULT_ROOT
```

**Comando** (caso archivo: matchea)
```bash
cd /tmp/atlas-smoke/file-marker/sub
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL  (file marker — debería ser L4)"
```

**Comando** (caso directorio: NO matchea, walk-up sigue subiendo y termina en L5)
```bash
cd /tmp/atlas-smoke/dir-marker/sub
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL  (dir marker — debería ser L5 fallback)"
```

**Expected**
```
/tmp/atlas-smoke/file-marker
level=4  (file marker — debería ser L4)
<HOME>/vault
level=5  (dir marker — debería ser L5 fallback)
```

**Resultado** — [PASS]

---

## Escenario 6 — L5 fallback `$HOME/vault` cuando todo lo anterior falla

**Setup**
```bash
clean_fixtures
reload
unset ATLAS_VAULT VAULT_ROOT
cd /tmp                # sin marker en ningún ancestor
```

**Comando**
```bash
detect_vault
echo "level=$ATLAS_VAULT_RESOLVED_LEVEL"
```

**Expected**
```
<HOME>/vault   (ej. /c/Users/David/vault o /home/u/vault)
level=5
```

**Resultado** — [PASS]

---

## Cleanup

```bash
clean_fixtures
unset ATLAS_VAULT VAULT_ROOT _ATLAS_VAULT_ROOT_WARNED \
      ATLAS_VAULT_RESOLVED ATLAS_VAULT_RESOLVED_LEVEL
```

---

## Resumen de ejecución

| Escenario | Resultado |
|-----------|-----------|
| 1 — L1 flag override                              | [PASS] |
| 2 — L2 `$ATLAS_VAULT` precedence                  | [PASS] |
| 3 — L3 `$VAULT_ROOT` legacy warning una vez       | [PASS] |
| 4 — L4 walk-up con `.obsidian/`                   | [PASS] |
| 5 — L4 con `.atlas-pool` (archivo) + dir ignorado | [PASS] |
| 6 — L5 fallback `$HOME/vault`                     | [PASS] |

> Si cualquier escenario falla: revertir el cambio que rompió el escenario y
> abrir issue con el output completo. NO mergear con runbook en rojo.
