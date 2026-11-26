-- Bellamia v2.6
-- Horarios de atención configurables desde Admin → Negocio.

begin;

-- ============================================================================
-- CONFIGURACIÓN
-- ============================================================================

alter table public.businesses
  add column if not exists appointment_slot_minutes integer
  not null default 30;

alter table public.businesses
  drop constraint if exists businesses_slot_minutes_chk;

alter table public.businesses
  add constraint businesses_slot_minutes_chk
  check (appointment_slot_minutes in (15, 30, 45, 60));

create table if not exists public.business_hours (
  business_id uuid not null
    references public.businesses(id)
    on delete cascade,
  weekday smallint not null,
  enabled boolean not null default true,
  opens_at time not null default time '08:00',
  closes_at time not null default time '21:00',
  updated_at timestamptz not null default now(),
  primary key (business_id, weekday),
  constraint business_hours_weekday_chk
    check (weekday between 1 and 7),
  constraint business_hours_range_chk
    check (closes_at > opens_at)
);

revoke all on table public.business_hours
from public, anon, authenticated;

-- Preserve the v2.5 behavior for all existing businesses.
insert into public.business_hours(
  business_id,
  weekday,
  enabled,
  opens_at,
  closes_at
)
select
  b.id,
  d.weekday,
  true,
  time '08:00',
  time '21:00'
from public.businesses b
cross join generate_series(1, 7) as d(weekday)
on conflict (business_id, weekday) do nothing;

-- Automatically seed future businesses too.
create or replace function private.seed_business_hours()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.business_hours(
    business_id,
    weekday,
    enabled,
    opens_at,
    closes_at
  )
  select
    new.id,
    d.weekday,
    true,
    time '08:00',
    time '21:00'
  from generate_series(1, 7) as d(weekday)
  on conflict (business_id, weekday) do nothing;

  return new;
end;
$$;

drop trigger if exists seed_business_hours
on public.businesses;

create trigger seed_business_hours
after insert on public.businesses
for each row
execute function private.seed_business_hours();

-- ============================================================================
-- GUARDADO DESDE ADMIN
-- ============================================================================

create or replace function public.update_business_schedule(
  p_business_id uuid,
  p_slot_minutes integer,
  p_hours jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_item jsonb;
  v_weekday integer;
  v_enabled boolean;
  v_opens time;
  v_closes time;
begin
  if not private.is_business_member(
    p_business_id,
    array['owner','admin']::text[]
  ) then
    raise exception 'BUSINESS_ACCESS_DENIED';
  end if;

  if p_slot_minutes not in (15, 30, 45, 60) then
    raise exception 'INVALID_SLOT_MINUTES';
  end if;

  if jsonb_typeof(p_hours) <> 'array'
     or jsonb_array_length(p_hours) <> 7 then
    raise exception 'INVALID_BUSINESS_HOURS';
  end if;

  update public.businesses
  set
    appointment_slot_minutes = p_slot_minutes,
    updated_at = now()
  where id = p_business_id;

  for v_item in
    select value
    from jsonb_array_elements(p_hours)
  loop
    v_weekday := (v_item->>'weekday')::integer;
    v_enabled := coalesce(
      (v_item->>'enabled')::boolean,
      false
    );
    v_opens := (v_item->>'opens_at')::time;
    v_closes := (v_item->>'closes_at')::time;

    if v_weekday not between 1 and 7 then
      raise exception 'INVALID_WEEKDAY';
    end if;

    if v_closes <= v_opens then
      raise exception 'INVALID_OPENING_RANGE';
    end if;

    if v_enabled
       and extract(epoch from (v_closes - v_opens)) / 60
           < p_slot_minutes then
      raise exception 'OPENING_RANGE_TOO_SHORT';
    end if;

    insert into public.business_hours(
      business_id,
      weekday,
      enabled,
      opens_at,
      closes_at,
      updated_at
    )
    values (
      p_business_id,
      v_weekday,
      v_enabled,
      v_opens,
      v_closes,
      now()
    )
    on conflict (business_id, weekday)
    do update set
      enabled = excluded.enabled,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      updated_at = now();
  end loop;
end;
$$;

revoke all
on function public.update_business_schedule(
  uuid, integer, jsonb
)
from public, anon;

grant execute
on function public.update_business_schedule(
  uuid, integer, jsonb
)
to authenticated;

-- ============================================================================
-- DISPONIBILIDAD BASADA EN LA CONFIGURACIÓN DEL NEGOCIO
-- ============================================================================

create or replace function private.available_appointment_slots(
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
declare
  v_weekday integer;
  v_enabled boolean;
  v_opens time;
  v_closes time;
  v_slot_minutes integer;
begin
  v_weekday := extract(isodow from p_date)::integer;

  select
    b.appointment_slot_minutes,
    coalesce(bh.enabled, true),
    coalesce(bh.opens_at, time '08:00'),
    coalesce(bh.closes_at, time '21:00')
  into
    v_slot_minutes,
    v_enabled,
    v_opens,
    v_closes
  from public.businesses b
  left join public.business_hours bh
    on bh.business_id = b.id
   and bh.weekday = v_weekday
  where b.id = p_business_id
    and b.active = true;

  if not found or not v_enabled then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(
      jsonb_agg(slot order by slot),
      '[]'::jsonb
    )
    from (
      select gs as slot
      from generate_series(
        (
          (p_date + v_opens)
          at time zone 'America/Argentina/Buenos_Aires'
        ),
        (
          (
            p_date
            + v_closes
            - make_interval(mins => v_slot_minutes)
          )
          at time zone 'America/Argentina/Buenos_Aires'
        ),
        make_interval(mins => v_slot_minutes)
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
    ) q
  );
end;
$$;

-- ============================================================================
-- BOOTSTRAP ADMIN: incluye business_hours
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


    'business_hours',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(bh)
            order by bh.weekday
          )
          from public.business_hours bh
          where bh.business_id = v_business_id
        ),
        '[]'::jsonb
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
