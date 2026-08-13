# Routes

## Global

- `/splash`
- `/onboarding`

## Auth

- `/auth/login`
- `/auth/activate`
- `/auth/forgot-password`
- `/auth/reset-password`

## Client

- `/client/home`
- `/client/card`
- `/client/history`
- `/client/history/:recordId`
- `/client/rewards`
- `/client/appointments`
- `/client/appointments/:appointmentId`
- `/client/profile`
- `/client/profile/edit`

## Admin

- `/admin/dashboard`
- `/admin/clients`
- `/admin/clients/new`
- `/admin/clients/:clientId`
- `/admin/clients/:clientId/history`
- `/admin/clients/:clientId/notes`
- `/admin/clients/:clientId/rewards`
- `/admin/clients/:clientId/edit`
- `/admin/services`
- `/admin/services/new`
- `/admin/services/:serviceId/edit`
- `/admin/appointments`
- `/admin/appointments/new`
- `/admin/appointments/:appointmentId`
- `/admin/analytics`
- `/admin/analytics/clients`
- `/admin/loyalty`
- `/admin/more`
- `/admin/more/business`
- `/admin/more/notifications`
- `/admin/more/account`
- `/admin/more/settings`

## Guards

### Client routes

Las rutas `/client/*` requieren:

```text
role == client
```

### Admin routes

Las rutas `/admin/*` requieren:

```text
role == admin
```

Si el usuario intenta acceder a una ruta no autorizada debe ser redirigido a su home correspondiente.
