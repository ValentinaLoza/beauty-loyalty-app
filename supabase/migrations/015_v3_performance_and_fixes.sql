-- ============================================================================
-- v3.0 — Rendimiento y correcciones
-- ============================================================================
-- Seguro de ejecutar en una base existente (producción) y en una base nueva
-- después de 001..014. Todo es idempotente: se puede ejecutar más de una vez.
--
-- 1. Crea get_admin_client_detail(), que la app usa en la ficha de la clienta
--    y que no estaba en ninguna migración (se había creado a mano).
-- 2. Índices que faltaban para las consultas más frecuentes.
-- 3. get_admin_bootstrap() más liviano: calcula el resumen de clientas una
--    sola vez, con agregados en lugar de 4 subconsultas por clienta, y
--    devuelve sólo los IDs de "clientas para recordar" en vez de repetir
--    cada ficha completa (la respuesta pesaba el doble).
-- 4. Publica la tabla appointments en Supabase Realtime, para que la agenda
--    se actualice sola sin consultar cada 3 segundos.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Ficha de la clienta
-- ----------------------------------------------------------------------------
create or replace function public.get_admin_client_detail(
  p_client_id uuid
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
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select c.business_id
  into v_business_id
  from public.clients c
  where c.id = p_client_id;

  if v_business_id is null
     or not private.is_business_member(v_business_id, null) then
    raise exception 'CLIENT_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'history',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', sr.id,
              'service_id', sr.service_id,
              'service_name_snapshot', sr.service_name_snapshot,
              'base_price', sr.base_price,
              'discount_amount', sr.discount_amount,
              'final_price', sr.final_price,
              'loyalty_points_earned', sr.loyalty_points_earned,
              'performed_at', sr.performed_at
            )
            order by sr.performed_at desc
          )
          from public.service_records sr
          where sr.client_id = p_client_id
            and sr.status = 'completed'
        ),
        '[]'::jsonb
      ),
    'rewards',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', r.id,
              'reward_percent_snapshot', r.reward_percent_snapshot,
              'status', r.status,
              'issued_at', r.issued_at,
              'redeemed_at', rr.redeemed_at
            )
            order by r.issued_at desc
          )
          from public.rewards r
          left join public.reward_redemptions rr
            on rr.reward_id = r.id
          where r.client_id = p_client_id
        ),
        '[]'::jsonb
      )
  );
end;
$$;

revoke all on function public.get_admin_client_detail(uuid) from public, anon;
grant execute on function public.get_admin_client_detail(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Índices
-- ----------------------------------------------------------------------------

-- Pertenencia al negocio: la usan todas las políticas RLS y el bootstrap.
create index if not exists business_members_user_active_idx
  on public.business_members (user_id, business_id)
  where active = true;

-- Métricas y actividad reciente del panel.
create index if not exists service_records_business_completed_idx
  on public.service_records (business_id, performed_at desc)
  where status = 'completed';

create index if not exists rewards_business_status_idx
  on public.rewards (business_id, status);

-- Turnos futuros de una clienta (recordatorios y tarjeta pública).
create index if not exists appointments_client_starts_idx
  on public.appointments (client_id, starts_at);

-- ----------------------------------------------------------------------------
-- 3. Bootstrap del panel
-- ----------------------------------------------------------------------------
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
  v_program_id uuid;
  v_clients jsonb;
  v_reminder_ids jsonb;
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
    return jsonb_build_object('has_business', false);
  end if;

  select lp.id
  into v_program_id
  from public.loyalty_programs lp
  where lp.business_id = v_business_id
    and lp.active = true
  limit 1;

  -- Resumen de clientas calculado una sola vez, con agregados por tabla.
  with active_clients as (
    select c.id, c.public_token, c.first_name, c.last_name, c.phone, c.email
    from public.clients c
    where c.business_id = v_business_id
      and c.active = true
      and c.archived_at is null
  ),
  points as (
    select lt.client_id, sum(lt.points_delta)::integer as points
    from public.loyalty_transactions lt
    where lt.program_id = v_program_id
    group by lt.client_id
  ),
  rewards as (
    select r.client_id, count(*)::integer as available_rewards
    from public.rewards r
    where r.business_id = v_business_id
      and r.status = 'available'
    group by r.client_id
  ),
  services as (
    select sr.client_id,
           count(*)::integer as service_count,
           max(sr.performed_at) as last_service_at
    from public.service_records sr
    where sr.business_id = v_business_id
      and sr.status = 'completed'
    group by sr.client_id
  ),
  upcoming as (
    select distinct a.client_id
    from public.appointments a
    where a.business_id = v_business_id
      and a.starts_at > now()
      and a.status in ('requested', 'confirmed')
  ),
  summary as (
    select ac.*,
           coalesce(p.points, 0) as points,
           coalesce(r.available_rewards, 0) as available_rewards,
           coalesce(s.service_count, 0) as service_count,
           s.last_service_at,
           (u.client_id is not null) as has_upcoming
    from active_clients ac
    left join points p on p.client_id = ac.id
    left join rewards r on r.client_id = ac.id
    left join services s on s.client_id = ac.id
    left join upcoming u on u.client_id = ac.id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'public_token', public_token,
          'first_name', first_name,
          'last_name', last_name,
          'phone', phone,
          'email', email,
          'points', points,
          'available_rewards', available_rewards,
          'service_count', service_count,
          'last_service_at', last_service_at
        )
        order by last_name, first_name
      ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(to_jsonb(id) order by last_name, first_name)
        filter (where available_rewards > 0 and not has_upcoming),
      '[]'::jsonb
    )
  into v_clients, v_reminder_ids
  from summary;

  return jsonb_build_object(
    'has_business', true,
    'role', v_role,

    'business',
      (select to_jsonb(b) from public.businesses b where b.id = v_business_id),

    'business_hours',
      coalesce(
        (
          select jsonb_agg(to_jsonb(bh) order by bh.weekday)
          from public.business_hours bh
          where bh.business_id = v_business_id
        ),
        '[]'::jsonb
      ),

    'loyalty',
      (select to_jsonb(lp) from public.loyalty_programs lp where lp.id = v_program_id),

    -- Los desactivados siguen apareciendo; los archivados no.
    'services',
      coalesce(
        (
          select jsonb_agg(to_jsonb(s) order by s.name)
          from public.services s
          where s.business_id = v_business_id
            and s.archived_at is null
        ),
        '[]'::jsonb
      ),

    'clients', v_clients,

    -- Sólo IDs: la app ya tiene cada ficha en 'clients'.
    'reminder_client_ids', v_reminder_ids,

    'recent_activity',
      coalesce(
        (
          select jsonb_agg(x order by (x->>'performed_at')::timestamptz desc)
          from (
            select jsonb_build_object(
              'client_name', c.first_name || ' ' || c.last_name,
              'service_name', sr.service_name_snapshot,
              'final_price', sr.final_price,
              'performed_at', sr.performed_at
            ) x
            from public.service_records sr
            join public.clients c on c.id = sr.client_id
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
              'client_name', c.first_name || ' ' || c.last_name,
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
          join public.clients c on c.id = a.client_id
          join public.services s on s.id = a.service_id
          where a.business_id = v_business_id
            and a.starts_at >= now() - interval '180 days'
        ),
        '[]'::jsonb
      ),

    'metrics',
      (
        select jsonb_build_object(
          'client_count', jsonb_array_length(v_clients),
          'service_count', count(*),
          'revenue', coalesce(sum(sr.final_price), 0),
          'services_this_month',
            count(*) filter (where sr.performed_at >= date_trunc('month', now())),
          'revenue_this_month',
            coalesce(sum(sr.final_price)
              filter (where sr.performed_at >= date_trunc('month', now())), 0),
          'available_rewards',
            (
              select count(*)
              from public.rewards r
              where r.business_id = v_business_id
                and r.status = 'available'
            ),
          'upcoming_appointments',
            (
              select count(*)
              from public.appointments a
              where a.business_id = v_business_id
                and a.starts_at >= now()
                and a.status in ('requested', 'confirmed')
            )
        )
        from public.service_records sr
        where sr.business_id = v_business_id
          and sr.status = 'completed'
      )
  );
end;
$$;

revoke all on function public.get_admin_bootstrap() from public, anon;
grant execute on function public.get_admin_bootstrap() to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Realtime para la agenda
-- ----------------------------------------------------------------------------
-- Supabase Realtime respeta RLS (appointments_select): cada administradora
-- sólo recibe los cambios de su propio negocio.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'appointments'
     ) then
    execute 'alter publication supabase_realtime add table public.appointments';
  end if;
end;
$$;

commit;
