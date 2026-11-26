# Activar las notificaciones push

Las notificaciones avisan a la administradora de turnos nuevos y a las
clientas de sus turnos y beneficios, aunque la app esté cerrada.

## Cómo funciona

```text
algo pasa en la base (turno, beneficio, recordatorio por pg_cron)
  → fila nueva en notification_outbox
  → Database Webhook (configurado en el panel de Supabase)
  → Edge Function push-dispatch  (usa las claves VAPID)
  → el navegador del celular muestra la notificación
```

**Claves VAPID:** un par de claves que identifica a tu app ante los
servicios de notificaciones de Google, Apple y Mozilla.

- La **pública** va dentro de la app (`WEB_PUSH_VAPID_PUBLIC_KEY` en la
  configuración). No es secreta.
- La **privada** va sólo en los *secrets* de Supabase. Nunca en la app,
  en Git ni en un chat.

Se generan una vez por proyecto. Si se cambian, cada celular tiene que
volver a tocar "Activar notificaciones".

## Pasos (una sola vez por proyecto)

### 1. Generar las claves (en tu computadora)

En PowerShell:

```bash
npx web-push generate-vapid-keys
```

Muestra una *Public Key* y una *Private Key*. Dejá la ventana abierta.

### 2. Guardarlas en Supabase

*Edge Functions → Secrets → Add new secret*, tres veces:

| Name | Value |
| --- | --- |
| `VAPID_PUBLIC_KEY` | la *Public Key* |
| `VAPID_PRIVATE_KEY` | la *Private Key* |
| `VAPID_SUBJECT` | `mailto:` + un email de contacto, ej. `mailto:hola@ejemplo.com` |

### 3. Crear la función de envío

1. *Edge Functions → Deploy a new function → Via Editor*.
2. Nombre: `push-dispatch` (exactamente así).
3. Borrar el código de ejemplo y pegar todo
   `supabase/functions/push-dispatch/index.ts`. *Deploy*.
4. En la función, pestaña *Details* (o *Settings*): **desactivar**
   *Verify JWT* / *Enforce JWT verification* y guardar.
   La función valida por su cuenta la clave secreta del paso 4.

### 4. Conectar la base con la función (Database Webhook)

1. *Project Settings → API Keys → Secret keys*: copiar la clave `default`
   (empieza con `sb_secret_`). No la compartas con nadie.
2. *Database → Webhooks → Create a new hook*:
   - Name: `push-dispatch`
   - Table: `notification_outbox` · Events: **Insert**
   - Type: **Supabase Edge Functions** → `push-dispatch` · Method `POST`
   - HTTP Headers → *Add a new header*: `apikey` = la clave `sb_secret_…`
   - *Create webhook*.

### 5. Poner la clave pública en la app y publicar

Completar `WEB_PUSH_VAPID_PUBLIC_KEY` en `config/bellamia.json` (o
`config/local.json`), compilar y publicar.

### 6. Probar

En el celular de la administradora: *Negocio → Notificaciones → Activar*.
En iPhone, primero *Compartir → Agregar a pantalla de inicio* y abrir la
app desde ese ícono. Después, pedir un turno desde la tarjeta de una
clienta: debe llegar el aviso.

Si no llega: *Edge Functions → push-dispatch → Logs*, y *Database →
Webhooks → push-dispatch* para ver si hubo llamadas y sus errores.
