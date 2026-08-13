# Phase 0.2 — Database Design

The MVP supports:
- businesses;
- business members;
- clients with or without app accounts;
- services;
- service history;
- loyalty programs;
- loyalty transactions;
- rewards;
- reward redemptions.

Main tables:

```text
auth.users
profiles
businesses
business_members
clients
services
loyalty_programs
service_records
loyalty_transactions
rewards
reward_redemptions
```

Loyalty balance is derived from:

```sql
SUM(loyalty_transactions.points_delta)
```

There is no mutable `points_current` source of truth.
