-- Backup round trip: export the business of 10_smoke.sql, delete every row
-- of it, restore it as another user on a "new project" and compare.
\set ON_ERROR_STOP on

insert into auth.users(id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000003', 'restorer@test');

create temporary table backup_file as
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', false) as s,
       public.export_business_backup() as data;

do $$
declare
  v_backup jsonb := (select data from backup_file);
  v_business uuid := (v_backup->>'business_id')::uuid;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
  v_failed boolean;
  t text;
begin
  assert v_backup->>'format' = 'beauty-loyalty-backup', 'format';
  assert jsonb_array_length(v_backup->'tables'->'clients') = 1, 'clients exported';
  assert jsonb_array_length(v_backup->'tables'->'service_records') = 7, 'records exported';
  assert jsonb_array_length(v_backup->'tables'->'appointments') >= 1, 'appointments exported';
  assert (select last_backup_at from public.businesses where id = v_business) is not null,
    'last_backup_at must be set';

  -- An owner who already has a business cannot restore over it.
  v_failed := false;
  begin
    perform public.restore_business_backup(v_backup);
  exception when others then v_failed := true;
  end;
  assert v_failed, 'restore must refuse a user that already has a business';

  -- A stranger cannot export.
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000002', false);
  v_failed := false;
  begin
    perform public.export_business_backup();
  exception when others then v_failed := true;
  end;
  assert v_failed, 'stranger must not export';

  -- Simulate losing the project: delete everything of the business.
  delete from public.notification_outbox where business_id = v_business;
  delete from public.push_bindings where business_id = v_business;
  delete from public.appointments where business_id = v_business;
  delete from public.reward_redemptions where business_id = v_business;
  delete from public.loyalty_transactions where business_id = v_business;
  delete from public.rewards where business_id = v_business;
  delete from public.service_records where business_id = v_business;
  delete from public.clients where business_id = v_business;
  delete from public.services where business_id = v_business;
  delete from public.loyalty_programs where business_id = v_business;
  delete from public.business_hours where business_id = v_business;
  delete from public.business_members where business_id = v_business;
  delete from public.businesses where id = v_business;

  -- Restore as a brand-new user.
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000003', false);
  v_result := public.restore_business_backup(v_backup);
  assert (v_result->>'clients')::int = 1, 'restore result';

  -- The restored user sees the business and the same data.
  assert (public.get_admin_bootstrap()->>'has_business')::boolean, 'restored business visible';
  v_after := public.export_business_backup();

  foreach t in array array['business_hours','loyalty_programs','services','clients',
    'service_records','rewards','loyalty_transactions','reward_redemptions','appointments']
  loop
    v_before := (
      select coalesce(jsonb_agg(x - 'registered_by' - 'created_by' - 'redeemed_by' order by x->>'id', x->>'weekday'), '[]')
      from jsonb_array_elements(v_backup->'tables'->t) x);
    v_after := (
      select coalesce(jsonb_agg(x - 'registered_by' - 'created_by' - 'redeemed_by' order by x->>'id', x->>'weekday'), '[]')
      from jsonb_array_elements(public.export_business_backup()->'tables'->t) x);
    assert v_before = v_after, t || ' differs after restore';
  end loop;

  assert not exists (select 1 from public.notification_outbox where business_id = v_business),
    'restore must not enqueue old notifications';

  -- Restoring twice is refused.
  v_failed := false;
  begin
    perform public.restore_business_backup(v_backup);
  exception when others then v_failed := true;
  end;
  assert v_failed, 'second restore must be refused';

  raise notice 'BACKUP TEST OK';
end;
$$;
