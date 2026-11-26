BEAUTY LOYALTY v3.0 — CORRECCIONES Y VELOCIDAD
==============================================

QUÉ SE CORRIGIÓ
---------------
1. Ficha de la clienta.
   La app pedía get_admin_client_detail(), una función que no estaba en
   ninguna migración (se había creado a mano en la base y se perdió con las
   migraciones 002–004). Sin ella, en una base nueva la ficha quedaba vacía
   y daba error. Ahora está en 015.

2. Detalle que desaparecía.
   Al registrar un servicio, el historial recién cargado podía guardarse en
   una copia vieja de la clienta y no verse hasta volver a entrar.

3. Nombre "Bellamia" fijo en el código.
   Los textos, títulos, manifiestos PWA y enlaces de tarjeta ahora salen de
   la configuración (APP_TITLE, APP_SHORT_NAME, THEME_COLOR), así la misma
   app sirve para otro negocio.

POR QUÉ ERA LENTA Y QUÉ CAMBIÓ
-----------------------------
1. La agenda se pedía entera cada 3 segundos y cada respuesta redibujaba
   la app completa, aunque nada hubiera cambiado.
   → Ahora usa Supabase Realtime: el cambio llega solo, en el momento.
     Queda una consulta de respaldo cada 60 s, y sólo redibuja si hubo
     cambios.

2. Después de cada acción (registrar servicio, crear turno, etc.) se hacían
   2 o 3 recargas completas, una detrás de otra.
   → Ahora una sola recarga (o dos en paralelo cuando también hace falta la
     ficha), y si llegan varias pedidas a la vez se unen en una.

3. La carga del panel repetía cada ficha de clienta dos veces
   ("clientas para recordar") y calculaba 4 subconsultas por clienta.
   → Medido con 500 clientas y 6000 servicios:
       servidor: 107 ms → ~20 ms
       datos:    448 KB → 272 KB

4. Faltaban índices para pertenencia al negocio, métricas, beneficios y
   turnos por clienta. → Agregados.

5. La app no se mostraba hasta terminar de cargar el panel (pantalla en
   blanco). → Ahora aparece enseguida con un indicador de carga.

6. La tarjeta de la clienta se descargaba cada 3 s con la pestaña Turnos
   abierta. → Cada 20 s.

7. El tema de colores se recalculaba en cada redibujo. → Sólo si cambia el
   color del negocio.

INSTALACIÓN (base existente)
----------------------------
1. Supabase → SQL Editor → ejecutar COMPLETO:
     supabase/migrations/015_v3_performance_and_fixes.sql
   No borra ni modifica datos. Se puede ejecutar dos veces sin problema.

2. Compilar y publicar:
     ./scripts/build_web.sh            (Windows: .\scripts\build_web.ps1)
     npx wrangler pages deploy build/web --project-name=bellamialashesstudio

   La app nueva también funciona con una base sin la 015 (lee el formato
   anterior), pero la ficha de la clienta necesita la 015.

PRUEBA
------
1. Admin → Turnos abierto en un celular; pedir un turno desde la tarjeta
   de una clienta en otro: debe aparecer en segundos sin recargar.
2. Registrar un servicio desde la ficha: el historial se actualiza al
   instante.
3. Abrir la ficha de una clienta: muestra historial y beneficios.

REPOSITORIO
-----------
- El código está en la raíz del repositorio (antes sólo había documentos de
  planificación; ahora están en docs/planning-2025/).
- supabase/tests + scripts/test_db.sh: prueba automática de toda la base.
- GitHub Actions: CI en cada push y deploy opcional a Cloudflare Pages.
