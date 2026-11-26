-- Bellamia v1.5 — Web Push Notifications
-- Requiere v1.4 aplicada.
--
-- Arquitectura:
-- push_endpoints        = dispositivo/navegador físico
-- push_bindings         = a quién representa ese dispositivo (admin/clienta)
-- notification_outbox   = eventos pendientes para enviar
-- notification_delivery_log = auditoría de entregas
--
-- Esto permite que un mismo navegador de prueba pueda estar asociado
-- tanto a la administradora como a una clienta sin duplicar las claves push.

begin;

create table if not exists public.push_endpoints (
  id uuid primary key default gen_random_uuid(),
  endpoint text not null unique,
  p256dh_key text not null,
  auth_key text not null,
  device_label text,
  enabled boolean not null default true,
  failure_count integer not null default 0,
  last_success_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.push_bindings (
  id uuid primary key default gen_random_uuid(),
  endpoint_id uuid not null
    references public.push_endpoints(id)
    on delete cascade,
  business_id uuid not null
    references public.businesses(id)
    on delete cascade,
  recipient_kind text not null,
  admin_user_id uuid
    references auth.users(id)
    on delete cascade,
  client_id uuid
    references public.clients(id)
    on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint push_bindings_kind_chk
    check (recipient_kind in ('admin','client')),

  constraint push_bindings_owner_chk
    check (
      (
        recipient_kind = 'admin'
        and admin_user_id is not null
        and client_id is null
      )
      or
      (
        recipient_kind = 'client'
        and client_id is not null
        and admin_user_id is null
      )
    )
);

create unique index if not exists
push_bindings_admin_uq
on public.push_bindings (
  endpoint_id,
  admin_user_id
)
where recipient_kind = 'admin';

create unique index if not exists
push_bindings_client_uq
on public.push_bindings (
  endpoint_id,
  client_id
)
where recipient_kind = 'client';

create index if not exists push_bindings_business_idx
on public.push_bindings (
  business_id,
  recipient_kind,
  enabled
);

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null
    references public.businesses(id)
    on delete cascade,
  audience text not null,
  client_id uuid
    references public.clients(id)
    on delete cascade,
  event_type text not null,
  dedupe_key text not null unique,
  title text not null,
  body text not null,
  target_path text not null default '/',
  scheduled_for timestamptz not null default now(),
  processed_at timestamptz,
  delivered_count integer not null default 0,
  failed_count integer not null default 0,
  created_at timestamptz not null default now(),

  constraint notification_outbox_audience_chk
    check (audience in ('admin','client')),

  constraint notification_outbox_client_chk
    check (
      audience = 'admin'
      or client_id is not null
    )
);

create index if not exists notification_outbox_pending_idx
on public.notification_outbox (
  scheduled_for,
  processed_at
);

create table if not exists public.notification_delivery_log (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null
    references public.notification_outbox(id)
    on delete cascade,
  endpoint_id uuid
    references public.push_endpoints(id)
    on delete set null,
  http_status integer,
  status text not null,
  error_message text,
  attempted_at timestamptz not null default now(),

  constraint notification_delivery_status_chk
    check (
      status in (
        'sent',
        'failed',
        'expired',
        'no_subscription'
      )
    )
);

alter table public.push_endpoints enable row level security;
alter table public.push_bindings enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.notification_delivery_log enable row level security;

-- No direct browser access. Everything goes through controlled RPCs.
revoke all on public.push_endpoints
from anon, authenticated;

revoke all on public.push_bindings
from anon, authenticated;

revoke all on public.notification_outbox
from anon, authenticated;

revoke all on public.notification_delivery_log
from anon, authenticated;

drop trigger if exists push_endpoints_updated_at
on public.push_endpoints;

create trigger push_endpoints_updated_at
before update on public.push_endpoints
for each row
execute function private.set_updated_at();

drop trigger if exists push_bindings_updated_at
on public.push_bindings;

create trigger push_bindings_updated_at
before update on public.push_bindings
for each row
execute function private.set_updated_at();

-- ============================================================================
-- REGISTRO DE DISPOSITIVOS
-- ============================================================================

create or replace function public.register_admin_push_subscription(
  p_endpoint text,
  p_p256dh_key text,
  p_auth_key text,
  p_device_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
  v_endpoint_id uuid;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select bm.business_id
  into v_business_id
  from public.business_members bm
  join public.businesses b
    on b.id = bm.business_id
  where bm.user_id = v_user_id
    and bm.active = true
    and b.active = true
  limit 1;

  if v_business_id is null then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  insert into public.push_endpoints (
    endpoint,
    p256dh_key,
    auth_key,
    device_label,
    enabled,
    failure_count
  )
  values (
    p_endpoint,
    p_p256dh_key,
    p_auth_key,
    p_device_label,
    true,
    0
  )
  on conflict (endpoint)
  do update set
    p256dh_key = excluded.p256dh_key,
    auth_key = excluded.auth_key,
    device_label = excluded.device_label,
    enabled = true,
    failure_count = 0
  returning id into v_endpoint_id;

  insert into public.push_bindings (
    endpoint_id,
    business_id,
    recipient_kind,
    admin_user_id,
    client_id,
    enabled
  )
  values (
    v_endpoint_id,
    v_business_id,
    'admin',
    v_user_id,
    null,
    true
  )
  on conflict (
    endpoint_id,
    admin_user_id
  )
  where recipient_kind = 'admin'
  do update set
    business_id = excluded.business_id,
    enabled = true;

  return v_endpoint_id;
end;
$$;

create or replace function public.register_client_push_subscription(
  p_token uuid,
  p_endpoint text,
  p_p256dh_key text,
  p_auth_key text,
  p_device_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_client public.clients%rowtype;
  v_endpoint_id uuid;
begin
  select *
  into v_client
  from public.clients
  where public_token = p_token
    and active = true
    and archived_at is null;

  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;

  insert into public.push_endpoints (
    endpoint,
    p256dh_key,
    auth_key,
    device_label,
    enabled,
    failure_count
  )
  values (
    p_endpoint,
    p_p256dh_key,
    p_auth_key,
    p_device_label,
    true,
    0
  )
  on conflict (endpoint)
  do update set
    p256dh_key = excluded.p256dh_key,
    auth_key = excluded.auth_key,
    device_label = excluded.device_label,
    enabled = true,
    failure_count = 0
  returning id into v_endpoint_id;

  insert into public.push_bindings (
    endpoint_id,
    business_id,
    recipient_kind,
    admin_user_id,
    client_id,
    enabled
  )
  values (
    v_endpoint_id,
    v_client.business_id,
    'client',
    null,
    v_client.id,
    true
  )
  on conflict (
    endpoint_id,
    client_id
  )
  where recipient_kind = 'client'
  do update set
    business_id = excluded.business_id,
    enabled = true;

  return v_endpoint_id;
end;
$$;

-- ============================================================================
-- OUTBOX HELPERS
-- ============================================================================

create or replace function private.enqueue_push(
  p_business_id uuid,
  p_audience text,
  p_client_id uuid,
  p_event_type text,
  p_dedupe_key text,
  p_title text,
  p_body text,
  p_target_path text,
  p_scheduled_for timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_id uuid;
begin
  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path,
    scheduled_for
  )
  values (
    p_business_id,
    p_audience,
    p_client_id,
    p_event_type,
    p_dedupe_key,
    p_title,
    p_body,
    p_target_path,
    p_scheduled_for
  )
  on conflict (dedupe_key)
  do nothing
  returning id into v_id;

  return v_id;
end;
$$;

-- ============================================================================
-- EVENTOS DE TURNOS
-- ============================================================================

create or replace function private.push_appointment_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_client public.clients%rowtype;
  v_service public.services%rowtype;
  v_local_time text;
begin
  select *
  into v_client
  from public.clients
  where id = new.client_id;

  select *
  into v_service
  from public.services
  where id = new.service_id;

  v_local_time :=
    to_char(
      new.starts_at
        at time zone 'America/Argentina/Buenos_Aires',
      'DD/MM/YYYY HH24:MI'
    );

  if tg_op = 'INSERT' then

    if new.source = 'client'
       and new.status = 'requested' then

      perform private.enqueue_push(
        new.business_id,
        'admin',
        null,
        'appointment_requested',
        'appointment-requested:' || new.id::text,
        'Nuevo turno solicitado',
        trim(v_client.first_name || ' ' || v_client.last_name)
          || ' pidió ' || v_service.name
          || ' para el ' || v_local_time || '.',
        '/admin/appointments'
      );

    elsif new.source = 'admin'
          and new.status = 'confirmed' then

      perform private.enqueue_push(
        new.business_id,
        'client',
        new.client_id,
        'appointment_created',
        'appointment-created:' || new.id::text,
        'Nuevo turno confirmado ✨',
        v_service.name || ' · ' || v_local_time,
        '/c/' || v_client.public_token::text
      );
    end if;

    return new;
  end if;

  if tg_op = 'UPDATE' then

    if old.status is distinct from new.status then

      if new.status = 'confirmed' then
        perform private.enqueue_push(
          new.business_id,
          'client',
          new.client_id,
          'appointment_confirmed',
          'appointment-confirmed:' || new.id::text
            || ':' || extract(epoch from new.updated_at)::bigint::text,
          'Tu turno fue confirmado ✨',
          v_service.name || ' · ' || v_local_time,
          '/c/' || v_client.public_token::text
        );

      elsif new.status = 'cancelled' then
        perform private.enqueue_push(
          new.business_id,
          'client',
          new.client_id,
          'appointment_cancelled',
          'appointment-cancelled:' || new.id::text
            || ':' || extract(epoch from new.updated_at)::bigint::text,
          'Tu turno fue cancelado',
          v_service.name || ' · ' || v_local_time,
          '/c/' || v_client.public_token::text
        );
      end if;

    elsif (
      old.starts_at is distinct from new.starts_at
      or old.service_id is distinct from new.service_id
    )
    and new.status in ('requested','confirmed') then

      perform private.enqueue_push(
        new.business_id,
        'client',
        new.client_id,
        'appointment_updated',
        'appointment-updated:' || new.id::text
          || ':' || extract(epoch from new.updated_at)::bigint::text,
        'Tu turno fue actualizado',
        v_service.name || ' · ' || v_local_time,
        '/c/' || v_client.public_token::text
      );

    end if;

    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists push_appointment_events
on public.appointments;

create trigger push_appointment_events
after insert or update
on public.appointments
for each row
execute function private.push_appointment_event();

-- ============================================================================
-- BENEFICIO DESBLOQUEADO
-- ============================================================================

create or replace function private.push_reward_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_client public.clients%rowtype;
begin
  if new.status <> 'available' then
    return new;
  end if;

  select *
  into v_client
  from public.clients
  where id = new.client_id;

  perform private.enqueue_push(
    new.business_id,
    'client',
    new.client_id,
    'reward_unlocked',
    'reward-unlocked:' || new.id::text,
    '¡Desbloqueaste un beneficio! 🎁',
    'Tenés '
      || trim(to_char(
        new.reward_percent_snapshot,
        'FM999990D##'
      ))
      || '% OFF disponible.',
    '/c/' || v_client.public_token::text
  );

  return new;
end;
$$;

drop trigger if exists push_reward_events
on public.rewards;

create trigger push_reward_events
after insert
on public.rewards
for each row
execute function private.push_reward_event();

-- ============================================================================
-- RECORDATORIOS PROGRAMADOS
-- Llamar esta función 1 vez por hora con Supabase Cron.
-- ============================================================================

create or replace function public.enqueue_scheduled_push_notifications()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_reward_client_count integer := 0;
  v_reward_admin_count integer := 0;
  v_appointment_count integer := 0;
begin
  -- Primer recordatorio: beneficio disponible hace 5 días, sin turno futuro.
  with candidates as (
    select
      r.id as reward_id,
      r.business_id,
      r.client_id,
      r.reward_percent_snapshot,
      c.first_name,
      c.last_name,
      c.public_token
    from public.rewards r
    join public.clients c
      on c.id = r.client_id
    where r.status = 'available'
      and r.issued_at <= now() - interval '5 days'
      and c.active = true
      and c.archived_at is null
      and not exists (
        select 1
        from public.appointments a
        where a.client_id = r.client_id
          and a.starts_at > now()
          and a.status in ('requested','confirmed')
      )
  )
  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path,
    scheduled_for
  )
  select
    business_id,
    'client',
    client_id,
    'reward_reminder_5d',
    'reward-reminder-5d-client:' || reward_id::text,
    'Tu beneficio te está esperando ✨',
    'Tenés '
      || trim(to_char(
        reward_percent_snapshot,
        'FM999990D##'
      ))
      || '% OFF disponible. Reservá tu turno para aprovecharlo.',
    '/c/' || public_token::text,
    now()
  from candidates
  on conflict (dedupe_key) do nothing;

  get diagnostics v_reward_client_count = row_count;

  with candidates as (
    select
      r.id as reward_id,
      r.business_id,
      r.client_id,
      r.reward_percent_snapshot,
      c.first_name,
      c.last_name
    from public.rewards r
    join public.clients c
      on c.id = r.client_id
    where r.status = 'available'
      and r.issued_at <= now() - interval '5 days'
      and c.active = true
      and c.archived_at is null
      and not exists (
        select 1
        from public.appointments a
        where a.client_id = r.client_id
          and a.starts_at > now()
          and a.status in ('requested','confirmed')
      )
  )
  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path,
    scheduled_for
  )
  select
    business_id,
    'admin',
    null,
    'reward_reminder_5d_admin',
    'reward-reminder-5d-admin:' || reward_id::text,
    'Beneficio sin turno',
    trim(first_name || ' ' || last_name)
      || ' tiene un beneficio disponible y todavía no reservó.',
    '/admin/clients/' || client_id::text,
    now()
  from candidates
  on conflict (dedupe_key) do nothing;

  get diagnostics v_reward_admin_count = row_count;

  -- Segundo recordatorio a los 12 días.
  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path,
    scheduled_for
  )
  select
    r.business_id,
    'client',
    r.client_id,
    'reward_reminder_12d',
    'reward-reminder-12d-client:' || r.id::text,
    'Todavía tenés tu beneficio disponible 🎁',
    'Si querés usar tu '
      || trim(to_char(
        r.reward_percent_snapshot,
        'FM999990D##'
      ))
      || '% OFF, podés pedir tu turno desde la tarjeta.',
    '/c/' || c.public_token::text,
    now()
  from public.rewards r
  join public.clients c
    on c.id = r.client_id
  where r.status = 'available'
    and r.issued_at <= now() - interval '12 days'
    and c.active = true
    and c.archived_at is null
    and not exists (
      select 1
      from public.appointments a
      where a.client_id = r.client_id
        and a.starts_at > now()
        and a.status in ('requested','confirmed')
    )
  on conflict (dedupe_key) do nothing;

  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path,
    scheduled_for
  )
  select
    r.business_id,
    'admin',
    null,
    'reward_reminder_12d_admin',
    'reward-reminder-12d-admin:' || r.id::text,
    'Beneficio aún sin canjear',
    trim(c.first_name || ' ' || c.last_name)
      || ' sigue sin reservar turno para usar su beneficio.',
    '/admin/clients/' || r.client_id::text,
    now()
  from public.rewards r
  join public.clients c
    on c.id = r.client_id
  where r.status = 'available'
    and r.issued_at <= now() - interval '12 days'
    and c.active = true
    and c.archived_at is null
    and not exists (
      select 1
      from public.appointments a
      where a.client_id = r.client_id
        and a.starts_at > now()
        and a.status in ('requested','confirmed')
    )
  on conflict (dedupe_key) do nothing;

  -- Recordatorio de turno aproximadamente 24 h antes.
  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path,
    scheduled_for
  )
  select
    a.business_id,
    'client',
    a.client_id,
    'appointment_24h',
    'appointment-24h:' || a.id::text
      || ':' || to_char(
        a.starts_at at time zone 'UTC',
        'YYYYMMDDHH24MI'
      ),
    'Recordatorio de tu turno ✨',
    s.name || ' · '
      || to_char(
        a.starts_at
          at time zone 'America/Argentina/Buenos_Aires',
        'DD/MM/YYYY HH24:MI'
      ),
    '/c/' || c.public_token::text,
    now()
  from public.appointments a
  join public.clients c
    on c.id = a.client_id
  join public.services s
    on s.id = a.service_id
  where a.status = 'confirmed'
    and a.starts_at >= now() + interval '23 hours'
    and a.starts_at <  now() + interval '25 hours'
    and c.active = true
    and c.archived_at is null
  on conflict (dedupe_key) do nothing;

  get diagnostics v_appointment_count = row_count;

  return jsonb_build_object(
    'reward_client_first_reminders',
      v_reward_client_count,
    'reward_admin_first_reminders',
      v_reward_admin_count,
    'appointment_24h_reminders',
      v_appointment_count
  );
end;
$$;

-- ============================================================================
-- PRUEBA MANUAL PARA ADMIN
-- ============================================================================

create or replace function public.enqueue_admin_test_push()
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
  v_id uuid;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select bm.business_id
  into v_business_id
  from public.business_members bm
  where bm.user_id = v_user_id
    and bm.active = true
  limit 1;

  if v_business_id is null then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  insert into public.notification_outbox (
    business_id,
    audience,
    client_id,
    event_type,
    dedupe_key,
    title,
    body,
    target_path
  )
  values (
    v_business_id,
    'admin',
    null,
    'admin_test',
    'admin-test:' || gen_random_uuid()::text,
    'Notificaciones Bellamia activas ✨',
    'Esta es una notificación de prueba.',
    '/admin'
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

revoke all
on function public.register_admin_push_subscription(
  text,text,text,text
)
from public, anon;

grant execute
on function public.register_admin_push_subscription(
  text,text,text,text
)
to authenticated;

revoke all
on function public.register_client_push_subscription(
  uuid,text,text,text,text
)
from public;

grant execute
on function public.register_client_push_subscription(
  uuid,text,text,text,text
)
to anon, authenticated;

revoke all
on function public.enqueue_scheduled_push_notifications()
from public, anon, authenticated;

-- Cron/database owner can execute it.
grant execute
on function public.enqueue_scheduled_push_notifications()
to postgres;

revoke all
on function public.enqueue_admin_test_push()
from public, anon;

grant execute
on function public.enqueue_admin_test_push()
to authenticated;

commit;
