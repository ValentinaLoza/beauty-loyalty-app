-- Ejecutar DESPUÉS de 011_v2_2_appointment_loyalty_atomic.sql
-- Solo diagnóstico. No modifica datos.

select
  a.id as appointment_id,
  a.starts_at,
  a.status,
  a.service_record_id,
  trim(c.first_name || ' ' || c.last_name) as clienta,
  s.name as servicio
from public.appointments a
join public.clients c on c.id = a.client_id
join public.services s on s.id = a.service_id
where a.status = 'completed'
  and a.service_record_id is null
order by a.starts_at desc;

-- Las filas que aparezcan son turnos de prueba completados con el sistema
-- anterior. No sumaron tarjeta porque el código viejo solo cambiaba status.
-- Como luego se hará el RESET FINAL, no se backfillean automáticamente.
