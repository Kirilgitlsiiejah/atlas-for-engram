---
name: compare-with-atlas
description: >-
  Modo EXPLÍCITO solamente. El hook PostToolUse en settings.json cubre el modo
  automático silencioso post-mem_search. Este skill se invoca cuando el usuario
  pide explícitamente comparar con atlas: "compará con atlas", "qué dice atlas
  sobre X", "buscá en atlas también". Separa los resultados de mem_search en
  own_work (decisiones/patrones/discoveries propios) vs engram_atlas (clips ya
  inyectados como type=atlas), con silencio inteligente — omite secciones vacías.
---

# compare-with-atlas

Skill de retrieval comparativo en modo EXPLÍCITO. Separa los resultados de `mem_search` por `type` para mostrar con provenance claro qué viene de tu trabajo propio vs qué viene de clips atlas ya inyectados a engram.

> **Importante**: el modo automático silencioso lo cubre el hook `PostToolUse` configurado en `~/.claude/settings.json` (`compare-with-atlas/hook.sh`). Este skill es para invocación EXPLÍCITA por parte del usuario. NO leas `${ATLAS_VAULT:-$HOME/vault}/atlas-pool/` — esa carpeta contiene clips RAW no inyectados que no deben aparecer en búsquedas de retrieval.

## Filosofía

NO se trata de elegir una fuente sobre otra. Se trata de mostrar al usuario, con provenance claro, qué sabe cada lado dentro de engram:

- "Esto sé desde mis notas propias en engram" → trabajo del usuario (decisiones, patrones, bugfixes, etc.)
- "Esto está en clips que ya inyecté como atlas en engram" → atlas inyectado (type=atlas)
- "⚠️ Sobre tema X hay diferencias entre lo que dice tu trabajo y lo que dice un clip atlas" → discrepancia

El skill hermano `inject-atlas` es lo que el usuario invoca para mover un clip de `atlas-pool/` a engram como `type=atlas`. Una vez inyectado, aparece en `mem_search` y por lo tanto acá.

---

## How to invoke

Triggers explícitos del usuario:

- "compará con atlas"
- "qué dice atlas sobre X"
- "buscá en atlas también"
- "buscá también en atlas"
- "compará lo mío con atlas"

En modo explícito, este skill se invoca DIRECTAMENTE — el usuario lo está pidiendo. No depende del hook automático.

> **Modo automático**: el hook `PostToolUse` en `settings.json` se dispara después de cada `mcp__plugin_engram_engram__mem_search` y emite la separación own_work vs engram_atlas como `additionalContext`. El usuario no necesita hacer nada para activarlo: ya está configurado.

---

## Algoritmo (modo explícito)

### Paso 1 — Capturar keywords

Tomar la query textual del usuario. Si el usuario dijo "qué dice atlas sobre hexagonal", la query es `hexagonal architecture` (o similar — usá criterio).

### Paso 2 — Consulta engram

`mem_search` con la query, sin filtro por type.

### Paso 3 — Separar por type

Recorrer los resultados y clasificarlos:

- **own_work**: `type ∈ {decision, architecture, pattern, discovery, learning, bugfix, config, manual, preference}`
- **engram_atlas**: `type = atlas`

Cualquier otro `type` desconocido → tratarlo como `own_work` por default.

### Paso 4 — Detectar discrepancias

Si hay resultados en AMBAS categorías sobre el MISMO subtema (mirando títulos y snippets), y dicen cosas distintas → marcar como discrepancia. Ejemplo: una observación own_work dice "usar puertos/adaptadores con un solo adapter HTTP", y una observación atlas dice "cada port puede tener N adapters". Eso es una discrepancia que vale la pena flaggear.

### Paso 5 — Sintetizar output (silencio inteligente)

Formato de salida:

```markdown
**From engram (your work):**
- [obs ID] <title> — <snippet> (type: <type>, project: <project>)
- ...

**From engram atlas (already injected):**
- [obs ID] <title> — <source_url si está> — <snippet>
- ...

**⚠️ Discrepancies detected:**
- Sobre <tema>:
  - tu trabajo dice: <resumen>
  - atlas (<source>) dice: <resumen>
- ...
```

### REGLAS DE SILENCIO INTELIGENTE (críticas)

| Caso | Comportamiento |
|------|----------------|
| Una sección está vacía | OMITIRLA completamente. NO mostrar header con "(none)" ni "no results" |
| Las dos secciones están vacías | Mostrar SOLO: `Sin resultados en engram para \`<query>\`.` |
| Solo "From engram (your work)" tiene resultados | Comportarse como `mem_search` normal. NO mencionar atlas. Cero ruido. |
| Solo "From engram atlas" tiene resultados | Mostrar solo esa sección |
| Hay discrepancias detectadas | SIEMPRE mostrar la sección ⚠️, aunque sea la única |

El objetivo: cuando atlas no aporta nada nuevo, el usuario no debe notar que el skill corrió. Cuando atlas sí aporta, la información llega ordenada por fuente.

---

## Vault resolution

Este skill **no tiene flag `--vault`** — sus dos modos (skill explícito y hook PostToolUse) consumen `mem_search` y nunca leen el `atlas-pool/`. La referencia a `${ATLAS_VAULT:-$HOME/vault}/atlas-pool/` arriba es solo recordatorio de que ese directorio NO debe leerse desde acá.

Si necesitás resolver el vault desde otro contexto, ver `README.md > Vault Resolution` (cascada L1-L5).

Migración: pasá `VAULT_ROOT` → `ATLAS_VAULT` para silenciar el warning de deprecación.

## Convenciones del usuario que respetar

- **Idioma**: rioplatense voseo. "Decí", "buscá", "compará", "qué pensás", "dale".
- **Herramientas**: NO usar `cat`/`grep`/`find`. Usar `bat`/`rg`/`fd`/`eza`. Si falta alguna, instalar con `brew`.
- **Tono**: directo, sin parrafadas, con criterio. Cero relleno.
- **Commits**: NO incluir "Co-Authored-By" ni atribución a IA.

---

## Ejemplos

### Ejemplo A — usuario tiene notas propias y atlas no aporta

Usuario: "compará con atlas qué tengo sobre hexagonal"

Output:

```
- [123] Decisión: usar puertos/adaptadores en módulo auth (type: decision, project: dev)
- [145] Pattern: tests de hexagonal con doubles en el borde (type: pattern, project: dev)
```

(no menciona atlas para nada — sección vacía, omitida)

### Ejemplo B — atlas inyectado tiene info relevante, propio no

Usuario: "qué dice atlas sobre event sourcing"

Output:

```
**From engram atlas (already injected):**
- [201] Martin Fowler: Event Sourcing — https://martinfowler.com/eaaDev/EventSourcing.html — patrón para persistir cambios como eventos inmutables
- [203] Greg Young: CQRS + ES talk — https://youtu.be/... — separación de read/write models
```

### Ejemplo C — discrepancia detectada

Usuario: "compará con atlas hexagonal"

Output:

```
**From engram (your work):**
- [89] Pattern: hexagonal con un solo adapter HTTP (type: pattern)

**From engram atlas (already injected):**
- [201] Alistair Cockburn: Hexagonal Architecture — https://alistair.cockburn.us/hexagonal-architecture/

**⚠️ Discrepancies detected:**
- Sobre número de adapters:
  - tu trabajo dice: usar un solo adapter HTTP por agregado
  - atlas (Alistair Cockburn) dice: cada port puede tener N adapters de entrada y M de salida
```
