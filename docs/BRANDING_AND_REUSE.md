# Nombre, marca y reutilización

## Para el emprendimiento actual

No hace falta cambiar el código Dart para el nombre visible dentro de la aplicación.

En el primer login se pide:

```text
Nombre del emprendimiento
Color principal
```

Luego se modifica desde:

```text
Admin → Negocio
```

El nombre aparece en el panel y en las tarjetas de las clientas.

## Nombre antes de iniciar sesión

En `config/local.json` poné el nombre real en `APP_TITLE`.

Para que el ícono instalado y el título HTML tengan exactamente ese nombre, también podés reemplazar `Loyalty Studio` en:

```text
web/manifest.json
web/index.html
```

## Para otro emprendimiento

La base ya usa `business_id`. Cada negocio tiene separados:

- marca;
- servicios;
- clientas;
- historial;
- fidelización;
- beneficios.

Podés reutilizarlo de dos maneras:

1. **Supabase separado por negocio:** máxima simplicidad y aislamiento.
2. **Mismo Supabase:** creás otro usuario Auth; su primer login crea otro negocio. RLS mantiene aislados los datos.
