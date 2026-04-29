# Manual smoke runbook — atlas source URL fallback

Valida el contrato de compatibilidad de `atlas-source-url-fallback` sin build ni
runner formal: `source_url` gana sobre `source`, `source` sigue siendo fallback,
y un clip sin URL sigue sin URL.

**Fixtures**: `tests/fixtures/atlas-source-url-fallback/vault/atlas-pool/`

**Última ejecución verde**: 2026-04-29

> Setup: corré estos comandos con Git Bash en Windows (o bash POSIX) desde la
> raíz del repo. Los asserts usan `jq -e`.

```bash
VAULT="$(pwd)/tests/fixtures/atlas-source-url-fallback/vault"
```

---

## 1. Sintaxis shell de scripts tocados

```bash
bash -n skills/inject-atlas/bulk-inject.sh
bash -n skills/atlas-lookup/lookup.sh
bash -n skills/atlas-cleanup/cleanup.sh
```

**Expected**: sin output y exit 0.

---

## 2. `bulk-inject` respeta fallback y precedencia canónica

```bash
bash skills/inject-atlas/bulk-inject.sh --dry-run --project atlas-smoke --vault "$VAULT" \
  | jq -e '
      .total == 3 and
      ([.files[] | select(.path | endswith("source-only.md"))][0].topic_key == "atlas/example.com/source-only-clip") and
      ([.files[] | select(.path | endswith("conflict.md"))][0].topic_key == "atlas/canonical.example/conflict-clip")
    '
```

**Expected**: `true`

---

## 3. `lookup` usa `source` como fallback legado

```bash
bash skills/atlas-lookup/lookup.sh --vault "$VAULT" "Source Only Clip" | jq -e '
  .success == true and
  .scenario == "pool_only" and
  .pool_matches[0].source_url == "https://example.com/post"
'
```

**Expected**: `true`

---

## 4. `lookup` prioriza `source_url` aunque `source` aparezca primero

```bash
bash skills/atlas-lookup/lookup.sh --vault "$VAULT" conflict | jq -e '
  .success == true and
  .pool_matches[0].source_url == "https://canonical.example/new"
'
```

**Expected**: `true`

---

## 5. Sin URL, sigue sin URL

```bash
bash skills/atlas-lookup/lookup.sh --vault "$VAULT" "No URL Clip" | jq -e '
  .success == true and
  .pool_matches[0].source_url == ""
'
```

**Expected**: `true`

---

## Nota sobre `cleanup`

`cleanup.sh` comparte la misma resolución canónica en pool (`source_url` primero,
después `source`). La validación runtime completa requiere un Engram accesible;
cuando esté disponible, corré `cleanup.sh --scan` contra estas fixtures con un
stub o entorno controlado para cubrir dangling/orphans end-to-end.
