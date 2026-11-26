-- Bellamia v2.4
-- 1) Las solicitudes creadas por clientas SIEMPRE nacen requested.
-- 2) Sólo un miembro autenticado del negocio puede confirmar/cancelar.
-- 3) La notificación admin abre /admin/appointments.
-- 4) Las notificaciones clienta abren /card/<public_token>.

begin;

-- ---------------------------------------------------------------------------
-- Solicitud pública: blindar status='requested'
-- ---------------------------------------------------------------------------

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
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Guard de estado.
--
-- INSERT source=client: fuerza requested incluso si una versión vieja intenta
-- mandar otro estado.
--
-- UPDATE requested -> confirmed/cancelled: requiere usuario autenticado y
-- miembro del negocio.
-- ---------------------------------------------------------------------------

create or replace function private.guard_client_appointment_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if new.source = 'client' then
      new.status := 'requested';
      new.created_by := null;
    end if;

    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.source = 'client'
       and old.status = 'requested'
       and new.status is distinct from old.status then

      if new.status not in ('confirmed', 'cancelled') then
        raise exception 'INVALID_CLIENT_REQUEST_TRANSITION';
      end if;

      if v_uid is null
         or not private.is_business_member(
           new.business_id,
           array['owner','admin','employee']::text[]
         ) then
        raise exception 'ADMIN_REQUIRED_TO_RESOLVE_REQUEST';
      end if;
    end if;

    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_client_appointment_state
on public.appointments;

create trigger guard_client_appointment_state
before insert or update of status
on public.appointments
for each row
execute function private.guard_client_appointment_state();

-- ---------------------------------------------------------------------------
-- Push de turnos.
-- ---------------------------------------------------------------------------

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
        '/card/' || v_client.public_token::text
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
          '/card/' || v_client.public_token::text
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
          '/card/' || v_client.public_token::text
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
        '/card/' || v_client.public_token::text
      );

    end if;

    return new;
  end if;

  return new;
end;
$$;

-- Trigger already exists from v1.5, but recreate it so this migration is
-- self-contained.
drop trigger if exists push_appointment_events
on public.appointments;

create trigger push_appointment_events
after insert or update
on public.appointments
for each row
execute function private.push_appointment_event();

-- Any admin notification still waiting in the outbox should use Turnos.
update public.notification_outbox
set target_path = '/admin/appointments'
where audience = 'admin'
  and event_type = 'appointment_requested'
  and processed_at is null;

commit;
