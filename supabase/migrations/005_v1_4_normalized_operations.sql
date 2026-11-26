-- Bellamia v1.4 CONSOLIDADA
-- Ejecutar sobre la base de producción actual.
-- Es idempotente respecto de las estructuras de turnos y reemplaza las funciones
-- operativas de v1.2/v1.3.
--
-- Objetivo:
-- 1) separar "desactivado" de "archivado";
-- 2) permitir editar servicios sin alterar históricos;
-- 3) permitir restaurar archivados;
-- 4) permitir editar turnos;
-- 5) mantener historial y métricas consistentes.

begin;

-- ============================================================================
-- NORMALIZACIÓN DE ESTADO: active != archived
-- ============================================================================

alter table public.clients
  add column if not exists archived_at timestamptz;

alter table public.services
  add column if not exists archived_at timestamptz;

-- En clientas, active=false solo se usó como archivo en las versiones previas.
update public.clients
set archived_at = coalesce(archived_at, updated_at, now())
where active = false
  and archived_at is null;

-- En servicios NO hacemos backfill automático:
-- active=false pudo significar simplemente "desactivado temporalmente".
-- A partir de ahora archived_at identifica de forma inequívoca un archivo.

create index if not exists clients_archived_idx
on public.clients (business_id, archived_at);

create index if not exists services_archived_idx
on public.services (business_id, archived_at);

-- ============================================================================
-- TURNOS (por si v1.2 todavía no fue aplicada)
-- ============================================================================

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null
    references public.businesses(id) on delete cascade,
  client_id uuid not null
    references public.clients(id) on delete cascade,
  service_id uuid not null
    references public.services(id) on delete restrict,
  starts_at timestamptz not null,
  status text not null default 'requested',
  source text not null default 'client',
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint appointments_status_chk
    check (status in ('requested','confirmed','completed','cancelled')),
  constraint appointments_source_chk
    check (source in ('client','admin'))
);

create index if not exists appointments_business_date_idx
on public.appointments (business_id, starts_at);

create unique index if not exists appointments_one_slot_uq
on public.appointments (business_id, starts_at)
where status in ('requested','confirmed');

alter table public.appointments enable row level security;

drop policy if exists appointments_select on public.appointments;
create policy appointments_select
on public.appointments for select
to authenticated
using (private.is_business_member(business_id, null));

drop policy if exists appointments_update on public.appointments;
create policy appointments_update
on public.appointments for update
to authenticated
using (
  private.is_business_member(
    business_id,
    array['owner','admin','employee']::text[]
  )
)
with check (
  private.is_business_member(
    business_id,
    array['owner','admin','employee']::text[]
  )
);

grant select, update on public.appointments to authenticated;

drop trigger if exists appointments_updated_at
on public.appointments;

create trigger appointments_updated_at
before update on public.appointments
for each row execute function private.set_updated_at();

-- ============================================================================
-- VIEW DE CLIENTAS ACTIVAS
-- ============================================================================

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

  coalesce(
    (
      select sum(lt.points_delta)
      from public.loyalty_transactions lt
      where lt.client_id = c.id
        and lt.program_id = (
          select lp.id
          from public.loyalty_programs lp
          where lp.business_id = c.business_id
            and lp.active = true
          limit 1
        )
    ),
    0
  )::integer as points,

  (
    select count(*)
    from public.rewards r
    where r.client_id = c.id
      and r.status = 'available'
  )::integer as available_rewards,

  (
    select count(*)
    from public.service_records sr
    where sr.client_id = c.id
      and sr.status = 'completed'
  )::integer as service_count,

  (
    select max(sr.performed_at)
    from public.service_records sr
    where sr.client_id = c.id
      and sr.status = 'completed'
  ) as last_service_at

from public.clients c
where c.active = true
  and c.archived_at is null;

grant select on public.client_dashboard to authenticated;

-- ============================================================================
-- EDITAR SERVICIO
-- ============================================================================

create or replace function public.update_service_definition(
  p_service_id uuid,
  p_name text,
  p_default_price numeric,
  p_loyalty_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_service public.services%rowtype;
begin
  select *
  into v_service
  from public.services
  where id = p_service_id;

  if not found then
    raise exception 'SERVICE_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_service.business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  if v_service.archived_at is not null then
    raise exception 'SERVICE_ARCHIVED';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'SERVICE_NAME_REQUIRED';
  end if;

  if p_default_price < 0 then
    raise exception 'INVALID_PRICE';
  end if;

  if p_loyalty_points < 0 then
    raise exception 'INVALID_POINTS';
  end if;

  update public.services
  set
    name = trim(p_name),
    default_price = p_default_price,
    loyalty_points = p_loyalty_points
  where id = p_service_id;

  -- service_records conserva service_name_snapshot/base_price/final_price,
  -- por lo tanto editar el servicio NO altera la historia.
  return jsonb_build_object(
    'service_id', p_service_id,
    'updated', true
  );
end;
$$;

-- ============================================================================
-- ARCHIVAR / ELIMINAR CLIENTA
-- ============================================================================

create or replace function public.delete_or_archive_client(
  p_client_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
  v_has_history boolean;
begin
  select business_id
  into v_business_id
  from public.clients
  where id = p_client_id;

  if not found then
    raise exception 'CLIENT_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  select
    exists (
      select 1
      from public.service_records
      where client_id = p_client_id
    )
    or exists (
      select 1
      from public.rewards
      where client_id = p_client_id
    )
    or exists (
      select 1
      from public.loyalty_transactions
      where client_id = p_client_id
    )
    or exists (
      select 1
      from public.appointments
      where client_id = p_client_id
        and (
          starts_at <= now()
          or status = 'completed'
        )
    )
  into v_has_history;

  if not v_has_history then
    delete from public.appointments
    where client_id = p_client_id;

    delete from public.clients
    where id = p_client_id;

    return jsonb_build_object(
      'action', 'deleted',
      'client_id', p_client_id
    );
  end if;

  update public.clients
  set
    active = false,
    archived_at = now()
  where id = p_client_id;

  update public.appointments
  set status = 'cancelled'
  where client_id = p_client_id
    and starts_at > now()
    and status in ('requested','confirmed');

  return jsonb_build_object(
    'action', 'archived',
    'client_id', p_client_id
  );
end;
$$;

create or replace function public.restore_client(
  p_client_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
begin
  select business_id
  into v_business_id
  from public.clients
  where id = p_client_id;

  if not found then
    raise exception 'CLIENT_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  update public.clients
  set
    active = true,
    archived_at = null
  where id = p_client_id;

  return p_client_id;
end;
$$;

-- ============================================================================
-- ARCHIVAR / ELIMINAR SERVICIO
-- ============================================================================

create or replace function public.delete_or_archive_service(
  p_service_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
  v_has_history boolean;
begin
  select business_id
  into v_business_id
  from public.services
  where id = p_service_id;

  if not found then
    raise exception 'SERVICE_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  select
    exists (
      select 1
      from public.service_records
      where service_id = p_service_id
    )
    or exists (
      select 1
      from public.appointments
      where service_id = p_service_id
        and (
          starts_at <= now()
          or status = 'completed'
        )
    )
  into v_has_history;

  if not v_has_history then
    delete from public.appointments
    where service_id = p_service_id;

    delete from public.services
    where id = p_service_id;

    return jsonb_build_object(
      'action', 'deleted',
      'service_id', p_service_id
    );
  end if;

  update public.services
  set
    active = false,
    archived_at = now()
  where id = p_service_id;

  update public.appointments
  set status = 'cancelled'
  where service_id = p_service_id
    and starts_at > now()
    and status in ('requested','confirmed');

  return jsonb_build_object(
    'action', 'archived',
    'service_id', p_service_id
  );
end;
$$;

create or replace function public.restore_service(
  p_service_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
begin
  select business_id
  into v_business_id
  from public.services
  where id = p_service_id;

  if not found then
    raise exception 'SERVICE_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  update public.services
  set
    archived_at = null,
    active = true
  where id = p_service_id;

  return p_service_id;
end;
$$;

-- ============================================================================
-- ARCHIVADOS
-- ============================================================================

create or replace function public.get_archived_entities(
  p_business_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not private.is_business_member(
    p_business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  return jsonb_build_object(
    'clients',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', c.id,
              'business_id', c.business_id,
              'public_token', c.public_token,
              'first_name', c.first_name,
              'last_name', c.last_name,
              'phone', c.phone,
              'email', c.email,
              'active', c.active,
              'points',
                coalesce(
                  (
                    select sum(lt.points_delta)
                    from public.loyalty_transactions lt
                    where lt.client_id = c.id
                      and lt.program_id = (
                        select lp.id
                        from public.loyalty_programs lp
                        where lp.business_id = c.business_id
                          and lp.active = true
                        limit 1
                      )
                  ),
                  0
                ),
              'available_rewards',
                (
                  select count(*)
                  from public.rewards r
                  where r.client_id = c.id
                    and r.status = 'available'
                ),
              'service_count',
                (
                  select count(*)
                  from public.service_records sr
                  where sr.client_id = c.id
                    and sr.status = 'completed'
                ),
              'last_service_at',
                (
                  select max(sr.performed_at)
                  from public.service_records sr
                  where sr.client_id = c.id
                    and sr.status = 'completed'
                )
            )
            order by c.last_name, c.first_name
          )
          from public.clients c
          where c.business_id = p_business_id
            and c.archived_at is not null
        ),
        '[]'::jsonb
      ),
    'services',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', s.id,
              'business_id', s.business_id,
              'name', s.name,
              'default_price', s.default_price,
              'loyalty_points', s.loyalty_points,
              'active', s.active
            )
            order by s.name
          )
          from public.services s
          where s.business_id = p_business_id
            and s.archived_at is not null
        ),
        '[]'::jsonb
      )
  );
end;
$$;

-- ============================================================================
-- TURNOS
-- ============================================================================

create or replace function public.create_admin_appointment(
  p_business_id uuid,
  p_client_id uuid,
  p_service_id uuid,
  p_starts_at timestamptz,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_id uuid;
begin
  if not private.is_business_member(
    p_business_id,
    array['owner','admin','employee']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  if p_starts_at <= now() then
    raise exception 'APPOINTMENT_MUST_BE_FUTURE';
  end if;

  if not exists (
    select 1
    from public.clients
    where id = p_client_id
      and business_id = p_business_id
      and active = true
      and archived_at is null
  ) then
    raise exception 'CLIENT_INVALID';
  end if;

  if not exists (
    select 1
    from public.services
    where id = p_service_id
      and business_id = p_business_id
      and active = true
      and archived_at is null
  ) then
    raise exception 'SERVICE_INVALID';
  end if;

  insert into public.appointments (
    business_id,
    client_id,
    service_id,
    starts_at,
    status,
    source,
    notes,
    created_by
  )
  values (
    p_business_id,
    p_client_id,
    p_service_id,
    p_starts_at,
    'confirmed',
    'admin',
    p_notes,
    auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.update_admin_appointment(
  p_appointment_id uuid,
  p_client_id uuid,
  p_service_id uuid,
  p_starts_at timestamptz,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_appointment public.appointments%rowtype;
begin
  select *
  into v_appointment
  from public.appointments
  where id = p_appointment_id;

  if not found then
    raise exception 'APPOINTMENT_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_appointment.business_id,
    array['owner','admin','employee']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  if v_appointment.status in ('completed','cancelled') then
    raise exception 'APPOINTMENT_NOT_EDITABLE';
  end if;

  if p_starts_at <= now() then
    raise exception 'APPOINTMENT_MUST_BE_FUTURE';
  end if;

  if not exists (
    select 1
    from public.clients
    where id = p_client_id
      and business_id = v_appointment.business_id
      and active = true
      and archived_at is null
  ) then
    raise exception 'CLIENT_INVALID';
  end if;

  if not exists (
    select 1
    from public.services
    where id = p_service_id
      and business_id = v_appointment.business_id
      and active = true
      and archived_at is null
  ) then
    raise exception 'SERVICE_INVALID';
  end if;

  update public.appointments
  set
    client_id = p_client_id,
    service_id = p_service_id,
    starts_at = p_starts_at,
    notes = p_notes
  where id = p_appointment_id;

  return p_appointment_id;
end;
$$;

create or replace function public.request_public_appointment(
  p_token uuid,
  p_service_id uuid,
  p_starts_at timestamptz,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_client public.clients%rowtype;
  v_id uuid;
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

  if p_starts_at <= now() then
    raise exception 'APPOINTMENT_MUST_BE_FUTURE';
  end if;

  if not exists (
    select 1
    from public.services
    where id = p_service_id
      and business_id = v_client.business_id
      and active = true
      and archived_at is null
  ) then
    raise exception 'SERVICE_INVALID';
  end if;

  insert into public.appointments (
    business_id,
    client_id,
    service_id,
    starts_at,
    status,
    source,
    notes
  )
  values (
    v_client.business_id,
    v_client.id,
    p_service_id,
    p_starts_at,
    'requested',
    'client',
    p_notes
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.get_admin_appointments(
  p_business_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not private.is_business_member(
    p_business_id,
    null
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'client_id', a.client_id,
          'client_name',
            c.first_name || ' ' || c.last_name,
          'service_id', a.service_id,
          'service_name', s.name,
          'starts_at', a.starts_at,
          'status', a.status,
          'source', a.source,
          'notes', a.notes
        )
        order by a.starts_at desc
      )
      from public.appointments a
      join public.clients c
        on c.id = a.client_id
      join public.services s
        on s.id = a.service_id
      where a.business_id = p_business_id
        and a.starts_at >= now() - interval '180 days'
    ),
    '[]'::jsonb
  );
end;
$$;

create or replace function public.delete_or_cancel_appointment(
  p_appointment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_appointment public.appointments%rowtype;
begin
  select *
  into v_appointment
  from public.appointments
  where id = p_appointment_id;

  if not found then
    raise exception 'APPOINTMENT_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_appointment.business_id,
    array['owner','admin','employee']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  if v_appointment.starts_at > now()
     and v_appointment.status in (
       'requested','confirmed','cancelled'
     ) then

    delete from public.appointments
    where id = p_appointment_id;

    return jsonb_build_object(
      'action', 'deleted',
      'appointment_id', p_appointment_id
    );
  end if;

  -- Los históricos no se destruyen.
  return jsonb_build_object(
    'action', 'preserved',
    'appointment_id', p_appointment_id
  );
end;
$$;

-- ============================================================================
-- BOOTSTRAP ADMIN
-- ============================================================================

create or replace function public.get_admin_bootstrap()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
  v_role text;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select bm.business_id, bm.role
  into v_business_id, v_role
  from public.business_members bm
  join public.businesses b
    on b.id = bm.business_id
  where bm.user_id = v_user_id
    and bm.active = true
    and b.active = true
  limit 1;

  if v_business_id is null then
    return jsonb_build_object(
      'has_business', false
    );
  end if;

  return jsonb_build_object(
    'has_business', true,
    'role', v_role,

    'business',
      (
        select to_jsonb(b)
        from public.businesses b
        where b.id = v_business_id
      ),

    'loyalty',
      (
        select to_jsonb(lp)
        from public.loyalty_programs lp
        where lp.business_id = v_business_id
          and lp.active = true
        limit 1
      ),

    -- Los desactivados siguen apareciendo.
    -- Los archivados NO.
    'services',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(s)
            order by s.name
          )
          from public.services s
          where s.business_id = v_business_id
            and s.archived_at is null
        ),
        '[]'::jsonb
      ),

    'clients',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(cd)
            order by cd.last_name, cd.first_name
          )
          from public.client_dashboard cd
          where cd.business_id = v_business_id
        ),
        '[]'::jsonb
      ),

    'reminder_clients',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(cd)
            order by cd.last_name, cd.first_name
          )
          from public.client_dashboard cd
          where cd.business_id = v_business_id
            and cd.available_rewards > 0
            and not exists (
              select 1
              from public.appointments a
              where a.client_id = cd.id
                and a.starts_at > now()
                and a.status in ('requested','confirmed')
            )
        ),
        '[]'::jsonb
      ),

    'recent_activity',
      coalesce(
        (
          select jsonb_agg(
            x
            order by
              (x->>'performed_at')::timestamptz desc
          )
          from (
            select jsonb_build_object(
              'client_name',
                c.first_name || ' ' || c.last_name,
              'service_name',
                sr.service_name_snapshot,
              'final_price',
                sr.final_price,
              'performed_at',
                sr.performed_at
            ) x
            from public.service_records sr
            join public.clients c
              on c.id = sr.client_id
            where sr.business_id = v_business_id
              and sr.status = 'completed'
            order by sr.performed_at desc
            limit 10
          ) q
        ),
        '[]'::jsonb
      ),

    'metrics',
      jsonb_build_object(
        'client_count',
          (
            select count(*)
            from public.clients
            where business_id = v_business_id
              and active = true
              and archived_at is null
          ),

        'service_count',
          (
            select count(*)
            from public.service_records
            where business_id = v_business_id
              and status = 'completed'
          ),

        'available_rewards',
          (
            select count(*)
            from public.rewards
            where business_id = v_business_id
              and status = 'available'
          ),

        'revenue',
          coalesce(
            (
              select sum(final_price)
              from public.service_records
              where business_id = v_business_id
                and status = 'completed'
            ),
            0
          ),

        'services_this_month',
          (
            select count(*)
            from public.service_records
            where business_id = v_business_id
              and status = 'completed'
              and performed_at >=
                date_trunc('month', now())
          ),

        'revenue_this_month',
          coalesce(
            (
              select sum(final_price)
              from public.service_records
              where business_id = v_business_id
                and status = 'completed'
                and performed_at >=
                  date_trunc('month', now())
            ),
            0
          ),

        'upcoming_appointments',
          (
            select count(*)
            from public.appointments
            where business_id = v_business_id
              and starts_at >= now()
              and status in ('requested','confirmed')
          )
      )
  );
end;
$$;

-- ============================================================================
-- TARJETA PÚBLICA
-- ============================================================================

create or replace function public.get_public_client_card(
  p_token uuid
)
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
begin
  select c.*
  into v_client
  from public.clients c
  join public.businesses b
    on b.id = c.business_id
  where c.public_token = p_token
    and c.active = true
    and c.archived_at is null
    and b.active = true;

  if not found then
    raise exception 'CARD_NOT_FOUND';
  end if;

  select *
  into v_business
  from public.businesses
  where id = v_client.business_id;

  select *
  into v_program
  from public.loyalty_programs
  where business_id = v_client.business_id
    and active = true
  limit 1;

  if found then
    select coalesce(sum(points_delta), 0)::integer
    into v_points
    from public.loyalty_transactions
    where client_id = v_client.id
      and program_id = v_program.id;
  end if;

  select count(*)::integer
  into v_available
  from public.rewards
  where client_id = v_client.id
    and status = 'available';

  return jsonb_build_object(
    'business',
      jsonb_build_object(
        'id', v_business.id,
        'name', v_business.name,
        'primary_color_hex',
          v_business.primary_color_hex,
        'phone', v_business.phone,
        'logo_url', v_business.logo_url
      ),

    'client',
      jsonb_build_object(
        'id', v_client.id,
        'first_name', v_client.first_name,
        'last_name', v_client.last_name,
        'points', v_points,
        'available_rewards', v_available
      ),

    'loyalty',
      jsonb_build_object(
        'id', coalesce(v_program.id::text, ''),
        'points_required',
          coalesce(v_program.points_required, 5),
        'reward_percent',
          coalesce(v_program.reward_percent, 20)
      ),

    'services',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(s)
            order by s.name
          )
          from public.services s
          where s.business_id = v_client.business_id
            and s.active = true
            and s.archived_at is null
        ),
        '[]'::jsonb
      ),

    'appointments',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'client_id', a.client_id,
              'client_name',
                v_client.first_name || ' ' ||
                v_client.last_name,
              'service_id', a.service_id,
              'service_name', s.name,
              'starts_at', a.starts_at,
              'status', a.status,
              'source', a.source,
              'notes', a.notes
            )
            order by a.starts_at
          )
          from public.appointments a
          join public.services s
            on s.id = a.service_id
          where a.client_id = v_client.id
            and a.starts_at >= now()
            and a.status in ('requested','confirmed')
        ),
        '[]'::jsonb
      ),

    'history',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', sr.id,
              'service_id', sr.service_id,
              'service_name',
                sr.service_name_snapshot,
              'base_price', sr.base_price,
              'discount_amount',
                sr.discount_amount,
              'final_price', sr.final_price,
              'points_earned',
                sr.loyalty_points_earned,
              'performed_at', sr.performed_at
            )
            order by sr.performed_at desc
          )
          from (
            select *
            from public.service_records
            where client_id = v_client.id
              and status = 'completed'
            order by performed_at desc
            limit 50
          ) sr
        ),
        '[]'::jsonb
      ),

    'rewards',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', r.id,
              'percent',
                r.reward_percent_snapshot,
              'status', r.status,
              'issued_at', r.issued_at,
              'redeemed_at', rr.redeemed_at
            )
            order by r.issued_at desc
          )
          from public.rewards r
          left join public.reward_redemptions rr
            on rr.reward_id = r.id
          where r.client_id = v_client.id
        ),
        '[]'::jsonb
      )
  );
end;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

revoke all
on function public.update_service_definition(
  uuid,text,numeric,integer
)
from public, anon;

grant execute
on function public.update_service_definition(
  uuid,text,numeric,integer
)
to authenticated;

revoke all
on function public.delete_or_archive_client(uuid)
from public, anon;
grant execute
on function public.delete_or_archive_client(uuid)
to authenticated;

revoke all
on function public.restore_client(uuid)
from public, anon;
grant execute
on function public.restore_client(uuid)
to authenticated;

revoke all
on function public.delete_or_archive_service(uuid)
from public, anon;
grant execute
on function public.delete_or_archive_service(uuid)
to authenticated;

revoke all
on function public.restore_service(uuid)
from public, anon;
grant execute
on function public.restore_service(uuid)
to authenticated;

revoke all
on function public.get_archived_entities(uuid)
from public, anon;
grant execute
on function public.get_archived_entities(uuid)
to authenticated;

revoke all
on function public.create_admin_appointment(
  uuid,uuid,uuid,timestamptz,text
)
from public, anon;
grant execute
on function public.create_admin_appointment(
  uuid,uuid,uuid,timestamptz,text
)
to authenticated;

revoke all
on function public.update_admin_appointment(
  uuid,uuid,uuid,timestamptz,text
)
from public, anon;
grant execute
on function public.update_admin_appointment(
  uuid,uuid,uuid,timestamptz,text
)
to authenticated;

revoke all
on function public.get_admin_appointments(uuid)
from public, anon;
grant execute
on function public.get_admin_appointments(uuid)
to authenticated;

revoke all
on function public.delete_or_cancel_appointment(uuid)
from public, anon;
grant execute
on function public.delete_or_cancel_appointment(uuid)
to authenticated;

revoke all
on function public.request_public_appointment(
  uuid,uuid,timestamptz,text
)
from public;

grant execute
on function public.request_public_appointment(
  uuid,uuid,timestamptz,text
)
to anon, authenticated;

commit;
