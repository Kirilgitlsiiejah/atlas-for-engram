# Examples — atlas-for-engram

Tres walkthroughs end-to-end del workflow completo.

## Setup común

Antes de cualquier ejemplo:

1. Tenés engram instalado y corriendo: `engram serve` (default `127.0.0.1:7437`)
2. Tenés el plugin instalado: `claude plugin install Kirilgitlsiiejah/atlas-for-engram`
3. Tenés un vault Obsidian (o cualquier dir con `.atlas-pool` empty file marker)

## Ejemplo 1: Clipear web → inject → search

**Caso**: leíste un blog post sobre Hexagonal Architecture y querés agregarlo a tu knowledge base.

### Paso 1 — Clipear

Instalá el [Obsidian Web Clipper](https://obsidian.md/clipper) y configurá template para escribir a `<vault>/atlas-pool/`. Ejemplo de output:

```markdown
---
source_url: https://blog.example.com/hexagonal
title: Hexagonal Architecture explained
clipped_at: 2026-04-25
domain: architecture
---

# Hexagonal Architecture

The pattern proposes that the application should be organized around the domain ...
```

### Paso 2 — Inject

En Claude Code:

```
inyectá al proyecto dev la info de hexagonal-architecture
```

El skill `inject-atlas` lee el `.md`, parsea frontmatter y lo inyecta a engram como `type=atlas` usando `source_url` como campo canónico.

Compatibilidad: si el clip viejo del Web Clipper trae `source:` en vez de `source_url:`, Atlas lo sigue leyendo igual. `source_url` queda como nombre canónico de escritura; `source` vive solo como fallback de lectura.

### Paso 3 — Search

Después en cualquier sesión:

```
qué sé sobre hexagonal architecture?
```

Claude llama `mem_search type=atlas`, encuentra tu clip, te muestra `source_url` + content. Si tenés el hook `compare-with-atlas` activado (viene por default), vas a ver split: tu propio trabajo vs el clip externo.

## Ejemplo 2: Multi-vault setup

**Caso**: tenés vault personal `~/vault-personal` y vault de trabajo `~/work/vault-laburo`. Querés que atlas detecte cuál usar según donde estés parado.

### Setup

Cero config necesaria — el cascade L4 walk-up lo resuelve solo siempre que cada vault tenga `.obsidian/` (directorio) o `.atlas-pool` (archivo regular) marker.

### Uso

```bash
cd ~/vault-personal
atlas-cleanup --scan
# → resuelve vault: /home/u/vault-personal (L4 walk-up .obsidian)

cd ~/work/vault-laburo
atlas-lookup "react hooks"
# → resuelve vault: /home/u/work/vault-laburo (L4 walk-up .obsidian)
```

### Override explícito

Si querés usar el vault personal mientras estás parado en otro lugar:

```bash
ATLAS_VAULT=~/vault-personal atlas-lookup "react hooks"
# → resuelve vault: /home/u/vault-personal (L2 env override)
```

O por flag CLI:

```bash
atlas-lookup --vault=~/vault-personal "react hooks"
# → resuelve vault: /home/u/vault-personal (L1 flag, top priority)
```

### Doctor para verificar

```bash
bash ~/.claude/plugins/atlas-for-engram/scripts/_doctor.sh
# additionalContext incluye: vault: L<n> (<label>) -> <path>
```

Levels posibles:

- `L1 (flag)` — `--vault` o `--vault=` explícito
- `L2 (env)` — `$ATLAS_VAULT` setado
- `L3 (env-legacy)` — `$VAULT_ROOT` setado (deprecation warning emitido)
- `L4 (marker)` — walk-up encontró `.obsidian/` o `.atlas-pool`
- `L5 (default)` — fallback a `$HOME/vault` (warning si no existe)

## Ejemplo 3: Debug — atlas no encuentra mis clips

**Caso**: clipeaste varios posts pero `mem_search type=atlas` no encuentra nada.

### Paso 1 — Doctor

```bash
bash ~/.claude/plugins/atlas-for-engram/scripts/_doctor.sh | jq .
```

Mirá `additionalContext`. Casos típicos:

- **`vault: L5 (default) -> /home/u/vault`** + warning `vault path doesn't exist` → estás cayendo a fallback. Setea `ATLAS_VAULT` o `cd` al vault correcto
- **`atlas-pool not found at <path>/atlas-pool`** → el vault existe pero falta el pool. Corré: `mkdir <path>/atlas-pool && touch <path>/atlas-pool/.gitkeep`

### Paso 2 — Verificá engram

```bash
curl -s http://127.0.0.1:7437/health
# {"service":"engram","status":"ok","version":"0.1.0"}
```

Si engram no está corriendo, los inject silenciosos fallan.

### Paso 3 — Atlas lookup directo

```bash
atlas-lookup --vault=<your-vault> https://blog.example.com/hexagonal
```

Te dice si el clip está: (a) en engram inyectado, (b) en `atlas-pool/` sin inyectar, (c) ambos, (d) ninguno.

### Paso 4 — Inject manual

Si tenés clips en `atlas-pool/` sin inyectar (caso b), corré `inject-atlas` o decile a Claude:

```
inyectá todos los clips de atlas-pool al proyecto dev
```

### Paso 5 — Index navegable

```
generá el atlas index del proyecto dev
```

`atlas-index` produce `<vault>/Atlas-Index.md` con todos los atlas observations agrupados por `source_domain`. Útil para review periódico.

## Recursos

- **README**: overview general (`<repo-root>/README.md`)
- **CONTRIBUTING**: si querés contribuir o entender las conventions (`<repo-root>/CONTRIBUTING.md`)
- **CHANGELOG**: qué cambió en cada release (`<repo-root>/CHANGELOG.md`)
- **engram MCP server**: https://github.com/Gentleman-Programming/engram
