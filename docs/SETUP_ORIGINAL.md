# Beauty Loyalty — versión productiva

Esta versión reemplaza el almacenamiento local de la demo por **Supabase**.

## Incluye

### Administradora
- Login real con Supabase Auth.
- Creación del emprendimiento en el primer ingreso.
- Nombre, color, teléfono y logo configurables.
- Dashboard con métricas.
- Alta y búsqueda de clientas.
- Alta y activación/desactivación de servicios.
- Programa configurable: cantidad de servicios + porcentaje de descuento.
- Registro de servicios.
- Generación automática de beneficios.
- Canje del beneficio y cálculo del descuento.
- Historial centralizado.
- Enlace privado por clienta.
- Copiar enlace y compartir por WhatsApp.
- Revocar/regenerar enlace.

### Clienta
- No necesita usuario ni contraseña.
- Recibe un enlace privado tipo `/c/<uuid>`.
- Consulta tarjeta, historial, beneficios y datos del emprendimiento.

## Arquitectura

```text
Flutter Web / PWA
        ↓
Supabase Publishable Key
        ↓
Supabase Auth + PostgreSQL + RLS
```

La web **nunca** debe contener una Secret key ni `service_role`.
