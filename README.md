# atlas-for-engram

Memoria infinita para Claude que vive en tu Obsidian.

<p>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/actions/workflows/ci.yml"><img src="https://github.com/Kirilgitlsiiejah/atlas-for-engram/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases"><img src="https://img.shields.io/github/v/release/Kirilgitlsiiejah/atlas-for-engram" alt="Release"></a>
<a href="https://github.com/Kirilgitlsiiejah/atlas-for-engram/stargazers"><img src="https://img.shields.io/github/stars/Kirilgitlsiiejah/atlas-for-engram?style=flat&logo=github&color=yellow" alt="GitHub stars"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
</p>

## ¿Qué hace?

Claude se olvida todo entre sesiones. Cada vez le re-explicás el mismo artículo, el mismo paper, el mismo snippet que leíste la semana pasada. Es agotador.

Atlas conecta tu Obsidian con la memoria persistente de Claude. Vos clipeás un artículo desde el browser → se guarda en tu vault de Obsidian → Claude lo recuerda para siempre y lo cita cuando le preguntás algo relacionado.

## Instalación

### 1. Instalá el plugin

En Claude Code:

```
/plugin install atlas@github:Kirilgitlsiiejah/atlas-for-engram
```

### 2. Descargá el clipper para tu browser

Pre-buildeado, listo para `Load unpacked`:

- **Chrome / Edge / Brave** → [atlas-clipper-chrome.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-chrome.zip)
- **Firefox** → [zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-firefox.zip)
- **Safari** → [zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-safari.zip)

Descomprimí, andá a `chrome://extensions`, prendé Developer Mode, click en "Load unpacked", seleccioná la carpeta. Listo.

### 3. Clipeá tu primera página

Click en el ícono Atlas (violeta) en la toolbar → "Save to Obsidian" → confirmá. El `.md` aparece en tu vault.

## Cómo se usa

### Investigación
Clipeás 10 papers sobre un tema. Le preguntás a Claude "¿qué dicen sobre X?" — los conoce todos, sin copy-paste.

### Aprendizaje
Cada tutorial que leés queda guardado. Empezás un proyecto, Claude ya sabe lo que aprendiste la semana pasada.

### Code snippets
Clipeás una respuesta de StackOverflow. Mañana le preguntás a Claude algo similar y la cita sin que se la mandes.

## El último paso (1 vez por clip)

Después de clipear, le decís a Claude que lo recuerde:

```
/atlas:inject-atlas <tu-proyecto> <slug-del-clip>
```

A partir de ahí, Claude lo encuentra solo cuando es relevante. No tenés que volver a mencionarlo.

## Saber más

- [Ejemplos detallados](./EXAMPLES.md) — casos de uso reales, queries, debugging
- [Contribuir](./CONTRIBUTING.md) — desarrollo, testing, SDD workflow
- [Changelog](./CHANGELOG.md)
- [Releases](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases)

## Créditos

- Memoria persistente: [Engram](https://github.com/Gentleman-Programming/engram)
- Web Clipper brandeado, derivado del [Obsidian Web Clipper oficial](https://github.com/obsidianmd/obsidian-clipper) (MIT) con dos overrides: ícono Atlas y default folder `atlas-pool`. Todo lo demás sigue al upstream.
- License: ver [LICENSE](./LICENSE)
