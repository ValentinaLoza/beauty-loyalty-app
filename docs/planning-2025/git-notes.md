# Git Workflow

```text
main
└── develop
    ├── docs/database-design
    ├── feature/auth
    ├── feature/clients
    ├── feature/loyalty
    └── feature/rewards
```

Use Conventional Commits, for example:

```bash
git commit -m "docs: define database architecture"
git commit -m "feat: implement authentication flow"
git commit -m "fix: prevent duplicate loyalty transaction"
```
