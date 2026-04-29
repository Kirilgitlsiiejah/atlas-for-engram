# 🏛️ Atlas para engram — convertí tu Obsidian en una extensión de tu memoria persistente

Engram te da memoria persistente. Atlas la extiende al browser. Todo lo que clipeás de la web entra a tu engram como observaciones `type=atlas`, scoped al proyecto que estés laburando, queryable junto con tu trabajo. Tu lectura web, indexada con tu memoria de Claude.

## ¿Qué hace atlas, exactamente?

- **Web Clipper brandeado** que escribe los clips directo a tu vault de Obsidian, en una carpeta `atlas-pool/`. Markdown plano: `source_url` es canónico, pero Atlas también lee `source` en clips legacy.
- **Skills que conectan ese pool con engram**: inyectar un clip como `type=atlas`, lookup de URLs, generar índice navegable, integrity checks, edit y delete in-place.
- **Hook automático post-search**: cada vez que Claude busca en tu engram, separa silenciosamente "tu trabajo" (decisions, bugfixes, discoveries) de "lo que clipeaste" (atlas). Ves de un vistazo qué es tuyo y qué es lectura.
- **Catálogo `Atlas-Index.md` auto-generado** en la raíz del vault, agrupado por dominio fuente. Navegás tu atlas como navegás tu vault.
- **Vault auto-detectado** por walk-up desde el cwd. Cero config, cero paths hardcoded.
- **Doctor por sesión** que valida estado del plugin, engram corriendo y vault accesible antes de que algo falle silencioso.

## Setup — asumiendo que ya tenés engram corriendo

Si ya tenés engram funcionando, sumarle atlas son 5 minutos. Necesitás 3 cosas más:

**1. Obsidian** — cualquier vault, atlas lo detecta solo. Si no lo tenés: https://obsidian.md

**2. Atlas Web Clipper** — bajá el zip de tu browser, descomprimí, y `Load unpacked` desde `chrome://extensions` (Developer Mode prendido):
- Chrome / Edge / Brave: [atlas-clipper-1.6.2-chrome.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-chrome.zip)
- Firefox: [atlas-clipper-1.6.2-firefox.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-firefox.zip)
- Safari: [atlas-clipper-1.6.2-safari.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-safari.zip)

**3. El plugin atlas-for-engram** — una vez, dentro de Claude Code:

```
/plugin install atlas@github:Kirilgitlsiiejah/atlas-for-engram
```

## Cómo se usa — hablás natural, las skills se disparan solas

- **Clip + inject** (`inject-atlas`): clipeás un paper desde el browser y le decís *"agregá esto al atlas del proyecto auth-rewrite"*. Queda en engram como `type=atlas`, scoped al proyecto, con `source_url` y slug.
- **Lookup** (`atlas-lookup`): *"¿tengo atlas de esta URL?"* — te dice si ya lo clipeaste, en qué proyecto vive, si está injectado en engram, o si está sin injectar todavía. Cuatro escenarios cubiertos.
- **Atlas-Index** (`atlas-index`): *"generame el atlas index del proyecto auth-rewrite"* — escribe `Atlas-Index.md` en la raíz del vault, agrupado por dominio, con links a los raws.
- **Auto-comparación** (`compare-with-atlas`): cuando le preguntás algo a Claude, busca en engram y separa los hits entre "tus decisiones/discoveries" y "lo que clipeaste de la web". Sin que se lo pidas.
- **Cleanup** (`atlas-cleanup`): *"corré integrity check del atlas"* — reporta orphans (engram sin raw), dangling (raw sin inject), duplicados (misma URL en varios proyectos), malformed.
- **Edit y delete** (`atlas-edit`, `atlas-delete`): *"editá el atlas de esa URL, cambiá el título y re-inyectá"* o *"borrá todos los atlas del dominio X del proyecto Y"*. In-place, bulk si querés.

## Por qué importa

Tu engram + atlas = todo tu trabajo + todo lo que leés, en un solo lugar consultable. Inyectás lo que querés, y Claude lo encuentra cuando es relevante — sin que vos te acuerdes de pegarle el link de nuevo. La web que consumís deja de ser efímera y pasa a ser parte de tu memoria, separada por proyectos, comparable contra tus decisions.

## Links

- Repo: https://github.com/Kirilgitlsiiejah/atlas-for-engram
- Releases (zips del clipper): https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/latest
- Engram: https://github.com/Gentleman-Programming/engram
- Obsidian: https://obsidian.md
