BELLAMIA v2.4 — SOLICITUD PENDIENTE + PUSH A TURNOS
=======================================================

PROBLEMA 1
----------
Al tocar la notificación "Nuevo turno solicitado", el service worker recorría
las ventanas Bellamia y utilizaba la PRIMERA que encontraba.

Si existía una tarjeta de clienta, otra PWA o una ventana anterior, podía
enfocar esa ventana y no abrir Admin → Turnos.

CORRECCIÓN
----------
Para una URL /admin/... el push service worker ahora busca únicamente una
ventana cuyo pathname también sea /admin/....

Si existe:
- la navega exactamente a /admin/appointments;
- luego la enfoca.

Si no existe:
- abre una ventana nueva exactamente en /admin/appointments.

Para /card/... hace lo mismo pero exclusivamente con la PWA clienta.

PROBLEMA 2
----------
Una solicitud realizada por la clienta debe ser:

source = client
status = requested

y la ADMIN debe decidir:
requested → confirmed
o
requested → cancelled

v2.4 lo blinda también en PostgreSQL.

Aunque un frontend viejo intentara crear una solicitud clienta como confirmed,
el trigger la fuerza a requested.

Además una transición desde requested necesita:
- auth.uid() válido;
- pertenecer al negocio como owner/admin/employee.

Por lo tanto una clienta/usuario anónimo no puede auto-confirmarse.

IMPORTANTE
----------
Los turnos creados directamente por la ADMIN continúan naciendo Confirmados.
Eso es intencional: si la propia admin crea el turno, no necesita aprobar su
propia carga.

ARCHIVOS MODIFICADOS
--------------------
web/push-sw.js

NUEVOS
------
supabase/migrations/012_v2_4_appointment_request_state_push_routes.sql
supabase/DIAGNOSTICO_SOLICITUDES_AUTO_CONFIRMADAS.sql

ORDEN
-----
1. Supabase → SQL Editor.
2. Ejecutar COMPLETO:
   012_v2_4_appointment_request_state_push_routes.sql

3. Publicar el frontend:

flutter clean
flutter pub get
flutter build web --release --dart-define-from-file=config/local.json

npx wrangler pages deploy build/web --project-name=bellamialashesstudio

4. En el iPhone/admin es importante que se actualice el service worker.
   Cerrar completamente Bellamia y volver a abrirla después del deploy.

PRUEBA
------
A. Clienta → Pedir turno.

En la clienta:
Pendiente

En Supabase:
source = client
status = requested

En admin:
debe aparecer "Pendiente" y el menú debe ofrecer:
Confirmar
Cancelar

B. Tocar notificación admin.

Debe abrir:
Admin → Turnos

URL:
 /admin/appointments

C. Admin → Confirmar.

Recién EN ESE MOMENTO:
status = confirmed

y la clienta recibe:
"Tu turno fue confirmado ✨"

NO HACE FALTA RESET AÚN.
Primero probar una solicitud completamente nueva.
