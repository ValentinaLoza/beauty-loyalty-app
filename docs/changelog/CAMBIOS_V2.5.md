BELLAMIA v2.5 — AGENDA INTELIGENTE
===================================

CAMBIO 1 — PUSH ADMIN MÁS RÁPIDO
--------------------------------
La notificación "Nuevo turno solicitado" ahora abre:

/admin/appointments?appointment=UUID

Al entrar:
1. Bellamia pide PRIMERO sólo ese turno;
2. lo muestra arriba como "Solicitud recibida";
3. después actualiza el resto de la agenda en segundo plano.

Además get_admin_bootstrap ahora incluye los turnos, así una apertura en frío
ya tiene la agenda dentro de la primera carga del admin.

CAMBIO 2 — NO HAY DOS TURNOS EN EL MISMO HORARIO
-------------------------------------------------
La base protege:

business_id + starts_at

para estados:
requested
confirmed

Si 15:30 está pendiente o confirmado, otro turno no puede usar 15:30.

Aunque dos teléfonos intenten reservarlo al mismo instante, sólo uno entra.

CAMBIO 3 — HORARIOS MÁS INTUITIVOS
----------------------------------
Se eliminó el selector libre de hora.

Ahora:
1. Elegís el día.
2. Bellamia consulta Supabase.
3. Muestra solamente horarios disponibles.
4. Los horarios están agrupados:
   Mañana
   Tarde
   Noche

Slots actuales:
08:00 a 20:30
cada 30 minutos.

Ejemplo:
09:00  09:30  10:00
10:30  11:00  11:30

Si 10:30 ya está ocupado, no aparece.

Esto funciona tanto:
- Admin → Nuevo turno
- Admin → Editar turno
- Clienta → Pedir turno

ARCHIVOS NUEVOS/MODIFICADOS
---------------------------
lib/appointment_slot_picker.dart
lib/app_state.dart
lib/app.dart
lib/pages/admin_pages.dart
lib/pages/public_client_page.dart

SQL:
supabase/migrations/013_v2_5_agenda_slots_fast_notification.sql

ORDEN
-----
1. Supabase → SQL Editor.
2. Ejecutar COMPLETO:
   013_v2_5_agenda_slots_fast_notification.sql

3. Compilar/publicar:

flutter clean
flutter pub get
flutter build web --release --dart-define-from-file=config/local.json

npx wrangler pages deploy build/web --project-name=bellamialashesstudio

PRUEBA DISPONIBILIDAD
---------------------
A. Crear/pedir un turno para mañana a 15:30.
B. Volver a crear otro turno para mañana.
C. 15:30 NO debe aparecer.
D. Cancelar el primer turno.
E. Volver a elegir ese día.
F. 15:30 debe volver a estar disponible.

PRUEBA PUSH
-----------
A. Clienta pide turno.
B. Admin recibe push.
C. Tocar push.
D. Debe abrir Turnos y mostrar arriba:
   "Solicitud recibida"
   con ese turno.
E. El resto de la agenda se completa en segundo plano.

NOTA
----
La franja 08:00–21:00 y los bloques de 30 minutos quedan centralizados en
la función SQL. Si después querés horarios distintos por día o duración por
servicio, se puede convertir en configuración del negocio.
