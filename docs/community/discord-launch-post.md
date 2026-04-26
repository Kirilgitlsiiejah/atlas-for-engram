# 🏛️ Atlas-for-Engram — la memoria infinita para Claude que vive en tu Obsidian

## ¿Qué es esto?

Claude se olvida de TODO entre sesiones. Cada conversación arranca de cero: re-explicás el mismo paper, pegás los mismos snippets, contás el mismo contexto. **Atlas-for-Engram** arma un loop browser → Obsidian → Claude para que lo que leíste una vez quede guardado para siempre, y Claude lo consulte solo cuando lo necesita.

## El problema, en concreto

Imaginate que estás leyendo un artículo de 30 minutos sobre WebSockets. Lo cerrás. Mañana le preguntás algo a Claude. Claude no tiene idea. Vos volvés a abrir el artículo, copiás 5 párrafos, pegás en el chat. Cada. Vez. Multiplicalo por 20 papers, 50 tutoriales, 100 respuestas de StackOverflow. Es agotador.

## La solución — 3 piezas

1. **Atlas Web Clipper** — extensión de browser brandeada (ícono violeta). Hacés click y el artículo se guarda como `.md` en tu vault de Obsidian.
2. **Atlas-pool** — la carpeta de tu vault donde viven todos los clips. Markdown plano, lo editás y organizás como quieras.
3. **Inject-atlas + Engram** — un comando le dice a Claude "leelo y acordate". Queda en memoria persistente para siempre.

## Cómo se instala

**1.** Instalá el plugin desde Claude Code:

```bash
/plugin install atlas@github:Kirilgitlsiiejah/atlas-for-engram
```

**2.** Descargá el clipper para tu browser desde la [release v0.2.0](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/tag/v0.2.0) y descomprimilo a una carpeta estable:

- Chrome / Edge / Brave: [atlas-clipper-1.6.2-chrome.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-chrome.zip)
- Firefox: [atlas-clipper-1.6.2-firefox.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-firefox.zip)
- Safari: [atlas-clipper-1.6.2-safari.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-safari.zip)

**3.** Cargá la extensión en Chrome:

```
# chrome://extensions → Developer Mode ON → Load unpacked → seleccioná la carpeta descomprimida
```

**4.** Listo — clipeá tu primera página:

```bash
# Click en el ícono Atlas (violeta) en la toolbar → Save to Obsidian → confirmar
# Después en Claude:
/atlas:inject-atlas <tu-proyecto> <slug-del-clip>
```

## 3 ejemplos de uso

- **Investigación**: clipeás 10 papers, le preguntás a Claude "qué dicen estos sobre X" — los conoce todos, sin pegar nada.
- **Aprendizaje**: cada tutorial que leés queda guardado. Empezás un proyecto nuevo y Claude ya sabe lo que aprendiste la semana pasada.
- **Code snippets**: clipeás una respuesta de StackOverflow hoy, mañana Claude la cita cuando le preguntás algo similar.

## Links

- Repo: https://github.com/Kirilgitlsiiejah/atlas-for-engram
- Releases: https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases
- Engram (la memoria daemon): https://github.com/Gentleman-Programming/engram
