BELLAMIA v2.6 — HORARIOS DESDE NEGOCIO
========================================

NUEVO
-----
Admin → Negocio → Horarios de atención

La admin puede definir:
- si cada día está abierto o cerrado;
- hora de apertura;
- hora de cierre;
- intervalo/duración de agenda:
  15, 30, 45 o 60 minutos.

Ejemplo:

Lunes       09:00 → 18:00
Martes      09:00 → 18:00
Miércoles   Cerrado
Jueves      10:00 → 20:00
Viernes     10:00 → 20:00
Sábado      09:00 → 14:00
Domingo     Cerrado

Cada 30 minutos.

EFECTO
------
Después de guardar, tanto:

Admin → Nuevo turno
como
Clienta → Pedir turno

usan esa configuración automáticamente.

Si el miércoles está Cerrado:
no aparece ningún horario para el miércoles.

Si el sábado cierra 14:00 y los bloques son de 30 min:
el último horario ofrecido es 13:30.

Si un horario ya está Pendiente o Confirmado:
sigue sin aparecer.

SQL
---
Ejecutar:

supabase/migrations/014_v2_6_business_hours.sql

Este SQL:
- agrega appointment_slot_minutes a businesses;
- crea business_hours;
- mantiene 08:00–21:00 / 30 min como valores iniciales;
- agrega update_business_schedule();
- modifica available_appointment_slots() para leer la configuración;
- agrega los horarios al bootstrap del admin.

INSTALACIÓN
-----------
1. Supabase → SQL Editor:
   ejecutar 014_v2_6_business_hours.sql completo.

2. Flutter:
   flutter clean
   flutter pub get
   flutter build web --release --dart-define-from-file=config/local.json

3. Deploy:
   npx wrangler pages deploy build/web --project-name=bellamialashesstudio

PRUEBA
------
1. Admin → Negocio.
2. Horarios de atención.
3. Cerrar un día, por ejemplo miércoles.
4. Cambiar lunes a 10:00–15:00.
5. Guardar.
6. Clienta → Pedir turno.
7. Miércoles debe mostrar "No quedan horarios disponibles".
8. Lunes sólo debe ofrecer slots dentro de 10:00–15:00.

NOTA
----
v2.6 configura una sola franja continua por día.
Todavía no incluye:
- pausa de almuerzo;
- feriados/vacaciones;
- dos franjas en un mismo día.

Eso puede añadirse más adelante si el negocio lo necesita.
