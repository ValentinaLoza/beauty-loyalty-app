# Cómo ponerla en funcionamiento

## 1. Crear proyecto Supabase

Creá un proyecto nuevo en Supabase Free.
No necesitás Docker ni Supabase CLI para este flujo.

## 2. Crear la base

En Supabase abrí:

```text
SQL Editor → New query
```

Abrí este archivo local:

```text
supabase/migrations/001_production_schema.sql
```

Copiá TODO, pegalo en SQL Editor y ejecutá `Run`.
Debe terminar sin errores.

## 3. Crear la administradora

En Supabase:

```text
Authentication → Users → Add user
```

Creá el usuario de tu amiga con su email y una contraseña segura.

No crees el negocio manualmente. En el primer login la web pregunta el nombre y color y lo crea automáticamente.

## 4. Obtener las claves públicas

En Supabase buscá el panel `Connect`.
Necesitás:

```text
Project URL
Publishable key
```

NO uses Secret key ni service_role.

## 5. Configurar Flutter

Copiá:

```text
config/example.json
```

como:

```text
config/local.json
```

Completalo:

```json
{
  "SUPABASE_URL": "https://TU-PROYECTO.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "APP_TITLE": "NOMBRE REAL DEL EMPRENDIMIENTO"
}
```

`config/local.json` no se sube a Git.

## 6. Dependencias

Desde la raíz:

```powershell
flutter pub get
```

## 7. Probar localmente

```powershell
flutter run -d chrome --dart-define-from-file=config/local.json
```

Ingresá con el usuario de Auth creado en Supabase.
En el primer ingreso completá el nombre real del emprendimiento.

## 8. Configuración inicial

### Negocio
Cargá nombre, color, teléfono/WhatsApp y logo opcional.

### Servicios
Cargá los servicios y precios reales.

### Fidelización
Definí, por ejemplo:

```text
5 servicios → 20% OFF
```

### Clientas
Creá una clienta de prueba.
Entrá a su ficha y elegí `Copiar tarjeta`.
Abrí el link en incógnito: debe funcionar sin login.

## 9. Prueba antes de publicar

1. Registrá 5 servicios.
2. Confirmá que aparezca el beneficio.
3. Abrí el link público de la clienta.
4. Confirmá que vea el mismo beneficio.
5. Canjeá el beneficio desde Admin.
6. Refrescá el link público.
7. Confirmá que figure utilizado.
8. Probá `Regenerar enlace privado` y verificá que el anterior deje de funcionar.

## 10. Compilar producción

```powershell
flutter build web --release --dart-define-from-file=config/local.json
```

Resultado:

```text
build/web
```

## 11. Publicar gratis en Cloudflare Pages

Usá Cloudflare Pages con **Direct Upload** y subí `build/web`.
Cloudflare te dará una URL parecida a:

```text
https://nombre.pages.dev
```

Después de publicar, generá/copía nuevamente los links de las clientas desde la URL publicada. No compartas links de `localhost`.

## 12. Probar desde celular

- Abrí la URL `pages.dev`.
- Probá login Admin.
- Abrí un link privado de clienta.
- Probá en modo incógnito.
- Agregá la web a pantalla de inicio si querés usarla como PWA.
