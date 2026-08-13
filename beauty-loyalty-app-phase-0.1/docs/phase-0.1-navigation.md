# Fase 0.1 — Mapa completo de pantallas y navegación

## Objetivo

Definir la estructura funcional de navegación antes de comenzar la implementación en Flutter.

La aplicación será una sola app con dos experiencias según el rol autenticado:

- `client`
- `admin`

## Flujo global

```text
APP
│
├── Splash
├── Onboarding
└── Autenticación
      │
      ├── Iniciar sesión
      ├── Recuperar contraseña
      └── Activar cuenta
               │
               ▼
         Resolver usuario
               │
        ┌──────┴───────┐
        │              │
     CLIENTA         ADMIN
        │              │
        ▼              ▼
    Client App     Admin Panel
```

## Lógica de sesión

```text
¿Hay sesión iniciada?

NO
↓
Login

SÍ
↓
Consultar perfil

role == client
↓
/client/home

role == admin
↓
/admin/dashboard
```

## Decisiones principales

- Una sola aplicación.
- Dos roles principales: `admin` y `client`.
- Las clientas pueden existir sin tener cuenta.
- La administradora crea la ficha de la clienta.
- La clienta puede ser invitada más adelante a activar su cuenta.
- Los puntos y beneficios no pueden modificarse desde la cuenta clienta.
- Los servicios realizados quedan registrados históricamente.
- Los datos históricos no se eliminan físicamente.
- Se utilizará `go_router`.
- La arquitectura queda preparada para agenda, QR, empleados y múltiples negocios.
