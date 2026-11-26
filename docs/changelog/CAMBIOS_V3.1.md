BEAUTY LOYALTY v3.1 — COPIAS DE SEGURIDAD
=========================================

NUEVO
-----
Admin → Negocio → Copia de seguridad → "Descargar copia".
Baja un archivo .json con clientas, servicios, historial, beneficios,
canjes, turnos, horarios y programa de fidelización.

Si pasan 14 días sin descargar una copia (y hay clientas cargadas), el
Dashboard muestra un recordatorio con el mismo botón.

Restaurar: en un proyecto Supabase NUEVO, la administradora entra por
primera vez y, en vez de crear el negocio, toca "Restaurar copia de
seguridad" y elige el archivo. Vuelve todo tal cual, con los mismos
enlaces de tarjeta de cada clienta.

Por seguridad, restaurar sólo funciona en una cuenta que todavía no tiene
negocio: nunca pisa ni mezcla datos.

No se copian: las suscripciones a notificaciones (cada celular vuelve a
tocar "Activar notificaciones") ni la cuenta de la administradora (se crea
en Authentication del proyecto nuevo).

SQL
---
supabase/migrations/016_v3_1_backups.sql
(para el proyecto actual alcanza con ejecutar sólo este archivo)

DÓNDE GUARDAR LAS COPIAS
------------------------
Fuera del celular: Google Drive, o mandártela por mail. El archivo tiene
datos personales de las clientas: no lo subas a GitHub ni lo compartas.

NOTIFICACIONES
--------------
docs/PUSH_SETUP.md explica cómo activarlas en un proyecto nuevo.
