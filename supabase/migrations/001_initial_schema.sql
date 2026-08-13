-- ============================================================================
-- Beauty Loyalty App
-- Phase 0.2.3 - Initial Supabase/PostgreSQL schema
-- Migration: 001_initial_schema.sql
--
-- Target: Supabase Postgres
-- Includes:
--   * Core tables
--   * Constraints and indexes
--   * updated_at triggers
--   * auth.users -> profiles trigger
--   * Row Level Security
--   * Grants
--   * Atomic RPC functions:
--       - register_service()
--       - redeem_reward()
--
-- IMPORTANT:
--   This migration assumes Supabase's `auth` schema already exists.
-- ============================================================================

begin;

-- ============================================================================
-- 1. PRIVATE SCHEMA
-- ============================================================================

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ============================================================================
-- 2. TABLES
-- ============================================================================

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    first_name varchar(80) not null,
    last_name varchar(80) not null,
    phone varchar(30),
    avatar_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.businesses (
    id uuid primary key default gen_random_uuid(),
    name varchar(120) not null,
    logo_url text,
    phone varchar(30),
    email varchar(254),
    address text,
    currency_code char(3) not null default 'ARS',
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint businesses_currency_code_chk
        check (currency_code ~ '^[A-Z]{3}$')
);

create table public.business_members (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    user_id uuid not null references public.profiles(id) on delete cascade,
    role text not null,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint business_members_role_chk
        check (role in ('owner', 'admin', 'employee')),
    constraint business_members_business_user_uq
        unique (business_id, user_id)
);

create table public.clients (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    user_id uuid references public.profiles(id) on delete set null,
    first_name varchar(80) not null,
    last_name varchar(80) not null,
    phone varchar(30),
    email varchar(254),
    birth_date date,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint clients_business_user_uq
        unique (business_id, user_id)
);

create table public.services (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    name varchar(120) not null,
    description text,
    default_price numeric(12,2) not null,
    loyalty_points integer not null default 1,
    duration_minutes integer,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint services_default_price_chk
        check (default_price >= 0),
    constraint services_loyalty_points_chk
        check (loyalty_points >= 0),
    constraint services_duration_minutes_chk
        check (duration_minutes is null or duration_minutes > 0)
);

create table public.loyalty_programs (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    name varchar(120) not null,
    points_required integer not null,
    reward_type text not null,
    reward_value numeric(12,2),
    free_service_id uuid references public.services(id) on delete restrict,
    custom_description text,
    expires_after_days integer,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint loyalty_programs_points_required_chk
        check (points_required > 0),

    constraint loyalty_programs_reward_type_chk
        check (
            reward_type in (
                'percentage',
                'fixed_amount',
                'free_service',
                'custom'
            )
        ),

    constraint loyalty_programs_expires_after_days_chk
        check (
            expires_after_days is null
            or expires_after_days > 0
        ),

    constraint loyalty_programs_reward_configuration_chk
        check (
            (
                reward_type = 'percentage'
                and reward_value is not null
                and reward_value between 0 and 100
                and free_service_id is null
            )
            or
            (
                reward_type = 'fixed_amount'
                and reward_value is not null
                and reward_value >= 0
                and free_service_id is null
            )
            or
            (
                reward_type = 'free_service'
                and free_service_id is not null
            )
            or
            (
                reward_type = 'custom'
                and custom_description is not null
                and length(trim(custom_description)) > 0
            )
        )
);

create table public.service_records (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    service_id uuid not null references public.services(id) on delete restrict,
    registered_by uuid references public.profiles(id) on delete set null,

    service_name_snapshot varchar(120) not null,

    base_price numeric(12,2) not null,
    discount_amount numeric(12,2) not null default 0,
    final_price numeric(12,2) not null,
    currency_code char(3) not null,

    loyalty_points_earned integer not null default 0,

    performed_at timestamptz not null,
    notes text,

    status text not null default 'completed',
    voided_at timestamptz,
    voided_by uuid references public.profiles(id) on delete set null,
    void_reason text,

    idempotency_key uuid not null,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint service_records_base_price_chk
        check (base_price >= 0),

    constraint service_records_discount_amount_chk
        check (
            discount_amount >= 0
            and discount_amount <= base_price
        ),

    constraint service_records_final_price_chk
        check (final_price >= 0),

    constraint service_records_currency_code_chk
        check (currency_code ~ '^[A-Z]{3}$'),

    constraint service_records_loyalty_points_chk
        check (loyalty_points_earned >= 0),

    constraint service_records_status_chk
        check (status in ('completed', 'voided')),

    constraint service_records_business_idempotency_uq
        unique (business_id, idempotency_key)
);

create table public.rewards (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    program_id uuid not null references public.loyalty_programs(id) on delete restrict,

    reward_type text not null,
    reward_value numeric(12,2),
    reward_currency_code char(3),
    free_service_id uuid references public.services(id) on delete restrict,
    description_snapshot text,

    status text not null default 'available',

    issued_at timestamptz not null default now(),
    expires_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint rewards_reward_type_chk
        check (
            reward_type in (
                'percentage',
                'fixed_amount',
                'free_service',
                'custom'
            )
        ),

    constraint rewards_status_chk
        check (
            status in (
                'available',
                'redeemed',
                'expired',
                'cancelled'
            )
        ),

    constraint rewards_percentage_value_chk
        check (
            reward_type <> 'percentage'
            or (
                reward_value is not null
                and reward_value between 0 and 100
            )
        ),

    constraint rewards_fixed_value_chk
        check (
            reward_type <> 'fixed_amount'
            or (
                reward_value is not null
                and reward_value >= 0
                and reward_currency_code is not null
            )
        ),

    constraint rewards_free_service_chk
        check (
            reward_type <> 'free_service'
            or free_service_id is not null
        ),

    constraint rewards_currency_code_chk
        check (
            reward_currency_code is null
            or reward_currency_code ~ '^[A-Z]{3}$'
        )
);

create table public.loyalty_transactions (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    program_id uuid not null references public.loyalty_programs(id) on delete restrict,

    service_record_id uuid references public.service_records(id) on delete restrict,
    reward_id uuid references public.rewards(id) on delete restrict,

    transaction_type text not null,
    points_delta integer not null,
    description text,

    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),

    constraint loyalty_transactions_type_chk
        check (
            transaction_type in (
                'service_earned',
                'reward_issued',
                'manual_adjustment',
                'correction',
                'service_reversal',
                'reward_reversal'
            )
        ),

    constraint loyalty_transactions_points_delta_chk
        check (points_delta <> 0)
);

create table public.reward_redemptions (
    id uuid primary key default gen_random_uuid(),
    reward_id uuid not null references public.rewards(id) on delete restrict,
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    service_record_id uuid not null references public.service_records(id) on delete restrict,

    redeemed_by uuid references public.profiles(id) on delete set null,

    discount_amount numeric(12,2) not null default 0,
    currency_code char(3) not null,

    redeemed_at timestamptz not null default now(),
    created_at timestamptz not null default now(),

    constraint reward_redemptions_reward_uq
        unique (reward_id),

    constraint reward_redemptions_service_record_uq
        unique (service_record_id),

    constraint reward_redemptions_discount_amount_chk
        check (discount_amount >= 0),

    constraint reward_redemptions_currency_code_chk
        check (currency_code ~ '^[A-Z]{3}$')
);

-- ============================================================================
-- 3. INDEXES
-- ============================================================================

create index business_members_business_idx
    on public.business_members (business_id);

create index business_members_user_idx
    on public.business_members (user_id);

create index clients_business_idx
    on public.clients (business_id);

create index clients_user_idx
    on public.clients (user_id)
    where user_id is not null;

create index clients_name_idx
    on public.clients (
        business_id,
        lower(last_name),
        lower(first_name)
    );

create index services_business_active_idx
    on public.services (business_id, active);

create unique index loyalty_programs_one_active_per_business_uq
    on public.loyalty_programs (business_id)
    where active = true;

create index service_records_client_performed_idx
    on public.service_records (client_id, performed_at desc);

create index service_records_business_performed_idx
    on public.service_records (business_id, performed_at desc);

create index loyalty_transactions_client_program_created_idx
    on public.loyalty_transactions (
        client_id,
        program_id,
        created_at
    );

create unique index loyalty_transactions_one_service_earned_uq
    on public.loyalty_transactions (service_record_id)
    where (
        transaction_type = 'service_earned'
        and service_record_id is not null
    );

create unique index loyalty_transactions_one_reward_issued_uq
    on public.loyalty_transactions (reward_id)
    where (
        transaction_type = 'reward_issued'
        and reward_id is not null
    );

create index rewards_client_status_idx
    on public.rewards (client_id, status);

create index rewards_business_status_idx
    on public.rewards (business_id, status);

-- ============================================================================
-- 4. UPDATED_AT TRIGGER
-- ============================================================================

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger businesses_set_updated_at
before update on public.businesses
for each row execute function private.set_updated_at();

create trigger business_members_set_updated_at
before update on public.business_members
for each row execute function private.set_updated_at();

create trigger clients_set_updated_at
before update on public.clients
for each row execute function private.set_updated_at();

create trigger services_set_updated_at
before update on public.services
for each row execute function private.set_updated_at();

create trigger loyalty_programs_set_updated_at
before update on public.loyalty_programs
for each row execute function private.set_updated_at();

create trigger service_records_set_updated_at
before update on public.service_records
for each row execute function private.set_updated_at();

create trigger rewards_set_updated_at
before update on public.rewards
for each row execute function private.set_updated_at();

-- ============================================================================
-- 5. AUTH USER -> PROFILE
-- ============================================================================

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
    insert into public.profiles (
        id,
        first_name,
        last_name,
        phone,
        avatar_url
    )
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'first_name', ''),
        coalesce(new.raw_user_meta_data ->> 'last_name', ''),
        new.raw_user_meta_data ->> 'phone',
        new.raw_user_meta_data ->> 'avatar_url'
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

-- ============================================================================
-- 6. PRIVATE RLS HELPERS
-- ============================================================================

create or replace function private.is_business_member(
    p_business_id uuid,
    p_roles text[] default null
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
    select exists (
        select 1
        from public.business_members bm
        where bm.business_id = p_business_id
          and bm.user_id = auth.uid()
          and bm.active = true
          and (
              p_roles is null
              or bm.role = any (p_roles)
          )
    );
$$;

create or replace function private.is_client_of_business(
    p_business_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
    select exists (
        select 1
        from public.clients c
        where c.business_id = p_business_id
          and c.user_id = auth.uid()
          and c.active = true
    );
$$;

create or replace function private.is_own_client(
    p_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
    select exists (
        select 1
        from public.clients c
        where c.id = p_client_id
          and c.user_id = auth.uid()
    );
$$;

create or replace function private.can_view_profile(
    p_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
    select
        auth.uid() = p_profile_id

        or exists (
            select 1
            from public.business_members me
            join public.business_members target
              on target.business_id = me.business_id
            where me.user_id = auth.uid()
              and me.active = true
              and target.user_id = p_profile_id
              and target.active = true
        )

        or exists (
            select 1
            from public.clients c
            join public.business_members target
              on target.business_id = c.business_id
            where c.user_id = auth.uid()
              and c.active = true
              and target.user_id = p_profile_id
              and target.active = true
        );
$$;

revoke all on function private.is_business_member(uuid, text[]) from public;
revoke all on function private.is_client_of_business(uuid) from public;
revoke all on function private.is_own_client(uuid) from public;
revoke all on function private.can_view_profile(uuid) from public;

grant execute on function private.is_business_member(uuid, text[]) to authenticated;
grant execute on function private.is_client_of_business(uuid) to authenticated;
grant execute on function private.is_own_client(uuid) to authenticated;
grant execute on function private.can_view_profile(uuid) to authenticated;

-- ============================================================================
-- 7. ROW LEVEL SECURITY
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.clients enable row level security;
alter table public.services enable row level security;
alter table public.loyalty_programs enable row level security;
alter table public.service_records enable row level security;
alter table public.loyalty_transactions enable row level security;
alter table public.rewards enable row level security;
alter table public.reward_redemptions enable row level security;

-- Profiles

create policy profiles_select_policy
on public.profiles
for select
to authenticated
using (
    private.can_view_profile(id)
);

create policy profiles_update_own_policy
on public.profiles
for update
to authenticated
using (
    id = auth.uid()
)
with check (
    id = auth.uid()
);

-- Businesses

create policy businesses_select_policy
on public.businesses
for select
to authenticated
using (
    private.is_business_member(id, null)
    or private.is_client_of_business(id)
);

create policy businesses_update_admin_policy
on public.businesses
for update
to authenticated
using (
    private.is_business_member(
        id,
        array['owner', 'admin']::text[]
    )
)
with check (
    private.is_business_member(
        id,
        array['owner', 'admin']::text[]
    )
);

-- Business members

create policy business_members_select_policy
on public.business_members
for select
to authenticated
using (
    private.is_business_member(business_id, null)
);

-- Clients

create policy clients_select_policy
on public.clients
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or user_id = auth.uid()
);

create policy clients_insert_admin_policy
on public.clients
for insert
to authenticated
with check (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
);

create policy clients_update_admin_policy
on public.clients
for update
to authenticated
using (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
)
with check (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
);

-- Services

create policy services_select_policy
on public.services
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or private.is_client_of_business(business_id)
);

create policy services_insert_admin_policy
on public.services
for insert
to authenticated
with check (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
);

create policy services_update_admin_policy
on public.services
for update
to authenticated
using (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
)
with check (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
);

-- Loyalty programs

create policy loyalty_programs_select_policy
on public.loyalty_programs
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or private.is_client_of_business(business_id)
);

create policy loyalty_programs_insert_admin_policy
on public.loyalty_programs
for insert
to authenticated
with check (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
);

create policy loyalty_programs_update_admin_policy
on public.loyalty_programs
for update
to authenticated
using (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
)
with check (
    private.is_business_member(
        business_id,
        array['owner', 'admin']::text[]
    )
);

-- Service records: read-only from client API; writes through RPC.

create policy service_records_select_policy
on public.service_records
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or private.is_own_client(client_id)
);

-- Loyalty transactions: read-only from client API; writes through RPC.

create policy loyalty_transactions_select_policy
on public.loyalty_transactions
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or private.is_own_client(client_id)
);

-- Rewards: read-only from client API; writes through RPC.

create policy rewards_select_policy
on public.rewards
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or private.is_own_client(client_id)
);

-- Redemptions: read-only from client API; writes through RPC.

create policy reward_redemptions_select_policy
on public.reward_redemptions
for select
to authenticated
using (
    private.is_business_member(business_id, null)
    or private.is_own_client(client_id)
);

-- ============================================================================
-- 8. TABLE GRANTS
-- ============================================================================

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.businesses from anon, authenticated;
revoke all on table public.business_members from anon, authenticated;
revoke all on table public.clients from anon, authenticated;
revoke all on table public.services from anon, authenticated;
revoke all on table public.loyalty_programs from anon, authenticated;
revoke all on table public.service_records from anon, authenticated;
revoke all on table public.loyalty_transactions from anon, authenticated;
revoke all on table public.rewards from anon, authenticated;
revoke all on table public.reward_redemptions from anon, authenticated;

grant select, update
on table public.profiles
to authenticated;

grant select, update
on table public.businesses
to authenticated;

grant select
on table public.business_members
to authenticated;

grant select, insert, update
on table public.clients
to authenticated;

grant select, insert, update
on table public.services
to authenticated;

grant select, insert, update
on table public.loyalty_programs
to authenticated;

grant select
on table public.service_records
to authenticated;

grant select
on table public.loyalty_transactions
to authenticated;

grant select
on table public.rewards
to authenticated;

grant select
on table public.reward_redemptions
to authenticated;

-- ============================================================================
-- 9. RPC: REGISTER SERVICE
-- ============================================================================

create or replace function public.register_service(
    p_business_id uuid,
    p_client_id uuid,
    p_service_id uuid,
    p_idempotency_key uuid,
    p_base_price numeric default null,
    p_performed_at timestamptz default now(),
    p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();

    v_business public.businesses%rowtype;
    v_client public.clients%rowtype;
    v_service public.services%rowtype;
    v_program public.loyalty_programs%rowtype;
    v_existing public.service_records%rowtype;

    v_service_record_id uuid;
    v_reward_id uuid;

    v_price numeric(12,2);
    v_points_earned integer := 0;
    v_balance integer := 0;

    v_program_id uuid;
    v_points_required integer;

    v_rewards_json jsonb := '[]'::jsonb;
begin
    if v_user_id is null then
        raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
    end if;

    if p_idempotency_key is null then
        raise exception 'IDEMPOTENCY_KEY_REQUIRED' using errcode = 'P0001';
    end if;

    if not private.is_business_member(
        p_business_id,
        array['owner', 'admin', 'employee']::text[]
    ) then
        raise exception 'BUSINESS_ACCESS_DENIED' using errcode = 'P0001';
    end if;

    select *
      into v_business
      from public.businesses
     where id = p_business_id;

    if not found or v_business.active = false then
        raise exception 'BUSINESS_INACTIVE' using errcode = 'P0001';
    end if;

    -- Serialize loyalty operations for this client.
    select *
      into v_client
      from public.clients
     where id = p_client_id
     for update;

    if not found then
        raise exception 'CLIENT_NOT_FOUND' using errcode = 'P0001';
    end if;

    if v_client.business_id <> p_business_id then
        raise exception 'BUSINESS_MISMATCH' using errcode = 'P0001';
    end if;

    if v_client.active = false then
        raise exception 'CLIENT_INACTIVE' using errcode = 'P0001';
    end if;

    -- Idempotent replay check after client lock.
    select *
      into v_existing
      from public.service_records
     where business_id = p_business_id
       and idempotency_key = p_idempotency_key;

    if found then
        if v_existing.client_id <> p_client_id then
            raise exception 'IDEMPOTENCY_KEY_CONFLICT' using errcode = 'P0001';
        end if;

        select lt.program_id
          into v_program_id
          from public.loyalty_transactions lt
         where lt.service_record_id = v_existing.id
           and lt.transaction_type = 'service_earned'
         limit 1;

        if v_program_id is not null then
            select lp.points_required
              into v_points_required
              from public.loyalty_programs lp
             where lp.id = v_program_id;

            select coalesce(sum(lt.points_delta), 0)::integer
              into v_balance
              from public.loyalty_transactions lt
             where lt.client_id = p_client_id
               and lt.program_id = v_program_id;
        end if;

        select coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'id', r.id,
                    'type', r.reward_type,
                    'value', r.reward_value,
                    'status', r.status
                )
                order by r.issued_at
            ),
            '[]'::jsonb
        )
          into v_rewards_json
          from public.loyalty_transactions lt
          join public.rewards r
            on r.id = lt.reward_id
         where lt.service_record_id = v_existing.id
           and lt.transaction_type = 'reward_issued';

        return jsonb_build_object(
            'service_record_id', v_existing.id,
            'points_earned', v_existing.loyalty_points_earned,
            'points_balance', coalesce(v_balance, 0),
            'points_required', v_points_required,
            'rewards_issued', v_rewards_json,
            'idempotent_replay', true
        );
    end if;

    select *
      into v_service
      from public.services
     where id = p_service_id;

    if not found then
        raise exception 'SERVICE_NOT_FOUND' using errcode = 'P0001';
    end if;

    if v_service.business_id <> p_business_id then
        raise exception 'BUSINESS_MISMATCH' using errcode = 'P0001';
    end if;

    if v_service.active = false then
        raise exception 'SERVICE_INACTIVE' using errcode = 'P0001';
    end if;

    v_price := coalesce(p_base_price, v_service.default_price);

    if v_price is null or v_price < 0 then
        raise exception 'INVALID_PRICE' using errcode = 'P0001';
    end if;

    -- At most one active program is enforced by a partial unique index.
    select *
      into v_program
      from public.loyalty_programs
     where business_id = p_business_id
       and active = true
     limit 1;

    if found then
        v_points_earned := v_service.loyalty_points;
        v_program_id := v_program.id;
        v_points_required := v_program.points_required;
    else
        v_points_earned := 0;
        v_program_id := null;
        v_points_required := null;
    end if;

    insert into public.service_records (
        business_id,
        client_id,
        service_id,
        registered_by,
        service_name_snapshot,
        base_price,
        discount_amount,
        final_price,
        currency_code,
        loyalty_points_earned,
        performed_at,
        notes,
        status,
        idempotency_key
    )
    values (
        p_business_id,
        p_client_id,
        p_service_id,
        v_user_id,
        v_service.name,
        v_price,
        0,
        v_price,
        v_business.currency_code,
        v_points_earned,
        coalesce(p_performed_at, now()),
        p_notes,
        'completed',
        p_idempotency_key
    )
    returning id into v_service_record_id;

    if v_program_id is not null and v_points_earned > 0 then

        insert into public.loyalty_transactions (
            business_id,
            client_id,
            program_id,
            service_record_id,
            transaction_type,
            points_delta,
            description,
            created_by
        )
        values (
            p_business_id,
            p_client_id,
            v_program_id,
            v_service_record_id,
            'service_earned',
            v_points_earned,
            'Points earned from service',
            v_user_id
        );

        select coalesce(sum(points_delta), 0)::integer
          into v_balance
          from public.loyalty_transactions
         where client_id = p_client_id
           and program_id = v_program_id;

        while v_balance >= v_program.points_required loop

            insert into public.rewards (
                business_id,
                client_id,
                program_id,
                reward_type,
                reward_value,
                reward_currency_code,
                free_service_id,
                description_snapshot,
                status,
                issued_at,
                expires_at
            )
            values (
                p_business_id,
                p_client_id,
                v_program.id,
                v_program.reward_type,
                v_program.reward_value,
                case
                    when v_program.reward_type = 'fixed_amount'
                        then v_business.currency_code
                    else null
                end,
                v_program.free_service_id,
                coalesce(
                    v_program.custom_description,
                    case
                        when v_program.reward_type = 'percentage'
                            then v_program.reward_value::text || '% OFF'
                        when v_program.reward_type = 'fixed_amount'
                            then v_program.reward_value::text || ' OFF'
                        when v_program.reward_type = 'free_service'
                            then 'Free service'
                        else 'Reward'
                    end
                ),
                'available',
                now(),
                case
                    when v_program.expires_after_days is null
                        then null
                    else now() + make_interval(days => v_program.expires_after_days)
                end
            )
            returning id into v_reward_id;

            insert into public.loyalty_transactions (
                business_id,
                client_id,
                program_id,
                service_record_id,
                reward_id,
                transaction_type,
                points_delta,
                description,
                created_by
            )
            values (
                p_business_id,
                p_client_id,
                v_program.id,
                v_service_record_id,
                v_reward_id,
                'reward_issued',
                -v_program.points_required,
                'Points consumed to issue reward',
                v_user_id
            );

            v_balance := v_balance - v_program.points_required;

            v_rewards_json :=
                v_rewards_json ||
                jsonb_build_array(
                    jsonb_build_object(
                        'id', v_reward_id,
                        'type', v_program.reward_type,
                        'value', v_program.reward_value,
                        'status', 'available'
                    )
                );
        end loop;
    else
        v_balance := 0;
    end if;

    return jsonb_build_object(
        'service_record_id', v_service_record_id,
        'points_earned', v_points_earned,
        'points_balance', v_balance,
        'points_required', v_points_required,
        'rewards_issued', v_rewards_json,
        'idempotent_replay', false
    );
end;
$$;

revoke all on function public.register_service(
    uuid,
    uuid,
    uuid,
    uuid,
    numeric,
    timestamptz,
    text
) from public, anon;

grant execute on function public.register_service(
    uuid,
    uuid,
    uuid,
    uuid,
    numeric,
    timestamptz,
    text
) to authenticated;

-- ============================================================================
-- 10. RPC: REDEEM REWARD + REGISTER SERVICE ATOMICALLY
-- ============================================================================

create or replace function public.redeem_reward(
    p_business_id uuid,
    p_client_id uuid,
    p_service_id uuid,
    p_reward_id uuid,
    p_idempotency_key uuid,
    p_base_price numeric default null,
    p_performed_at timestamptz default now(),
    p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();

    v_business public.businesses%rowtype;
    v_client public.clients%rowtype;
    v_service public.services%rowtype;
    v_program public.loyalty_programs%rowtype;
    v_reward public.rewards%rowtype;
    v_existing public.service_records%rowtype;
    v_existing_redemption public.reward_redemptions%rowtype;

    v_service_record_id uuid;
    v_redemption_id uuid;
    v_new_reward_id uuid;

    v_price numeric(12,2);
    v_discount numeric(12,2);
    v_final numeric(12,2);

    v_points_earned integer := 0;
    v_balance integer := 0;
    v_points_required integer;

    v_rewards_json jsonb := '[]'::jsonb;
begin
    if v_user_id is null then
        raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
    end if;

    if p_idempotency_key is null then
        raise exception 'IDEMPOTENCY_KEY_REQUIRED' using errcode = 'P0001';
    end if;

    if not private.is_business_member(
        p_business_id,
        array['owner', 'admin', 'employee']::text[]
    ) then
        raise exception 'BUSINESS_ACCESS_DENIED' using errcode = 'P0001';
    end if;

    select *
      into v_business
      from public.businesses
     where id = p_business_id;

    if not found or v_business.active = false then
        raise exception 'BUSINESS_INACTIVE' using errcode = 'P0001';
    end if;

    -- Lock order is always client -> reward.
    select *
      into v_client
      from public.clients
     where id = p_client_id
     for update;

    if not found then
        raise exception 'CLIENT_NOT_FOUND' using errcode = 'P0001';
    end if;

    if v_client.business_id <> p_business_id then
        raise exception 'BUSINESS_MISMATCH' using errcode = 'P0001';
    end if;

    if v_client.active = false then
        raise exception 'CLIENT_INACTIVE' using errcode = 'P0001';
    end if;

    -- Idempotent replay.
    select *
      into v_existing
      from public.service_records
     where business_id = p_business_id
       and idempotency_key = p_idempotency_key;

    if found then
        if v_existing.client_id <> p_client_id then
            raise exception 'IDEMPOTENCY_KEY_CONFLICT' using errcode = 'P0001';
        end if;

        select *
          into v_existing_redemption
          from public.reward_redemptions
         where service_record_id = v_existing.id;

        if not found then
            raise exception 'IDEMPOTENCY_KEY_CONFLICT' using errcode = 'P0001';
        end if;

        if v_existing_redemption.reward_id <> p_reward_id then
            raise exception 'IDEMPOTENCY_KEY_CONFLICT' using errcode = 'P0001';
        end if;

        select lp.points_required,
               coalesce(sum(lt.points_delta), 0)::integer
          into v_points_required, v_balance
          from public.loyalty_transactions src
          join public.loyalty_programs lp
            on lp.id = src.program_id
          left join public.loyalty_transactions lt
            on lt.client_id = p_client_id
           and lt.program_id = src.program_id
         where src.service_record_id = v_existing.id
           and src.transaction_type = 'service_earned'
         group by lp.points_required
         limit 1;

        select coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'id', r.id,
                    'type', r.reward_type,
                    'value', r.reward_value,
                    'status', r.status
                )
                order by r.issued_at
            ),
            '[]'::jsonb
        )
          into v_rewards_json
          from public.loyalty_transactions lt
          join public.rewards r
            on r.id = lt.reward_id
         where lt.service_record_id = v_existing.id
           and lt.transaction_type = 'reward_issued';

        return jsonb_build_object(
            'service_record_id', v_existing.id,
            'redemption_id', v_existing_redemption.id,
            'reward_id', v_existing_redemption.reward_id,
            'base_price', v_existing.base_price,
            'discount_amount', v_existing.discount_amount,
            'final_price', v_existing.final_price,
            'points_earned', v_existing.loyalty_points_earned,
            'points_balance', coalesce(v_balance, 0),
            'points_required', v_points_required,
            'rewards_issued', v_rewards_json,
            'idempotent_replay', true
        );
    end if;

    select *
      into v_reward
      from public.rewards
     where id = p_reward_id
     for update;

    if not found then
        raise exception 'REWARD_NOT_FOUND' using errcode = 'P0001';
    end if;

    if v_reward.business_id <> p_business_id
       or v_reward.client_id <> p_client_id then
        raise exception 'BUSINESS_MISMATCH' using errcode = 'P0001';
    end if;

    if v_reward.status <> 'available' then
        raise exception 'REWARD_NOT_AVAILABLE' using errcode = 'P0001';
    end if;

    if v_reward.expires_at is not null
       and v_reward.expires_at <= now() then
        raise exception 'REWARD_EXPIRED' using errcode = 'P0001';
    end if;

    select *
      into v_service
      from public.services
     where id = p_service_id;

    if not found then
        raise exception 'SERVICE_NOT_FOUND' using errcode = 'P0001';
    end if;

    if v_service.business_id <> p_business_id then
        raise exception 'BUSINESS_MISMATCH' using errcode = 'P0001';
    end if;

    if v_service.active = false then
        raise exception 'SERVICE_INACTIVE' using errcode = 'P0001';
    end if;

    v_price := coalesce(p_base_price, v_service.default_price);

    if v_price is null or v_price < 0 then
        raise exception 'INVALID_PRICE' using errcode = 'P0001';
    end if;

    case v_reward.reward_type

        when 'percentage' then
            v_discount := round(
                v_price * v_reward.reward_value / 100,
                2
            );

        when 'fixed_amount' then
            if v_reward.reward_currency_code is not null
               and v_reward.reward_currency_code <> v_business.currency_code then
                raise exception 'REWARD_CURRENCY_MISMATCH'
                    using errcode = 'P0001';
            end if;

            v_discount := least(
                v_price,
                v_reward.reward_value
            );

        when 'free_service' then
            if v_reward.free_service_id <> p_service_id then
                raise exception 'REWARD_NOT_VALID_FOR_SERVICE'
                    using errcode = 'P0001';
            end if;

            v_discount := v_price;

        when 'custom' then
            raise exception 'CUSTOM_REWARD_UNSUPPORTED'
                using errcode = 'P0001';

        else
            raise exception 'REWARD_NOT_AVAILABLE'
                using errcode = 'P0001';
    end case;

    v_discount := least(v_price, greatest(v_discount, 0));
    v_final := greatest(v_price - v_discount, 0);

    -- Current active loyalty program governs points for this new service.
    select *
      into v_program
      from public.loyalty_programs
     where business_id = p_business_id
       and active = true
     limit 1;

    if found then
        v_points_earned := v_service.loyalty_points;
        v_points_required := v_program.points_required;
    else
        v_points_earned := 0;
        v_points_required := null;
    end if;

    insert into public.service_records (
        business_id,
        client_id,
        service_id,
        registered_by,
        service_name_snapshot,
        base_price,
        discount_amount,
        final_price,
        currency_code,
        loyalty_points_earned,
        performed_at,
        notes,
        status,
        idempotency_key
    )
    values (
        p_business_id,
        p_client_id,
        p_service_id,
        v_user_id,
        v_service.name,
        v_price,
        v_discount,
        v_final,
        v_business.currency_code,
        v_points_earned,
        coalesce(p_performed_at, now()),
        p_notes,
        'completed',
        p_idempotency_key
    )
    returning id into v_service_record_id;

    insert into public.reward_redemptions (
        reward_id,
        business_id,
        client_id,
        service_record_id,
        redeemed_by,
        discount_amount,
        currency_code,
        redeemed_at
    )
    values (
        v_reward.id,
        p_business_id,
        p_client_id,
        v_service_record_id,
        v_user_id,
        v_discount,
        v_business.currency_code,
        now()
    )
    returning id into v_redemption_id;

    update public.rewards
       set status = 'redeemed'
     where id = v_reward.id;

    if v_program.id is not null and v_points_earned > 0 then

        insert into public.loyalty_transactions (
            business_id,
            client_id,
            program_id,
            service_record_id,
            transaction_type,
            points_delta,
            description,
            created_by
        )
        values (
            p_business_id,
            p_client_id,
            v_program.id,
            v_service_record_id,
            'service_earned',
            v_points_earned,
            'Points earned from service with reward redemption',
            v_user_id
        );

        select coalesce(sum(points_delta), 0)::integer
          into v_balance
          from public.loyalty_transactions
         where client_id = p_client_id
           and program_id = v_program.id;

        while v_balance >= v_program.points_required loop

            insert into public.rewards (
                business_id,
                client_id,
                program_id,
                reward_type,
                reward_value,
                reward_currency_code,
                free_service_id,
                description_snapshot,
                status,
                issued_at,
                expires_at
            )
            values (
                p_business_id,
                p_client_id,
                v_program.id,
                v_program.reward_type,
                v_program.reward_value,
                case
                    when v_program.reward_type = 'fixed_amount'
                        then v_business.currency_code
                    else null
                end,
                v_program.free_service_id,
                coalesce(
                    v_program.custom_description,
                    case
                        when v_program.reward_type = 'percentage'
                            then v_program.reward_value::text || '% OFF'
                        when v_program.reward_type = 'fixed_amount'
                            then v_program.reward_value::text || ' OFF'
                        when v_program.reward_type = 'free_service'
                            then 'Free service'
                        else 'Reward'
                    end
                ),
                'available',
                now(),
                case
                    when v_program.expires_after_days is null
                        then null
                    else now() + make_interval(days => v_program.expires_after_days)
                end
            )
            returning id into v_new_reward_id;

            insert into public.loyalty_transactions (
                business_id,
                client_id,
                program_id,
                service_record_id,
                reward_id,
                transaction_type,
                points_delta,
                description,
                created_by
            )
            values (
                p_business_id,
                p_client_id,
                v_program.id,
                v_service_record_id,
                v_new_reward_id,
                'reward_issued',
                -v_program.points_required,
                'Points consumed to issue reward',
                v_user_id
            );

            v_balance := v_balance - v_program.points_required;

            v_rewards_json :=
                v_rewards_json ||
                jsonb_build_array(
                    jsonb_build_object(
                        'id', v_new_reward_id,
                        'type', v_program.reward_type,
                        'value', v_program.reward_value,
                        'status', 'available'
                    )
                );
        end loop;
    else
        v_balance := 0;
    end if;

    return jsonb_build_object(
        'service_record_id', v_service_record_id,
        'redemption_id', v_redemption_id,
        'reward_id', v_reward.id,
        'base_price', v_price,
        'discount_amount', v_discount,
        'final_price', v_final,
        'points_earned', v_points_earned,
        'points_balance', v_balance,
        'points_required', v_points_required,
        'rewards_issued', v_rewards_json,
        'idempotent_replay', false
    );
end;
$$;

revoke all on function public.redeem_reward(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    numeric,
    timestamptz,
    text
) from public, anon;

grant execute on function public.redeem_reward(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    numeric,
    timestamptz,
    text
) to authenticated;

-- ============================================================================
-- 11. PROTECT INTERNAL/TRIGGER FUNCTIONS
-- ============================================================================

revoke all on function private.set_updated_at() from public;
revoke all on function private.handle_new_user() from public;

-- ============================================================================
-- END
-- ============================================================================

commit;
