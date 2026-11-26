-- ============================================================================
-- v3.1 — Copias de seguridad
-- ============================================================================
-- export_business_backup():  la administradora descarga un archivo con todos
--                             los datos de su negocio.
-- restore_business_backup(): en un proyecto NUEVO (usuaria sin negocio),
--                             vuelve a cargar ese archivo tal cual.
--
-- Seguro de ejecutar en una base existente; idempotente.
-- ============================================================================

begin;

alter table public.businesses
  add column if not exists last_backup_at timestamptz;

-- Orden de las tablas: cada una sólo depende de las anteriores.
-- No se copian: miembros (los usuarios son de cada proyecto) ni
-- suscripciones push (están atadas a cada navegador y proyecto).

-- ----------------------------------------------------------------------------
-- Exportar
-- ----------------------------------------------------------------------------
create or replace function public.export_business_backup()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_business_id uuid;
  v_now timestamptz := now();
  v_backup jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select bm.business_id
  into v_business_id
  from public.business_members bm
  join public.businesses b on b.id = bm.business_id
  where bm.user_id = auth.uid()
    and bm.active = true
    and bm.role in ('owner', 'admin')
    and b.active = true
  limit 1;

  if v_business_id is null then
    raise exception 'BACKUP_REQUIRES_OWNER_OR_ADMIN';
  end if;

  update public.businesses
  set last_backup_at = v_now
  where id = v_business_id;

  v_backup := jsonb_build_object(
    'format', 'beauty-loyalty-backup',
    'version', 1,
    'exported_at', v_now,
    'business_id', v_business_id,
    'tables', jsonb_build_object(
      'businesses',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.businesses t
          where t.id = v_business_id),
      'business_hours',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.business_hours t
          where t.business_id = v_business_id),
      'loyalty_programs',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.loyalty_programs t
          where t.business_id = v_business_id),
      'services',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.services t
          where t.business_id = v_business_id),
      'clients',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.clients t
          where t.business_id = v_business_id),
      'service_records',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.service_records t
          where t.business_id = v_business_id),
      'rewards',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.rewards t
          where t.business_id = v_business_id),
      'loyalty_transactions',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.loyalty_transactions t
          where t.business_id = v_business_id),
      'reward_redemptions',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.reward_redemptions t
          where t.business_id = v_business_id),
      'appointments',
        (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.appointments t
          where t.business_id = v_business_id)
    )
  );

  return v_backup;
end;
$$;

revoke all on function public.export_business_backup() from public, anon;
grant execute on function public.export_business_backup() to authenticated;

-- ----------------------------------------------------------------------------
-- Restaurar
-- ----------------------------------------------------------------------------
create or replace function public.restore_business_backup(p_backup jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_user_id uuid := auth.uid();
  v_tables jsonb;
  v_business_id uuid;
  v_appointments jsonb;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  -- Nunca mezcla ni pisa datos: sólo para una usuaria sin negocio.
  if exists (
    select 1 from public.business_members bm
    where bm.user_id = v_user_id
  ) then
    raise exception 'RESTORE_ONLY_FOR_USER_WITHOUT_BUSINESS';
  end if;

  if p_backup->>'format' is distinct from 'beauty-loyalty-backup'
     or (p_backup->>'version')::int is distinct from 1 then
    raise exception 'INVALID_BACKUP_FILE';
  end if;

  v_tables := p_backup->'tables';
  v_business_id := (p_backup->>'business_id')::uuid;

  if jsonb_array_length(coalesce(v_tables->'businesses', '[]')) <> 1 then
    raise exception 'INVALID_BACKUP_FILE';
  end if;

  if exists (select 1 from public.businesses where id = v_business_id) then
    raise exception 'BUSINESS_ALREADY_EXISTS';
  end if;

  insert into public.businesses
  select * from jsonb_populate_recordset(null::public.businesses, v_tables->'businesses');

  insert into public.business_members (business_id, user_id, role, active)
  values (v_business_id, v_user_id, 'owner', true);

  -- El trigger seed_business_hours ya cargó horarios por defecto:
  -- se reemplazan por los de la copia.
  delete from public.business_hours where business_id = v_business_id;
  insert into public.business_hours
  select * from jsonb_populate_recordset(null::public.business_hours, v_tables->'business_hours');

  insert into public.loyalty_programs
  select * from jsonb_populate_recordset(null::public.loyalty_programs, v_tables->'loyalty_programs');

  insert into public.services
  select * from jsonb_populate_recordset(null::public.services, v_tables->'services');

  insert into public.clients
  select * from jsonb_populate_recordset(null::public.clients, v_tables->'clients');

  -- Las columnas que apuntan a usuarias del proyecto anterior quedan vacías.
  insert into public.service_records
  select (r).* from (
    select jsonb_populate_record(null::public.service_records, row - 'registered_by') r
    from jsonb_array_elements(coalesce(v_tables->'service_records', '[]')) row
  ) q;

  insert into public.rewards
  select * from jsonb_populate_recordset(null::public.rewards, v_tables->'rewards');

  insert into public.loyalty_transactions
  select (r).* from (
    select jsonb_populate_record(null::public.loyalty_transactions, row - 'created_by') r
    from jsonb_array_elements(coalesce(v_tables->'loyalty_transactions', '[]')) row
  ) q;

  insert into public.reward_redemptions
  select (r).* from (
    select jsonb_populate_record(null::public.reward_redemptions, row - 'redeemed_by') r
    from jsonb_array_elements(coalesce(v_tables->'reward_redemptions', '[]')) row
  ) q;

  -- guard_client_appointment_state pone en "requested" todo turno insertado
  -- con source = 'client'. Durante la restauración se desactiva para que
  -- cada turno vuelva con su estado real. Si algo falla, la transacción
  -- completa (incluido este cambio) se deshace.
  v_appointments := coalesce(v_tables->'appointments', '[]');

  execute 'alter table public.appointments disable trigger guard_client_appointment_state';

  insert into public.appointments
  select (r).* from (
    select jsonb_populate_record(null::public.appointments, row - 'created_by') r
    from jsonb_array_elements(v_appointments) row
  ) q;

  execute 'alter table public.appointments enable trigger guard_client_appointment_state';

  -- Los triggers de push encolaron avisos de datos viejos: se descartan.
  delete from public.notification_outbox where business_id = v_business_id;

  return jsonb_build_object(
    'business_id', v_business_id,
    'clients', jsonb_array_length(coalesce(v_tables->'clients', '[]')),
    'service_records', jsonb_array_length(coalesce(v_tables->'service_records', '[]')),
    'appointments', jsonb_array_length(v_appointments)
  );
end;
$$;

revoke all on function public.restore_business_backup(jsonb) from public, anon;
grant execute on function public.restore_business_backup(jsonb) to authenticated;

commit;
