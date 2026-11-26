-- Bellamia v2.4 — diagnóstico.
-- No modifica nada.

select
  a.id,
  a.created_at,
  a.updated_at,
  a.starts_at,
  a.status,
  a.source,
  trim(c.first_name || ' ' || c.last_name) as clienta,
  s.name as servicio
from public.appointments a
join public.clients c on c.id = a.client_id
join public.services s on s.id = a.service_id
where a.source = 'client'
  and a.status = 'confirmed'
order by a.created_at desc;

-- Una solicitud NUEVA hecha después de aplicar la migración 012
-- debe aparecer primero como:
--
-- source = client
-- status = requested
--
-- No conviene modificar automáticamente las filas históricas porque algunas
-- pudieron haber sido confirmadas realmente por la admin.
