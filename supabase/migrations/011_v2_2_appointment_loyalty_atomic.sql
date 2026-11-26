-- Bellamia v2.2
-- Turnos + historial + fidelidad pasan a ser una sola operación atómica.
--
-- Antes:
--   appointment.status = 'completed'
-- no generaba service_record ni puntos.
--
-- Ahora:
--   complete_appointment()
--   1) bloquea el turno;
--   2) registra el servicio;
--   3) opcionalmente canjea un reward;
--   4) acredita puntos;
--   5) emite nuevos rewards si corresponde;
--   6) vincula service_record con appointment;
--   7) recién entonces marca el turno completed.
--
-- Si cualquier paso falla, PostgreSQL revierte TODO.

begin;

alter table public.appointments
  add column if not exists service_record_id uuid;

alter table public.appointments
  add column if not exists completed_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'appointments_service_record_fk'
  ) then
    alter table public.appointments
      add constraint appointments_service_record_fk
      foreign key (service_record_id)
      references public.service_records(id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists appointments_service_record_uq
on public.appointments(service_record_id)
where service_record_id is not null;

create or replace function public.complete_appointment(
  p_appointment_id uuid,
  p_reward_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_appointment public.appointments%rowtype;
  v_client public.clients%rowtype;
  v_service public.services%rowtype;
  v_program public.loyalty_programs%rowtype;
  v_reward public.rewards%rowtype;
  v_existing public.service_records%rowtype;

  v_service_record_id uuid;
  v_redemption_id uuid;
  v_new_reward_id uuid;

  v_discount numeric(12,2) := 0;
  v_final numeric(12,2);
  v_balance integer := 0;
  v_rewards jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select *
  into v_appointment
  from public.appointments
  where id = p_appointment_id
  for update;

  if not found then
    raise exception 'APPOINTMENT_NOT_FOUND';
  end if;

  if not private.is_business_member(
    v_appointment.business_id,
    array['owner','admin','employee']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  if v_appointment.status = 'cancelled' then
    raise exception 'APPOINTMENT_CANCELLED';
  end if;

  -- Idempotent replay: a second click cannot duplicate the service.
  if v_appointment.service_record_id is not null then
    return jsonb_build_object(
      'appointment_id', v_appointment.id,
      'service_record_id', v_appointment.service_record_id,
      'idempotent_replay', true
    );
  end if;

  select *
  into v_client
  from public.clients
  where id = v_appointment.client_id
  for update;

  if not found
     or v_client.business_id <> v_appointment.business_id then
    raise exception 'CLIENT_INVALID';
  end if;

  -- A booked service is allowed to be completed even if the business
  -- disabled/archive it after the appointment was originally created.
  select *
  into v_service
  from public.services
  where id = v_appointment.service_id;

  if not found
     or v_service.business_id <> v_appointment.business_id then
    raise exception 'SERVICE_INVALID';
  end if;

  select *
  into v_program
  from public.loyalty_programs
  where business_id = v_appointment.business_id
    and active = true
  limit 1;

  if not found then
    raise exception 'LOYALTY_PROGRAM_NOT_FOUND';
  end if;

  -- Appointment UUID is also the service idempotency key.
  select *
  into v_existing
  from public.service_records
  where business_id = v_appointment.business_id
    and idempotency_key = v_appointment.id;

  if found then
    update public.appointments
    set
      status = 'completed',
      service_record_id = v_existing.id,
      completed_at = coalesce(completed_at, now())
    where id = v_appointment.id;

    return jsonb_build_object(
      'appointment_id', v_appointment.id,
      'service_record_id', v_existing.id,
      'idempotent_replay', true
    );
  end if;

  if p_reward_id is not null then
    select *
    into v_reward
    from public.rewards
    where id = p_reward_id
    for update;

    if not found
       or v_reward.business_id <> v_appointment.business_id
       or v_reward.client_id <> v_appointment.client_id
       or v_reward.status <> 'available' then
      raise exception 'REWARD_NOT_AVAILABLE';
    end if;

    v_discount := round(
      v_service.default_price
      * v_reward.reward_percent_snapshot
      / 100,
      2
    );

    v_discount := least(
      v_service.default_price,
      v_discount
    );
  end if;

  v_final := greatest(
    v_service.default_price - v_discount,
    0
  );

  insert into public.service_records(
    business_id,
    client_id,
    service_id,
    registered_by,
    service_name_snapshot,
    base_price,
    discount_amount,
    final_price,
    loyalty_points_earned,
    performed_at,
    status,
    idempotency_key
  )
  values (
    v_appointment.business_id,
    v_appointment.client_id,
    v_appointment.service_id,
    v_user_id,
    v_service.name,
    v_service.default_price,
    v_discount,
    v_final,
    v_service.loyalty_points,
    now(),
    'completed',
    v_appointment.id
  )
  returning id
  into v_service_record_id;

  if p_reward_id is not null then
    insert into public.reward_redemptions(
      reward_id,
      business_id,
      client_id,
      service_record_id,
      redeemed_by,
      discount_amount,
      redeemed_at
    )
    values (
      v_reward.id,
      v_appointment.business_id,
      v_appointment.client_id,
      v_service_record_id,
      v_user_id,
      v_discount,
      now()
    )
    returning id
    into v_redemption_id;

    update public.rewards
    set status = 'redeemed'
    where id = v_reward.id;
  end if;

  if v_service.loyalty_points > 0 then
    insert into public.loyalty_transactions(
      business_id,
      client_id,
      program_id,
      service_record_id,
      transaction_type,
      points_delta,
      created_by
    )
    values (
      v_appointment.business_id,
      v_appointment.client_id,
      v_program.id,
      v_service_record_id,
      'service_earned',
      v_service.loyalty_points,
      v_user_id
    );
  end if;

  select coalesce(sum(points_delta), 0)::integer
  into v_balance
  from public.loyalty_transactions
  where client_id = v_appointment.client_id
    and program_id = v_program.id;

  while v_balance >= v_program.points_required loop
    insert into public.rewards(
      business_id,
      client_id,
      program_id,
      reward_percent_snapshot,
      status
    )
    values (
      v_appointment.business_id,
      v_appointment.client_id,
      v_program.id,
      v_program.reward_percent,
      'available'
    )
    returning id
    into v_new_reward_id;

    insert into public.loyalty_transactions(
      business_id,
      client_id,
      program_id,
      service_record_id,
      reward_id,
      transaction_type,
      points_delta,
      created_by
    )
    values (
      v_appointment.business_id,
      v_appointment.client_id,
      v_program.id,
      v_service_record_id,
      v_new_reward_id,
      'reward_issued',
      -v_program.points_required,
      v_user_id
    );

    v_balance :=
      v_balance - v_program.points_required;

    v_rewards :=
      v_rewards
      || jsonb_build_array(
        jsonb_build_object(
          'id', v_new_reward_id,
          'percent', v_program.reward_percent
        )
      );
  end loop;

  update public.appointments
  set
    status = 'completed',
    service_record_id = v_service_record_id,
    completed_at = now()
  where id = v_appointment.id;

  return jsonb_build_object(
    'appointment_id', v_appointment.id,
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

-- Safety net: old/cached frontends are no longer allowed to do the broken
-- "status only" completion.
create or replace function private.guard_appointment_completion()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.status = 'completed'
     and new.service_record_id is null then
    raise exception
      'COMPLETION_REQUIRES_SERVICE_RECORD';
  end if;

  if new.status = 'completed'
     and old.status is distinct from 'completed'
     and new.completed_at is null then
    new.completed_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists guard_appointment_completion
on public.appointments;

create trigger guard_appointment_completion
before update on public.appointments
for each row
execute function private.guard_appointment_completion();

revoke all
on function public.complete_appointment(uuid, uuid)
from public, anon;

grant execute
on function public.complete_appointment(uuid, uuid)
to authenticated;

commit;
