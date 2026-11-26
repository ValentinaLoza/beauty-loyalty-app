BELLAMIA v2.2 — TURNOS + FIDELIDAD CORREGIDOS
================================================

PROBLEMA ENCONTRADO EN EL ZIP COMPLETO
---------------------------------------
"Marcar realizado" hacía solamente:

appointments.status = 'completed'

No llamaba register_service ni redeem_reward.
Por eso:
- el turno figuraba Realizado;
- la tarjeta NO sumaba servicio;
- no sumaba puntos;
- el historial no se actualizaba;
- el beneficio quedaba desconectado del turno.

Además refreshAdminData reconstruía ClientRecord solo con datos resumen.
Eso podía vaciar temporalmente client.rewards y ocultar el botón Canjear
aunque Supabase todavía tuviera el reward disponible.

CAMBIO v2.2
-----------
Al completar un turno ahora se ejecuta UNA transacción PostgreSQL:

Turno confirmado
      ↓
complete_appointment()
      ↓
service_records
      ↓
loyalty_transactions
      ↓
reward opcional
      ↓
appointments.completed

Si falla una parte, se revierte todo.

SI HAY BENEFICIO
----------------
Al tocar:
Turnos → ... → Marcar realizado

aparece:
"Aplicar beneficio XX% OFF"

Por defecto queda seleccionado.
Si se desmarca:
- el servicio igualmente suma a la tarjeta;
- el beneficio NO se pierde;
- queda disponible para otro servicio.

SERVICIOS SIN TURNO
-------------------
Los botones manuales:
- Registrar servicio
- Canjear

siguen existiendo para una clienta que vino sin turno.

SEGURIDAD
---------
La base agrega un trigger que impide volver a marcar un turno completed
sin crear su service_record.

Así, incluso una versión vieja cacheada del frontend no puede volver a
generar el mismo problema silenciosamente.

ARCHIVOS IMPORTANTES MODIFICADOS
--------------------------------
lib/app_state.dart
lib/pages/admin_pages.dart

NUEVOS
------
supabase/migrations/011_v2_2_appointment_loyalty_atomic.sql
supabase/DIAGNOSTICO_TURNOS_V2_2.sql

ORDEN PARA PROBAR
-----------------
1. Copiar este proyecto/archivos.
2. Supabase → SQL Editor:
   ejecutar COMPLETO:
   011_v2_2_appointment_loyalty_atomic.sql

3. Compilar:
   flutter build web --release --dart-define-from-file=config/local.json

4. Publicar:
   npx wrangler pages deploy build/web --project-name=bellamialashesstudio

5. Crear una clienta/turno NUEVO de prueba.
6. Confirmar turno.
7. Turnos → Marcar realizado.

SIN BENEFICIO:
debe sumar el servicio y su punto.

CON BENEFICIO:
el diálogo ofrece aplicarlo.
Si se aplica:
- reward → redeemed;
- descuento guardado;
- servicio aparece en historial;
- el servicio también acredita sus puntos.

TURNOS VIEJOS
-------------
Los turnos que ya marcaste como "Realizado" con la versión rota NO se
convierten automáticamente en servicios.

Podés identificarlos ejecutando:
supabase/DIAGNOSTICO_TURNOS_V2_2.sql

Como todavía son datos de prueba y luego haremos el reset final, es más
seguro NO inventar historial retroactivo automáticamente.

NO EJECUTAR AÚN
---------------
FINAL_RESET_BEFORE_HANDOFF.sql

Primero comprobar el flujo completo con un turno nuevo.
