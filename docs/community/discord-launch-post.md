# 🏛️ Atlas-for-engram — la memoria infinita que vive en tu Obsidian

Claude se olvida de todo entre sesiones. Cada conversación arranca de cero. ¿Cuántas veces le re-explicaste el mismo paper, el mismo artículo, el mismo tutorial que leíste el lunes? Ya está. Se terminó.

**Inyectá lo que quieras a la memoria de tu proyecto en engram.** Todo lo que clipeás de la web, todo lo que leés, todo lo que aprendés — Claude lo recuerda para siempre y lo cita solo cuando es relevante. Tu cerebro, externalizado. Tu memoria, tu proyecto, lo que vos quieras, persistente para siempre.

## ¿Cómo funciona?

Mientras navegás, clipeás cualquier página con el Atlas Web Clipper y se guarda como markdown plano en tu vault de Obsidian, en una carpeta `atlas-pool/`. Después le decís a Claude algo como *"agregá esto a la memoria del proyecto X"* y se inyecta solo a engram. La próxima vez que le preguntes algo relacionado, lo cita sin que vos tengas que mandarle nada. Hablás natural, él dispara las skills cuando detecta lo que querés.

## Setup — 4 ingredientes, una sola vez

**1. Obsidian** — Si no lo tenés, [bajalo acá](https://obsidian.md/). Cualquier vault sirve, atlas detecta el tuyo solo.

**2. Atlas Web Clipper** — el clipper brandeado, descargá el zip para tu browser:
- Chrome / Edge / Brave: [atlas-clipper-1.6.2-chrome.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-chrome.zip)
- Firefox: [atlas-clipper-1.6.2-firefox.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-firefox.zip)
- Safari: [atlas-clipper-1.6.2-safari.zip](https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/download/v0.2.0/atlas-clipper-1.6.2-safari.zip)

Descomprimí el zip a una carpeta estable, andá a `chrome://extensions`, prendé Developer Mode, click en "Load unpacked", seleccioná la carpeta. Listo.

**3. Engram** — el daemon de memoria persistente. Lo bajás de [acá](https://github.com/Gentleman-Programming/engram) y lo dejás corriendo de fondo.

**4. El plugin** — una sola vez, dentro de Claude Code:

```
/plugin install atlas@github:Kirilgitlsiiejah/atlas-for-engram
```

## De ahí en más, 0 comandos 🚀

No tenés que aprender ninguna sintaxis nueva. No hay comandos para memorizar, ni flags raras, ni nombres de skills. Vos hablás con Claude como hablás siempre, y él dispara las skills cuando detecta que querés inyectar algo, buscar en tu atlas, o consultar lo que clipeaste hace tres semanas.

## 3 ejemplos reales

- **Investigación**: clipeás 10 papers sobre WebSockets durante la semana. El viernes le preguntás *"¿qué patrones aparecen sobre reconnection?"* — los conoce todos, sin copy-paste, sin pegar links.
- **Aprendizaje**: cada tutorial que leés queda guardado. Empezás un proyecto nuevo y Claude ya sabe lo que aprendiste el mes pasado, sin que se lo cuentes de nuevo.
- **Code snippets**: clipeás una respuesta de StackOverflow hoy. Mañana le preguntás algo parecido y la cita sin que se la pegues otra vez.

## Links

- Repo: https://github.com/Kirilgitlsiiejah/atlas-for-engram
- Última release: https://github.com/Kirilgitlsiiejah/atlas-for-engram/releases/latest
- Engram (la memoria daemon): https://github.com/Gentleman-Programming/engram
- Obsidian: https://obsidian.md
