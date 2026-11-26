# PostgreSQL Technical Schema

## Conventions
- IDs: `uuid`
- UUID default: `gen_random_uuid()`
- Dates/times: `timestamptz`
- Money: `numeric(12,2)`
- Soft-delete/inactive states preferred
- Row Level Security planned

## profiles
`id uuid PK/FK auth.users.id`
`first_name varchar(80) not null`
`last_name varchar(80) not null`
`phone varchar(30)`
`avatar_url text`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`

## businesses
`id uuid PK`
`name varchar(120) not null`
`logo_url text`
`phone varchar(30)`
`email varchar(254)`
`address text`
`currency_code char(3) default 'ARS'`
`active boolean default true`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`

## business_members
`id uuid PK`
`business_id uuid FK`
`user_id uuid FK profiles.id`
`role text check owner/admin/employee`
`active boolean default true`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`
`unique(business_id,user_id)`

## clients
`id uuid PK`
`business_id uuid FK`
`user_id uuid nullable FK profiles.id`
`first_name varchar(80) not null`
`last_name varchar(80) not null`
`phone varchar(30)`
`email varchar(254)`
`birth_date date`
`active boolean default true`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`
`unique(business_id,user_id)`

## services
`id uuid PK`
`business_id uuid FK`
`name varchar(120) not null`
`description text`
`default_price numeric(12,2) check >= 0`
`loyalty_points integer default 1 check >= 0`
`duration_minutes integer nullable check > 0`
`active boolean default true`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`

## loyalty_programs
`id uuid PK`
`business_id uuid FK`
`name varchar(120) not null`
`points_required integer check > 0`
`reward_type text`
`reward_value numeric(12,2)`
`free_service_id uuid nullable FK`
`custom_description text`
`expires_after_days integer nullable check > 0`
`active boolean default true`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`

Only one active program per business.

## service_records
`id uuid PK`
`business_id uuid FK`
`client_id uuid FK`
`service_id uuid FK`
`registered_by uuid nullable FK`
`service_name_snapshot varchar(120)`
`base_price numeric(12,2)`
`discount_amount numeric(12,2) default 0`
`final_price numeric(12,2)`
`currency_code char(3)`
`loyalty_points_earned integer default 0`
`performed_at timestamptz`
`notes text`
`status text default 'completed'`
`voided_at timestamptz`
`voided_by uuid`
`void_reason text`
`idempotency_key uuid not null`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`
`unique(business_id,idempotency_key)`

## loyalty_transactions
`id uuid PK`
`business_id uuid FK`
`client_id uuid FK`
`program_id uuid FK`
`service_record_id uuid nullable FK`
`reward_id uuid nullable FK`
`transaction_type text`
`points_delta integer check <> 0`
`description text`
`created_by uuid nullable FK`
`created_at timestamptz default now()`

Types:
- service_earned
- reward_issued
- manual_adjustment
- correction
- service_reversal
- reward_reversal

## rewards
`id uuid PK`
`business_id uuid FK`
`client_id uuid FK`
`program_id uuid FK`
`reward_type text`
`reward_value numeric(12,2)`
`reward_currency_code char(3)`
`free_service_id uuid nullable FK`
`description_snapshot text`
`status text default 'available'`
`issued_at timestamptz default now()`
`expires_at timestamptz`
`created_at timestamptz default now()`
`updated_at timestamptz default now()`

## reward_redemptions
`id uuid PK`
`reward_id uuid FK UNIQUE`
`business_id uuid FK`
`client_id uuid FK`
`service_record_id uuid FK UNIQUE`
`redeemed_by uuid nullable FK`
`discount_amount numeric(12,2) default 0`
`currency_code char(3)`
`redeemed_at timestamptz default now()`
`created_at timestamptz default now()`
