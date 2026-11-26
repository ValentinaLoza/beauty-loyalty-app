-- BELLAMIA — RESET FINAL ANTES DE ENTREGAR A PRODUCCIÓN
-- NO EJECUTAR hasta terminar TODAS las pruebas.
-- Conserva negocio, admin, servicios, fidelización y sistema push.

begin;

do $$
declare
  v_business_id uuid :=
    'REEMPLAZAR-AQUI-CON-EL-BUSINESS-ID';
begin

  if not exists (
    select 1 from public.businesses where id = v_business_id
  ) then
    raise exception 'BUSINESS_ID_INVALIDO. Cancelando limpieza.';
  end if;

  delete from public.notification_delivery_log
  where outbox_id in (
    select id
    from public.notification_outbox
    where business_id = v_business_id
  );

  delete from public.notification_outbox
  where business_id = v_business_id;

  delete from public.push_bindings
  where business_id = v_business_id;

  delete from public.push_endpoints pe
  where not exists (
    select 1
    from public.push_bindings pb
    where pb.endpoint_id = pe.id
  );

  delete from public.reward_redemptions rr
  where rr.reward_id in (
    select r.id
    from public.rewards r
    where r.business_id = v_business_id
  );

  delete from public.loyalty_transactions
  where business_id = v_business_id;

  delete from public.rewards
  where business_id = v_business_id;

  delete from public.appointments
  where business_id = v_business_id;

  delete from public.service_records
  where business_id = v_business_id;

  delete from public.clients
  where business_id = v_business_id;

end $$;

commit;

-- Después del reset:
-- Admin real → Negocio → Notificaciones → Activar.
-- Cada clienta real activa desde su tarjeta.
