# Phase 0.1 — Navigation Architecture

One mobile app with role-based experiences.

```text
APP
├── Splash
├── Onboarding
├── Auth
│   ├── Login
│   ├── Activate Account
│   └── Password Recovery
├── Client App
└── Admin Panel
```

Main decisions:
- One application.
- Client and admin shells.
- Clients may exist without an app account.
- Admin creates client records.
- Clients cannot modify loyalty data.
- Historical records are preserved.
- Flutter navigation will use `go_router`.
