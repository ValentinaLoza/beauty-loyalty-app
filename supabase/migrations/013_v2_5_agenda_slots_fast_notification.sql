-- Bellamia v2.5
-- Agenda con slots disponibles + carga prioritaria al abrir un push.
--
-- Horario operativo actual:
--   08:00 a 21:00
-- Slots:
--   cada 30 minutos
--
-- Los horarios ocupados por requested/confirmed no se ofrecen.

begin;

-- ============================================================================
-- PROTECCIÓN DE COLISIÓN
-- ============================================================================
--
-- El índice ya existe desde v1.4; se vuelve a declarar de forma idempotente.
-- Protege incluso ante dos reservas simultáneas.
create unique index if not exists appointments_one_slot_uq
on public.appointments (business_id, starts_at)
where status in ('requested','confirmed');

-- ============================================================================
-- HORARIOS DISPONIBLES
-- ============================================================================

create or replace function private.available_appointment_slots(
  p_business_id uuid,
  p_date date,
  p_exclude_appointment_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    jsonb_agg(slot order by slot),
    '[]'::jsonb
  )
  from (
    select gs as slot
    from generate_series(
      (
        (p_date + time '08:00')
        at time zone 'America/Argentina/Buenos_Aires'
      ),
      (
        (p_date + time '20:30')
        at time zone 'America/Argentina/Buenos_Aires'
      ),
      interval '30 minutes'
    ) gs
    where gs > now()
      and not exists (
        select 1
        from public.appointments a
        where a.business_id = p_business_id
          and a.starts_at = gs
          and a.status in ('requested','confirmed')
          and (
            p_exclude_appointment_id is null
            or a.id <> p_exclude_appointment_id
          )
      )
  ) q;
$$;

create or replace function public.get_admin_available_appointment_slots(
  p_business_id uuid,
  p_date date,
  p_exclude_appointment_id uuid default null
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
    array['owner','admin','employee']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  return private.available_appointment_slots(
    p_business_id,
    p_date,
    p_exclude_appointment_id
  );
end;
$$;

create or replace function public.get_public_available_appointment_slots(
  p_token uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
begin
  select c.business_id
  into v_business_id
  from public.clients c
  join public.businesses b
    on b.id = c.business_id
  where c.public_token = p_token
    and c.active = true
    and c.archived_at is null
    and b.active = true;

  if v_business_id is null then
    raise exception 'CARD_NOT_FOUND';
  end if;

  return private.available_appointment_slots(
    v_business_id,
    p_date,
    null
  );
end;
$$;

revoke all
on function public.get_admin_available_appointment_slots(
  uuid, date, uuid
)
from public, anon;

grant execute
on function public.get_admin_available_appointment_slots(
  uuid, date, uuid
)
to authenticated;

revoke all
on function public.get_public_available_appointment_slots(
  uuid, date
)
from public;

grant execute
on function public.get_public_available_appointment_slots(
  uuid, date
)
to anon, authenticated;

-- ============================================================================
-- CARGA RÁPIDA DE LA SOLICITUD TOCADA DESDE PUSH
-- ============================================================================

create or replace function public.get_admin_appointment_by_id(
  p_appointment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
begin
  select a.business_id
  into v_business_id
  from public.appointments a
  where a.id = p_appointment_id;

  if v_business_id is null then
    raise exception 'APPOINTMENT_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_business_id,
    null
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  return (
    select jsonb_build_object(
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
    from public.appointments a
    join public.clients c
      on c.id = a.client_id
    join public.services s
      on s.id = a.service_id
    where a.id = p_appointment_id
  );
end;
$$;

revoke all
on function public.get_admin_appointment_by_id(uuid)
from public, anon;

grant execute
on function public.get_admin_appointment_by_id(uuid)
to authenticated;

-- ============================================================================
-- EL PUSH ADMIN LLEVA EL ID DEL TURNO
-- ============================================================================
--
-- private.enqueue_push() inserta notification_outbox. Este BEFORE trigger
-- transforma:
--
-- /admin/appointments
--
-- en:
--
-- /admin/appointments?appointment=<uuid>
--
-- usando el UUID que ya está dentro del dedupe_key.

create or replace function private.decorate_appointment_push_target()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_appointment_id text;
begin
  if new.audience = 'admin'
     and new.event_type = 'appointment_requested'
     and new.dedupe_key like 'appointment-requested:%' then

    v_appointment_id :=
      split_part(new.dedupe_key, ':', 2);

    if v_appointment_id <> '' then
      new.target_path :=
        '/admin/appointments?appointment='
        || v_appointment_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists decorate_appointment_push_target
on public.notification_outbox;

create trigger decorate_appointment_push_target
before insert or update
on public.notification_outbox
for each row
execute function private.decorate_appointment_push_target();

update public.notification_outbox
set target_path =
  '/admin/appointments?appointment='
  || split_part(dedupe_key, ':', 2)
where audience = 'admin'
  and event_type = 'appointment_requested'
  and dedupe_key like 'appointment-requested:%'
  and processed_at is null;

-- ============================================================================
-- BOOTSTRAP ADMIN
-- ============================================================================
-- Appointments are bundled in the same startup RPC so a cold-open from a push
-- does not render Turnos empty and then wait for a second round-trip.

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

    'appointments',
      coalesce(
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
          where a.business_id = v_business_id
            and a.starts_at >= now() - interval '180 days'
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


commit;
