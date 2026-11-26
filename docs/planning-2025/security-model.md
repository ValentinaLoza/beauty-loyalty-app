# Security Model

## Authentication
Supabase Auth manages credentials.
Passwords are never stored in application tables.

## Row Level Security
RLS will be enabled.

### Client may read
- own client record;
- own service history;
- own loyalty transactions;
- own rewards.

### Client may not
- register services;
- insert loyalty transactions;
- issue rewards;
- redeem rewards.

### Business member
May access operational data only for businesses where an active membership exists.

## Critical RPC Operations
- `register_service()`
- `redeem_reward()`
- future `void_service()`

Critical loyalty writes should happen through controlled database functions.
