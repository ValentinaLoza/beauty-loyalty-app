-- Beauty Loyalty Production
-- Run this once in Supabase SQL Editor on a NEW project.

begin;

create schema if not exists private;

create table public.businesses (
    id uuid primary key default gen_random_uuid(),
    name varchar(120) not null,
    primary_color_hex char(7) not null default '#8F5E78',
    phone varchar(30),
    logo_url text,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint businesses_color_chk check (primary_color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

create table public.business_members (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'owner',
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint business_members_role_chk check (role in ('owner', 'admin', 'employee')),
    constraint business_members_business_user_uq unique (business_id, user_id)
);

create table public.clients (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete cascade,
    public_token uuid not null default gen_random_uuid(),
    first_name varchar(80) not null,
    last_name varchar(80) not null,
    phone varchar(30),
    email varchar(254),
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint clients_public_token_uq unique (public_token)
);

create table public.services (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete cascade,
    name varchar(120) not null,
    default_price numeric(12,2) not null,
    loyalty_points integer not null default 1,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint services_price_chk check (default_price >= 0),
    constraint services_points_chk check (loyalty_points >= 0)
);

create table public.loyalty_programs (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete cascade,
    points_required integer not null default 5,
    reward_percent numeric(5,2) not null default 20,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint loyalty_points_required_chk check (points_required > 0),
    constraint loyalty_reward_percent_chk check (reward_percent > 0 and reward_percent <= 100)
);

create unique index loyalty_one_active_per_business_uq
on public.loyalty_programs (business_id)
where active = true;

create table public.service_records (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    service_id uuid not null references public.services(id) on delete restrict,
    registered_by uuid references auth.users(id) on delete set null,
    service_name_snapshot varchar(120) not null,
    base_price numeric(12,2) not null,
    discount_amount numeric(12,2) not null default 0,
    final_price numeric(12,2) not null,
    loyalty_points_earned integer not null default 0,
    performed_at timestamptz not null default now(),
    status text not null default 'completed',
    idempotency_key uuid not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint service_records_price_chk check (
      base_price >= 0 and discount_amount >= 0 and discount_amount <= base_price and final_price >= 0
    ),
    constraint service_records_points_chk check (loyalty_points_earned >= 0),
    constraint service_records_status_chk check (status in ('completed', 'voided')),
    constraint service_records_idempotency_uq unique (business_id, idempotency_key)
);

create table public.rewards (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    program_id uuid not null references public.loyalty_programs(id) on delete restrict,
    reward_percent_snapshot numeric(5,2) not null,
    status text not null default 'available',
    issued_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint rewards_percent_chk check (reward_percent_snapshot > 0 and reward_percent_snapshot <= 100),
    constraint rewards_status_chk check (status in ('available', 'redeemed', 'cancelled'))
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
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    constraint loyalty_transaction_type_chk check (
      transaction_type in ('service_earned','reward_issued','service_reversal','reward_reversal','manual_adjustment')
    ),
    constraint loyalty_points_delta_chk check (points_delta <> 0)
);

create unique index loyalty_one_service_credit_uq
on public.loyalty_transactions (service_record_id)
where transaction_type = 'service_earned' and service_record_id is not null;

create unique index loyalty_one_reward_debit_uq
on public.loyalty_transactions (reward_id)
where transaction_type = 'reward_issued' and reward_id is not null;

create table public.reward_redemptions (
    id uuid primary key default gen_random_uuid(),
    reward_id uuid not null unique references public.rewards(id) on delete restrict,
    business_id uuid not null references public.businesses(id) on delete restrict,
    client_id uuid not null references public.clients(id) on delete restrict,
    service_record_id uuid not null unique references public.service_records(id) on delete restrict,
    redeemed_by uuid references auth.users(id) on delete set null,
    discount_amount numeric(12,2) not null,
    redeemed_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    constraint redemptions_discount_chk check (discount_amount >= 0)
);

create index clients_business_idx on public.clients (business_id);
create index services_business_idx on public.services (business_id);
create index service_records_client_date_idx on public.service_records (client_id, performed_at desc);
create index loyalty_client_program_idx on public.loyalty_transactions (client_id, program_id);
create index rewards_client_status_idx on public.rewards (client_id, status);

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

create trigger businesses_updated_at before update on public.businesses for each row execute function private.set_updated_at();
create trigger business_members_updated_at before update on public.business_members for each row execute function private.set_updated_at();
create trigger clients_updated_at before update on public.clients for each row execute function private.set_updated_at();
create trigger services_updated_at before update on public.services for each row execute function private.set_updated_at();
create trigger loyalty_programs_updated_at before update on public.loyalty_programs for each row execute function private.set_updated_at();
create trigger service_records_updated_at before update on public.service_records for each row execute function private.set_updated_at();
create trigger rewards_updated_at before update on public.rewards for each row execute function private.set_updated_at();

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
      and (p_roles is null or bm.role = any(p_roles))
  );
$$;

create or replace view public.client_dashboard
with (security_invoker = true)
as
select
  c.id,
  c.business_id,
  c.public_token,
  c.first_name,
  c.last_name,
  c.phone,
  c.email,
  c.active,
  coalesce((
    select sum(lt.points_delta)
    from public.loyalty_transactions lt
    where lt.client_id = c.id
      and lt.program_id = (
        select lp.id
        from public.loyalty_programs lp
        where lp.business_id = c.business_id and lp.active = true
        limit 1
      )
  ), 0)::integer as points,
  (
    select count(*)
    from public.rewards r
    where r.client_id = c.id and r.status = 'available'
  )::integer as available_rewards,
  (
    select count(*)
    from public.service_records sr
    where sr.client_id = c.id and sr.status = 'completed'
  )::integer as service_count,
  (
    select max(sr.performed_at)
    from public.service_records sr
    where sr.client_id = c.id and sr.status = 'completed'
  ) as last_service_at
from public.clients c
where c.active = true;

alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.clients enable row level security;
alter table public.services enable row level security;
alter table public.loyalty_programs enable row level security;
alter table public.service_records enable row level security;
alter table public.rewards enable row level security;
alter table public.loyalty_transactions enable row level security;
alter table public.reward_redemptions enable row level security;

create policy businesses_select on public.businesses for select to authenticated
using (private.is_business_member(id, null));
create policy businesses_update on public.businesses for update to authenticated
using (private.is_business_member(id, array['owner','admin']::text[]))
with check (private.is_business_member(id, array['owner','admin']::text[]));

create policy members_select on public.business_members for select to authenticated
using (user_id = auth.uid() or private.is_business_member(business_id, array['owner','admin']::text[]));

create policy clients_select on public.clients for select to authenticated
using (private.is_business_member(business_id, null));
create policy clients_insert on public.clients for insert to authenticated
with check (private.is_business_member(business_id, array['owner','admin','employee']::text[]));
create policy clients_update on public.clients for update to authenticated
using (private.is_business_member(business_id, array['owner','admin']::text[]))
with check (private.is_business_member(business_id, array['owner','admin']::text[]));

create policy services_select on public.services for select to authenticated
using (private.is_business_member(business_id, null));
create policy services_insert on public.services for insert to authenticated
with check (private.is_business_member(business_id, array['owner','admin']::text[]));
create policy services_update on public.services for update to authenticated
using (private.is_business_member(business_id, array['owner','admin']::text[]))
with check (private.is_business_member(business_id, array['owner','admin']::text[]));

create policy loyalty_select on public.loyalty_programs for select to authenticated
using (private.is_business_member(business_id, null));
create policy loyalty_update on public.loyalty_programs for update to authenticated
using (private.is_business_member(business_id, array['owner','admin']::text[]))
with check (private.is_business_member(business_id, array['owner','admin']::text[]));

create policy records_select on public.service_records for select to authenticated
using (private.is_business_member(business_id, null));
create policy rewards_select on public.rewards for select to authenticated
using (private.is_business_member(business_id, null));
create policy transactions_select on public.loyalty_transactions for select to authenticated
using (private.is_business_member(business_id, null));
create policy redemptions_select on public.reward_redemptions for select to authenticated
using (private.is_business_member(business_id, null));

create or replace function public.create_business_for_current_user(
  p_name text,
  p_primary_color_hex text default '#8F5E78'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'BUSINESS_NAME_REQUIRED'; end if;
  if p_primary_color_hex !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'INVALID_COLOR'; end if;
  if exists (select 1 from public.business_members where user_id = v_user_id and active = true) then
    raise exception 'BUSINESS_ALREADY_EXISTS';
  end if;

  insert into public.businesses(name, primary_color_hex)
  values (trim(p_name), p_primary_color_hex)
  returning id into v_business_id;

  insert into public.business_members(business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.loyalty_programs(business_id, points_required, reward_percent, active)
  values (v_business_id, 5, 20, true);

  return v_business_id;
end;
$$;

create or replace function public.get_business_metrics(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not private.is_business_member(p_business_id, null) then raise exception 'BUSINESS_ACCESS_DENIED'; end if;
  return jsonb_build_object(
    'client_count', (select count(*) from public.clients c where c.business_id = p_business_id and c.active = true),
    'service_count', (select count(*) from public.service_records sr where sr.business_id = p_business_id and sr.status = 'completed'),
    'available_rewards', (select count(*) from public.rewards r where r.business_id = p_business_id and r.status = 'available'),
    'revenue', coalesce((select sum(sr.final_price) from public.service_records sr where sr.business_id = p_business_id and sr.status = 'completed'), 0)
  );
end;
$$;

create or replace function public.register_service(
  p_business_id uuid,
  p_client_id uuid,
  p_service_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_client public.clients%rowtype;
  v_service public.services%rowtype;
  v_program public.loyalty_programs%rowtype;
  v_existing public.service_records%rowtype;
  v_service_record_id uuid;
  v_reward_id uuid;
  v_balance integer := 0;
  v_rewards jsonb := '[]'::jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if not private.is_business_member(p_business_id, array['owner','admin','employee']::text[]) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  select * into v_client from public.clients where id = p_client_id for update;
  if not found or v_client.business_id <> p_business_id or not v_client.active then raise exception 'CLIENT_INVALID'; end if;

  select * into v_existing from public.service_records
  where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('service_record_id', v_existing.id, 'idempotent_replay', true, 'rewards_issued', '[]'::jsonb);
  end if;

  select * into v_service from public.services where id = p_service_id;
  if not found or v_service.business_id <> p_business_id or not v_service.active then raise exception 'SERVICE_INVALID'; end if;

  select * into v_program from public.loyalty_programs
  where business_id = p_business_id and active = true limit 1;
  if not found then raise exception 'LOYALTY_PROGRAM_NOT_FOUND'; end if;

  insert into public.service_records(
    business_id, client_id, service_id, registered_by, service_name_snapshot,
    base_price, discount_amount, final_price, loyalty_points_earned,
    performed_at, status, idempotency_key
  ) values (
    p_business_id, p_client_id, p_service_id, v_user_id, v_service.name,
    v_service.default_price, 0, v_service.default_price, v_service.loyalty_points,
    now(), 'completed', p_idempotency_key
  ) returning id into v_service_record_id;

  if v_service.loyalty_points > 0 then
    insert into public.loyalty_transactions(
      business_id, client_id, program_id, service_record_id,
      transaction_type, points_delta, created_by
    ) values (
      p_business_id, p_client_id, v_program.id, v_service_record_id,
      'service_earned', v_service.loyalty_points, v_user_id
    );
  end if;

  select coalesce(sum(points_delta), 0)::integer into v_balance
  from public.loyalty_transactions
  where client_id = p_client_id and program_id = v_program.id;

  while v_balance >= v_program.points_required loop
    insert into public.rewards(business_id, client_id, program_id, reward_percent_snapshot, status)
    values (p_business_id, p_client_id, v_program.id, v_program.reward_percent, 'available')
    returning id into v_reward_id;

    insert into public.loyalty_transactions(
      business_id, client_id, program_id, service_record_id, reward_id,
      transaction_type, points_delta, created_by
    ) values (
      p_business_id, p_client_id, v_program.id, v_service_record_id, v_reward_id,
      'reward_issued', -v_program.points_required, v_user_id
    );

    v_balance := v_balance - v_program.points_required;
    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object('id', v_reward_id, 'percent', v_program.reward_percent));
  end loop;

  return jsonb_build_object(
    'service_record_id', v_service_record_id,
    'points_balance', v_balance,
    'rewards_issued', v_rewards,
    'idempotent_replay', false
  );
end;
$$;

create or replace function public.redeem_reward(
  p_business_id uuid,
  p_client_id uuid,
  p_service_id uuid,
  p_reward_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_client public.clients%rowtype;
  v_service public.services%rowtype;
  v_program public.loyalty_programs%rowtype;
  v_reward public.rewards%rowtype;
  v_existing public.service_records%rowtype;
  v_service_record_id uuid;
  v_redemption_id uuid;
  v_new_reward_id uuid;
  v_discount numeric(12,2);
  v_final numeric(12,2);
  v_balance integer := 0;
  v_rewards jsonb := '[]'::jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if not private.is_business_member(p_business_id, array['owner','admin','employee']::text[]) then raise exception 'BUSINESS_ACCESS_DENIED'; end if;

  select * into v_client from public.clients where id = p_client_id for update;
  if not found or v_client.business_id <> p_business_id or not v_client.active then raise exception 'CLIENT_INVALID'; end if;

  select * into v_existing from public.service_records
  where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('service_record_id', v_existing.id, 'idempotent_replay', true, 'rewards_issued', '[]'::jsonb);
  end if;

  select * into v_reward from public.rewards where id = p_reward_id for update;
  if not found or v_reward.business_id <> p_business_id or v_reward.client_id <> p_client_id or v_reward.status <> 'available' then
    raise exception 'REWARD_NOT_AVAILABLE';
  end if;

  select * into v_service from public.services where id = p_service_id;
  if not found or v_service.business_id <> p_business_id or not v_service.active then raise exception 'SERVICE_INVALID'; end if;

  select * into v_program from public.loyalty_programs
  where business_id = p_business_id and active = true limit 1;
  if not found then raise exception 'LOYALTY_PROGRAM_NOT_FOUND'; end if;

  v_discount := round(v_service.default_price * v_reward.reward_percent_snapshot / 100, 2);
  v_discount := least(v_service.default_price, v_discount);
  v_final := greatest(v_service.default_price - v_discount, 0);

  insert into public.service_records(
    business_id, client_id, service_id, registered_by, service_name_snapshot,
    base_price, discount_amount, final_price, loyalty_points_earned,
    performed_at, status, idempotency_key
  ) values (
    p_business_id, p_client_id, p_service_id, v_user_id, v_service.name,
    v_service.default_price, v_discount, v_final, v_service.loyalty_points,
    now(), 'completed', p_idempotency_key
  ) returning id into v_service_record_id;

  insert into public.reward_redemptions(
    reward_id, business_id, client_id, service_record_id, redeemed_by,
    discount_amount, redeemed_at
  ) values (
    v_reward.id, p_business_id, p_client_id, v_service_record_id, v_user_id,
    v_discount, now()
  ) returning id into v_redemption_id;

  update public.rewards set status = 'redeemed' where id = v_reward.id;

  if v_service.loyalty_points > 0 then
    insert into public.loyalty_transactions(
      business_id, client_id, program_id, service_record_id,
      transaction_type, points_delta, created_by
    ) values (
      p_business_id, p_client_id, v_program.id, v_service_record_id,
      'service_earned', v_service.loyalty_points, v_user_id
    );
  end if;

  select coalesce(sum(points_delta), 0)::integer into v_balance
  from public.loyalty_transactions
  where client_id = p_client_id and program_id = v_program.id;

  while v_balance >= v_program.points_required loop
    insert into public.rewards(business_id, client_id, program_id, reward_percent_snapshot, status)
    values (p_business_id, p_client_id, v_program.id, v_program.reward_percent, 'available')
    returning id into v_new_reward_id;

    insert into public.loyalty_transactions(
      business_id, client_id, program_id, service_record_id, reward_id,
      transaction_type, points_delta, created_by
    ) values (
      p_business_id, p_client_id, v_program.id, v_service_record_id, v_new_reward_id,
      'reward_issued', -v_program.points_required, v_user_id
    );

    v_balance := v_balance - v_program.points_required;
    v_rewards := v_rewards || jsonb_build_array(jsonb_build_object('id', v_new_reward_id, 'percent', v_program.reward_percent));
  end loop;

  return jsonb_build_object(
    'service_record_id', v_service_record_id,
    'redemption_id', v_redemption_id,
    'discount_amount', v_discount,
    'final_price', v_final,
    'points_balance', v_balance,
    'rewards_issued', v_rewards,
    'idempotent_replay', false
  );
end;
$$;

create or replace function public.rotate_client_public_token(p_client_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
  v_token uuid;
begin
  select business_id into v_business_id from public.clients where id = p_client_id;
  if not found then raise exception 'CLIENT_NOT_FOUND'; end if;
  if not private.is_business_member(v_business_id, array['owner','admin']::text[]) then raise exception 'BUSINESS_ACCESS_DENIED'; end if;
  update public.clients set public_token = gen_random_uuid()
  where id = p_client_id returning public_token into v_token;
  return v_token;
end;
$$;

create or replace function public.get_public_client_card(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_client public.clients%rowtype;
  v_business public.businesses%rowtype;
  v_program public.loyalty_programs%rowtype;
  v_points integer := 0;
  v_available integer := 0;
  v_history jsonb := '[]'::jsonb;
  v_rewards jsonb := '[]'::jsonb;
begin
  select c.* into v_client
  from public.clients c
  join public.businesses b on b.id = c.business_id
  where c.public_token = p_token and c.active = true and b.active = true;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;

  select * into v_business from public.businesses where id = v_client.business_id;
  select * into v_program from public.loyalty_programs
  where business_id = v_client.business_id and active = true limit 1;

  if found then
    select coalesce(sum(points_delta), 0)::integer into v_points
    from public.loyalty_transactions
    where client_id = v_client.id and program_id = v_program.id;
  end if;

  select count(*)::integer into v_available
  from public.rewards where client_id = v_client.id and status = 'available';

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', sr.id,
      'service_id', sr.service_id,
      'service_name', sr.service_name_snapshot,
      'base_price', sr.base_price,
      'discount_amount', sr.discount_amount,
      'final_price', sr.final_price,
      'points_earned', sr.loyalty_points_earned,
      'performed_at', sr.performed_at
    ) order by sr.performed_at desc), '[]'::jsonb)
  into v_history
  from (
    select * from public.service_records
    where client_id = v_client.id and status = 'completed'
    order by performed_at desc limit 50
  ) sr;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id,
      'percent', r.reward_percent_snapshot,
      'status', r.status,
      'issued_at', r.issued_at,
      'redeemed_at', rr.redeemed_at
    ) order by r.issued_at desc), '[]'::jsonb)
  into v_rewards
  from public.rewards r
  left join public.reward_redemptions rr on rr.reward_id = r.id
  where r.client_id = v_client.id;

  return jsonb_build_object(
    'business', jsonb_build_object(
      'id', v_business.id,
      'name', v_business.name,
      'primary_color_hex', v_business.primary_color_hex,
      'phone', v_business.phone,
      'logo_url', v_business.logo_url
    ),
    'client', jsonb_build_object(
      'id', v_client.id,
      'first_name', v_client.first_name,
      'last_name', v_client.last_name,
      'points', v_points,
      'available_rewards', v_available
    ),
    'loyalty', jsonb_build_object(
      'id', coalesce(v_program.id::text, ''),
      'points_required', coalesce(v_program.points_required, 5),
      'reward_percent', coalesce(v_program.reward_percent, 20)
    ),
    'history', v_history,
    'rewards', v_rewards
  );
end;
$$;

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select, update on public.businesses to authenticated;
grant select on public.business_members to authenticated;
grant select, insert, update on public.clients to authenticated;
grant select, insert, update on public.services to authenticated;
grant select, update on public.loyalty_programs to authenticated;
grant select on public.service_records to authenticated;
grant select on public.rewards to authenticated;
grant select on public.loyalty_transactions to authenticated;
grant select on public.reward_redemptions to authenticated;
grant select on public.client_dashboard to authenticated;

revoke all on function public.create_business_for_current_user(text, text) from public, anon;
grant execute on function public.create_business_for_current_user(text, text) to authenticated;
revoke all on function public.get_business_metrics(uuid) from public, anon;
grant execute on function public.get_business_metrics(uuid) to authenticated;
revoke all on function public.register_service(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.register_service(uuid, uuid, uuid, uuid) to authenticated;
revoke all on function public.redeem_reward(uuid, uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.redeem_reward(uuid, uuid, uuid, uuid, uuid) to authenticated;
revoke all on function public.rotate_client_public_token(uuid) from public, anon;
grant execute on function public.rotate_client_public_token(uuid) to authenticated;
revoke all on function public.get_public_client_card(uuid) from public;
grant execute on function public.get_public_client_card(uuid) to anon, authenticated;

revoke all on function private.set_updated_at() from public;
revoke all on function private.is_business_member(uuid, text[]) from public;

commit;
