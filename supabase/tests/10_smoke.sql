-- Smoke test of the critical flows. Runs after 00_supabase_stub.sql and all
-- migrations, on an EMPTY test database. Any failed check raises an error.
\set ON_ERROR_STOP on

insert into auth.users(id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'stranger@test');

-- Owner session
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', false);

do $$
declare
  v_bootstrap jsonb;
  v_business uuid;
  v_client uuid;
  v_service uuid;
  v_result jsonb;
  v_reward uuid;
  v_detail jsonb;
  v_token uuid;
  v_card jsonb;
  v_slot timestamptz;
  v_failed boolean;
  i int;
begin
  -- No business yet.
  v_bootstrap := public.get_admin_bootstrap();
  assert (v_bootstrap->>'has_business')::boolean = false, 'expected no business';

  perform public.create_business_for_current_user('Test Studio', '#8F5E78');
  select business_id into v_business from public.business_members limit 1;

  insert into public.services(business_id, name, default_price, loyalty_points)
  values (v_business, 'Lifting', 20000, 1) returning id into v_service;
  insert into public.clients(business_id, first_name, last_name)
  values (v_business, 'Ana', 'Pérez') returning id, public_token into v_client, v_token;

  -- 5 services => one reward with the default program (5 points, 20%).
  for i in 1..5 loop
    v_result := public.register_service(v_business, v_client, v_service, gen_random_uuid());
  end loop;
  assert jsonb_array_length(v_result->'rewards_issued') = 1,
    'the 5th service must issue a reward: ' || v_result::text;

  v_bootstrap := public.get_admin_bootstrap();
  assert (v_bootstrap->'metrics'->>'service_count')::int = 5, 'metrics.service_count';
  assert (v_bootstrap->'clients'->0->>'service_count')::int = 5, 'clients[0].service_count';
  assert (v_bootstrap->'clients'->0->>'available_rewards')::int = 1, 'clients[0].available_rewards';
  assert v_bootstrap->'reminder_client_ids' = jsonb_build_array(v_client),
    'client with a reward and no appointment must be in reminders';

  -- Client detail (was missing before v3).
  v_detail := public.get_admin_client_detail(v_client);
  assert jsonb_array_length(v_detail->'history') = 5, 'detail.history';
  assert v_detail->'rewards'->0->>'status' = 'available', 'detail.rewards';
  v_reward := (v_detail->'rewards'->0->>'id')::uuid;

  -- Redeem: 20% off 20000.
  v_result := public.redeem_reward(v_business, v_client, v_service, v_reward, gen_random_uuid());
  v_detail := public.get_admin_client_detail(v_client);
  assert v_detail->'rewards'->0->>'status' = 'redeemed', 'reward must be redeemed';
  assert v_detail->'rewards'->0->>'redeemed_at' is not null, 'redeemed_at';
  assert exists (
    select 1 from jsonb_array_elements(v_detail->'history') h
    where (h->>'discount_amount')::numeric = 4000
      and (h->>'final_price')::numeric = 16000
  ), 'the redemption must charge 20% less: ' || (v_detail->'history')::text;

  -- Idempotency: the same key twice registers once.
  v_result := public.register_service(v_business, v_client, v_service,
    '00000000-0000-0000-0000-0000000000aa');
  v_result := public.register_service(v_business, v_client, v_service,
    '00000000-0000-0000-0000-0000000000aa');
  assert (v_result->>'idempotent_replay')::boolean, 'same idempotency key must replay';

  -- Anonymous client card and appointment request.
  perform set_config('request.jwt.claim.sub', '', false);
  v_card := public.get_public_client_card(v_token);
  assert v_card is not null, 'public card';

  select s into v_slot
  from unnest(
    (select array_agg(x::timestamptz)
     from jsonb_array_elements_text(
       to_jsonb(public.get_public_available_appointment_slots(
         v_token, (current_date + 7)::date))) x)
  ) s
  limit 1;
  assert v_slot is not null, 'there must be free slots next week';

  perform public.request_public_appointment(v_token, v_service, v_slot, null);

  v_failed := false;
  begin
    perform public.request_public_appointment(v_token, v_service, v_slot, null);
  exception when others then
    v_failed := true;
  end;
  assert v_failed, 'the same slot cannot be booked twice';

  -- A stranger cannot read the owner's data.
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000002', false);
  assert (public.get_admin_bootstrap()->>'has_business')::boolean = false,
    'stranger must not see a business';
  v_failed := false;
  begin
    perform public.get_admin_client_detail(v_client);
  exception when others then
    v_failed := true;
  end;
  assert v_failed, 'stranger must not read client detail';

  raise notice 'SMOKE TEST OK';
end;
$$;
