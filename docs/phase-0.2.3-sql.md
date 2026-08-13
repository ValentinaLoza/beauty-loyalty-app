# Phase 0.2.3 — Initial Supabase/PostgreSQL SQL Migration

## Status

Completed initial executable migration:

```text
supabase/
└── migrations/
    └── 001_initial_schema.sql
```

## Included

The migration creates:

- `profiles`
- `businesses`
- `business_members`
- `clients`
- `services`
- `loyalty_programs`
- `service_records`
- `loyalty_transactions`
- `rewards`
- `reward_redemptions`

It also includes:

- UUID primary keys
- foreign keys
- CHECK constraints
- unique constraints
- partial unique indexes
- history-preserving relationships
- `updated_at` triggers
- automatic profile creation after an `auth.users` insert
- Row Level Security
- role-aware RLS policies
- restricted grants
- idempotency protection
- row locking for loyalty operations
- `register_service()` RPC
- `redeem_reward()` RPC

## Atomic operations

### `register_service()`

Atomically:

1. validates authentication and business membership;
2. locks the client;
3. protects retries with `idempotency_key`;
4. registers the service;
5. credits loyalty points;
6. calculates the current balance;
7. issues one or more rewards when required;
8. consumes the corresponding points;
9. returns one JSON result.

### `redeem_reward()`

Atomically:

1. validates authentication and permissions;
2. locks the client;
3. locks the reward;
4. validates reward status and expiry;
5. calculates the discount;
6. registers the discounted service;
7. records the redemption;
8. marks the reward as redeemed;
9. credits the new service's loyalty points;
10. issues any newly earned rewards.

## Important implementation note

The RPC functions are `SECURITY DEFINER`, but they explicitly verify `auth.uid()` and active business membership. They also use a restricted `search_path` and fully-qualified object names.

Critical history tables are read-only through normal authenticated table access. Their writes are performed by controlled RPC functions.

## Current error codes

- `AUTH_REQUIRED`
- `IDEMPOTENCY_KEY_REQUIRED`
- `IDEMPOTENCY_KEY_CONFLICT`
- `BUSINESS_ACCESS_DENIED`
- `BUSINESS_INACTIVE`
- `BUSINESS_MISMATCH`
- `CLIENT_NOT_FOUND`
- `CLIENT_INACTIVE`
- `SERVICE_NOT_FOUND`
- `SERVICE_INACTIVE`
- `INVALID_PRICE`
- `REWARD_NOT_FOUND`
- `REWARD_NOT_AVAILABLE`
- `REWARD_EXPIRED`
- `REWARD_CURRENCY_MISMATCH`
- `REWARD_NOT_VALID_FOR_SERVICE`
- `CUSTOM_REWARD_UNSUPPORTED`

## Still intentionally pending

The first migration does **not** yet implement:

- `void_service()`
- appointment tables
- client private notes
- employee management UI
- business bootstrap/onboarding RPC
- client self-edit RPC
- expired reward maintenance job
- automated database tests

These belong to later implementation phases.

## Next validation step

Before connecting Flutter, create a Supabase development project and apply this migration in a development environment. Then validate:

1. schema creation;
2. owner bootstrap;
3. RLS;
4. client/service CRUD;
5. `register_service()`;
6. 5-point reward issuance;
7. idempotent retries;
8. `redeem_reward()`;
9. concurrent service registration;
10. cross-business isolation.
