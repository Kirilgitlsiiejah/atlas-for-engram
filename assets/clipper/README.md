# Atlas Clipper

Obsidian Web Clipper, brandeado y enchufado al `atlas-pool`.

## ¿Qué es esto?

Es un fork minimal del [Obsidian Web Clipper](https://github.com/obsidianmd/obsidian-clipper) oficial. Solo cambian dos cosas:

1. El ícono de la extensión (Atlas titán, en vez del ícono morado de Obsidian).
2. El folder default de guardado (`atlas-pool` en vez de `Clippings`).

Todo lo demás — settings UI, templates, behavior, manifest, nombre, versión — sigue siendo el upstream tal cual. Esto es a propósito: es una customización derivada, no un producto rebrandeado.

## ¿Por qué un fork y no un preset?

Porque el ícono no se puede customizar via preset, solo via build. El preset JSON del Web Clipper sí cubre el folder default (mirá `src/utils/import-export.ts` upstream si querés el detalle), pero la imagen de la extensión vive en el `manifest.json` y los assets, así que para tocarla hay que rebuildear.

Si vos no necesitás el ícono Atlas y solo querés el folder default, el preset es una alternativa válida — más liviana, sin pipeline de build.

## Build local

### Prerrequisitos

- `git`
- `node` >= 18
- `npm`
- `bash` (en Windows: Git Bash funciona perfecto, es lo que usé yo)

### Comando

Desde la raíz del repo:

```bash
bash assets/clipper/build.sh
```

Tarda 1-3 minutos: la mayor parte se la come `npm ci` la primera vez, y después webpack buildeando los 3 targets.

### Output

Te quedan en `assets/clipper/dist/`:

- `atlas-clipper-1.6.2-chrome.zip`
- `atlas-clipper-1.6.2-firefox.zip`
- `atlas-clipper-1.6.2-safari.zip`
- `NOTICE.md` — atribución MIT + log de modificaciones

El build es idempotente: re-correrlo limpia `dist/` y rearma todo desde cero. La carpeta `dist/` está gitignoreada — cada uno la genera local.

## Instalación por browser

### Chrome / Edge / Brave / Vivaldi (Chromium)

1. Descomprimí `atlas-clipper-1.6.2-chrome.zip` en una carpeta estable (no la borres después, la extensión la necesita en disco).
2. Andá a `chrome://extensions` (o `edge://extensions`, `brave://extensions`, etc.).
3. Activá **Developer Mode** (esquina superior derecha).
4. Clickeá **"Load unpacked"** y apuntá a la carpeta que descomprimiste.

Con Manifest V3, mientras la pestaña de extensions esté abierta al menos una vez la extensión persiste entre sesiones. Si Chrome la deshabilita, volvé a esa pestaña y reactivala.

### Firefox

1. Andá a `about:debugging`.
2. Clickeá **"This Firefox"** en la barra lateral.
3. Clickeá **"Load Temporary Add-on..."** y seleccioná directamente el `.zip` (Firefox lo acepta sin descomprimir).

**Caveat importante:** las "temporary add-ons" se pierden al cerrar Firefox. Si querés persistencia, hay que firmar la extensión a través del proceso de Mozilla Add-ons (AMO o self-distribution con cuenta de developer), que está fuera del scope de este README.

### Safari

Necesitás macOS + Xcode instalado.

```bash
xcrun safari-web-extension-converter atlas-clipper-1.6.2-safari.zip
```

Eso te genera un proyecto Xcode. Abrilo, buildealo, y en Safari habilitá **Develop > Allow Unsigned Extensions** antes de activar la extensión en Settings > Extensions.

## Regenerar íconos

Si querés cambiar el logo (otro mascota, otro color, lo que sea):

1. Reemplazá la imagen fuente y corré:

   ```bash
   python assets/clipper/scripts/generate-icons.py \
       --source <ruta-a-tu-imagen.png> \
       --out-dir assets/clipper/icons/
   ```

   El script aplica un alpha matte sobre el fondo blanco y resamplea con LANCZOS a 16/48/128 px.

2. Re-corré `bash assets/clipper/build.sh` para que los nuevos íconos entren en los zips.

## ¿Qué se modificó del upstream?

Solo cuatro archivos. Transparencia total:

| Archivo upstream | Cambio |
|---|---|
| `src/managers/template-manager.ts:119` | `'Clippings'` → `'atlas-pool'` |
| `src/managers/template-ui.ts:149,559` | `'Clippings'` → `'atlas-pool'` (dos ocurrencias: default + reset path) |
| `src/settings.html:710` | `placeholder="Clippings"` → `placeholder="atlas-pool"` |
| `src/icons/icon{16,48,128}.png` | Reemplazados por la versión Atlas branded |

**Nota:** `manifest.json` NO se toca a propósito. Mantener el nombre y versión upstream deja explícito que esto es un derivative work, no un producto distinto. El `NOTICE.md` que va adentro de los zips reproduce la atribución completa.

El build tiene guards (`expect_count`) que verifican antes y después del patch que las strings estén exactamente donde se esperan. Si upstream renombra o mueve algo, el build falla loud en vez de generar un zip silenciosamente roto.

## Bump del upstream

Cuando salga una versión nueva del Web Clipper:

1. Editá `UPSTREAM_TAG` arriba de `build.sh` (línea 32).
2. Re-corré `bash assets/clipper/build.sh`.

Si los `expect_count` saltan, significa que upstream renombró o movió las líneas patcheadas — vas a tener que revisar los nuevos paths/strings y adaptar el patch en `build.sh` antes de que el build pase.

Pinneamos por tag (no por branch) para que la build sea reproducible: el mismo tag siempre te genera los mismos zips.

## Atribución MIT

Este software deriva de [Obsidian Web Clipper](https://github.com/obsidianmd/obsidian-clipper) © 2024 Obsidian, licenciado bajo MIT. El `NOTICE.md` adentro de los zips reproduce la atribución completa junto al log de modificaciones aplicadas.
