# Bellamia — debug fix del PWA de clienta

Se encontraron dos fallas reales en el ZIP completo:

1. `functions/card/[token].js` pedía `/index.html` a `ASSETS.fetch()`.
   En Cloudflare Pages, la canonicalización de URLs limpias puede devolver una
   redirección de `/index.html` a `/`. La Function devolvía esa redirección y el
   navegador terminaba en la raíz administrativa.

2. Aun si `/card/<token>` cargaba, `PublicClientPage` llamaba
   `bellamiaPrepareClientInstall()`, y `web/push_bridge.js` reemplazaba el
   manifest específico `/card-manifest/<token>` por el manifest genérico
   `/client-manifest.json`. Ese manifest arrancaba en `/client` sin UUID, por
   eso la app instalada mostraba "No pudimos identificar tu tarjeta".

## Corrección

- `/card/<UUID>` ahora recibe un shell Flutter directamente desde la Pages
  Function. No se vuelve a pedir `/index.html`, por lo que no hay redirección a
  `/`.
- El manifest permanece siempre en `/card-manifest/<UUID>`.
- Ese manifest usa `start_url: /card/<UUID>` y `scope: /card/`.
- Los links antiguos `/c/<UUID>` redirigen a `/card/<UUID>`.
- Se limpió `web/index.html`, que tenía `push_bridge.js` duplicado y uno de los
  scripts estaba fuera de `<head>`.

## Publicar

Desde la raíz del proyecto:

```powershell
flutter clean
flutter pub get
flutter build web --release --dart-define-from-file=config/local.json
npx wrangler pages deploy build/web --project-name=bellamialashesstudio
```

La carpeta `functions` debe estar en la raíz al ejecutar Wrangler.

## Probar

Primero en Safari, sin instalar:

`https://bellamialashesstudio.pages.dev/card/fdf46d4d-0025-46b6-b1a8-862f0c391c28`

Debe mostrar la tarjeta, no el admin.

Después abrir:

`https://bellamialashesstudio.pages.dev/card-manifest/fdf46d4d-0025-46b6-b1a8-862f0c391c28`

Debe contener `start_url` igual a `/card/fdf46d4d-0025-46b6-b1a8-862f0c391c28`.

Recién entonces borrar el ícono Bellamia anterior del iPhone y agregar la
nueva tarjeta a pantalla de inicio.

Después de confirmar que funciona, ejecutar `010_v2_1_card_urls.sql` si todavía
no se aplicó, para que los clics de notificaciones de clienta también usen
`/card/<UUID>`.
