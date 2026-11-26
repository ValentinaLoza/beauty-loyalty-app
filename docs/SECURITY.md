# Seguridad

## Claves

El navegador usa únicamente:

```text
Project URL
Publishable key
```

Nunca coloques en Flutter:

```text
Secret key
service_role
contraseña de PostgreSQL
```

## Administración

Las acciones administrativas requieren:

- sesión Supabase Auth;
- membership activa del negocio;
- políticas RLS;
- funciones SQL con validaciones.

## Tarjetas de clientas

Las clientas no tienen acceso directo a las tablas.
Cada ficha tiene un UUID privado en el enlace.
La función pública devuelve únicamente datos seguros de la tarjeta, historial y beneficios.
No expone email ni teléfono personal de la clienta.

Si un link se filtra, desde Admin se puede regenerar y el anterior queda inválido.
