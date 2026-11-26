-- Bellamia v1.6 — cierre de pruebas + automatización productiva

delete from public.notification_delivery_log
where outbox_id in (
  select id
  from public.notification_outbox
  where event_type = 'admin_test'
);

delete from public.notification_outbox
where event_type = 'admin_test';

drop function if exists public.enqueue_admin_test_push();

create extension if not exists pg_cron;

select cron.schedule(
  'bellamia-push-reminders',
  '0 * * * *',
  $$ select public.enqueue_scheduled_push_notifications(); $$
);
