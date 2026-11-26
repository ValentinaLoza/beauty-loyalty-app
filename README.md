# Beauty Loyalty

App web instalable (PWA) de fidelización y turnos para negocios de belleza.
Hoy la usa Bellamia Lashes Studio, y está pensada para reutilizarse en
cualquier otro negocio cambiando sólo la configuración.

- **Administradora:** clientas, servicios, programa de beneficios
  ("5 servicios → 20% OFF"), registro de servicios, canjes, agenda de turnos
  con horarios de atención, notificaciones push.
- **Clienta:** no necesita usuario. Recibe un enlace privado (`/card/<token>`)
  con su tarjeta, historial, beneficios y pedido de turnos; puede agregarla
  a la pantalla de inicio.

## Arquitectura

```text
Flutter Web (PWA)  ──►  Cloudflare Pages  (+ Functions en functions/)
        │
        ▼  publishable key (pública)
Supabase: Auth + PostgreSQL con RLS + funciones RPC + Realtime
        │
        └─► Edge Function push-dispatch (Web Push) + pg_cron
```

Todas las operaciones que tocan puntos, beneficios o turnos pasan por
funciones de la base (`supabase/migrations/`), que validan que quien llama
pertenezca al negocio. La web **nunca** contiene la `service_role` ni una
secret key.

## Estructura

| Carpeta | Qué hay |
| --- | --- |
| `lib/` | App Flutter (`app_state.dart` concentra el acceso a Supabase) |
| `web/` | HTML, manifiestos PWA y service worker de push, con marcadores de marca |
| `functions/` | Cloudflare Pages Functions: enlaces y manifiestos de la tarjeta |
| `supabase/migrations/` | Esquema de la base, en orden (`001` … `015`) |
| `supabase/functions/push-dispatch/` | Edge Function que envía las notificaciones |
| `supabase/tests/` | Prueba automática de la base |
| `supabase/scripts/` | SQL de diagnóstico y de limpieza manual (no son migraciones) |
| `tool/`, `scripts/` | Compilación con la marca del negocio y pruebas |
| `docs/` | Seguridad, alcance, marca, historial de cambios y planificación original |

## Puesta en marcha

### 1. Base de datos (Supabase)

- **Base existente (Bellamia, en producción):** ejecutar sólo
  `supabase/migrations/015_v3_performance_and_fixes.sql` en
  *SQL Editor*. Es seguro e idempotente: no borra ni cambia datos.
- **Negocio nuevo:** crear un proyecto Supabase y ejecutar en orden todas
  las migraciones de `supabase/migrations/` (los números 002–004 no
  existen; es normal). Después, crear la usuaria administradora en
  *Authentication → Users*. En el primer ingreso la app crea el negocio.

### 2. Configuración

Copiar `config/example.json` como `config/local.json` (no se sube a Git) y
completar:

| Clave | Ejemplo | Para qué |
| --- | --- | --- |
| `SUPABASE_URL` | `https://xxxx.supabase.co` | Proyecto Supabase |
| `SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_…` | Clave pública (nunca la secret) |
| `APP_TITLE` | `Bellamia Lashes Studio` | Nombre completo |
| `APP_SHORT_NAME` | `Bellamia` | Nombre bajo el ícono del celular |
| `THEME_COLOR` | `#8F5E78` | Color de la barra del navegador |
| `WEB_PUSH_VAPID_PUBLIC_KEY` | `B…` | Clave VAPID pública (push) |

### 3. Probar en la computadora

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=config/local.json
```

### 4. Compilar y publicar

```bash
./scripts/build_web.sh            # Windows: .\scripts\build_web.ps1
npx wrangler pages deploy build/web --project-name=bellamialashesstudio
```

El deploy de Bellamia está en **Cloudflare Pages**, proyecto
`bellamialashesstudio`, en la cuenta de Cloudflare con la que se hicieron los últimos deploys
(`https://bellamialashesstudio.pages.dev`, más el dominio propio si se
configuró uno). En *Settings → Variables* de ese proyecto conviene cargar
`APP_NAME`, `APP_SHORT_NAME` y `THEME_COLOR` para los enlaces de tarjeta.

**Deploy automático (opcional):** `.github/workflows/deploy.yml` publica en
cada cambio de `main` una vez cargados los secretos y variables que lista
ese archivo.

### 5. Notificaciones push

Ver `docs/SETUP_ORIGINAL.md` (Edge Function `push-dispatch`, claves VAPID
como secretos de Supabase y `supabase/config.push.toml.snippet`).

## Pruebas

```bash
# Base: aplica todas las migraciones en un Postgres vacío y prueba los flujos
PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres ./scripts/test_db.sh

# App
flutter analyze
flutter test
```

GitHub Actions corre ambas en cada push (`.github/workflows/ci.yml`).

## Usarla para otro negocio

1. Proyecto Supabase nuevo + todas las migraciones.
2. `config/local.json` con su nombre, color y claves.
3. Íconos propios en `web/icons/` y `web/favicon.png`.
4. Proyecto nuevo en Cloudflare Pages y `--project-name` con su nombre.

Más detalle en `docs/BRANDING_AND_REUSE.md`.

## Cambios de la v3

Ver `docs/changelog/CAMBIOS_V3.0.md`.
