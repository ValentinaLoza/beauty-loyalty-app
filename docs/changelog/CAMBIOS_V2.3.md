BELLAMIA v2.3 — AUTOSYNC DE TURNOS + NAVEGACIÓN LIMPIA
===========================================================

1. TURNOS EN TIEMPO CASI REAL
-----------------------------
La notificación push ya llegaba inmediatamente, pero las pantallas tenían
una copia de los turnos obtenida cuando se habían abierto.

Ahora:

ADMIN → sección Turnos
- consulta Supabase cada 3 segundos;
- sólo mientras Turnos está abierto;
- al volver a la PWA desde segundo plano refresca inmediatamente;
- al salir de Turnos el timer se destruye.

CLIENTA → sección Turnos
- refresca la tarjeta/turnos cada 3 segundos;
- sólo mientras Turnos está seleccionado;
- al volver a abrir la PWA refresca inmediatamente;
- al cambiar a Tarjeta/Historial/Beneficios deja de consultar.

No se hace polling permanente de toda la aplicación.

2. NAVEGACIÓN ADMIN SIN APILADO
-------------------------------
Antes cada sección del admin construía un AdminScaffold completo.

Visualmente:
Scaffold Inicio
→ Scaffold Clientas
→ Scaffold Servicios
...

Aunque context.go reemplazaba la ubicación, las transiciones y el Scaffold
recreado daban sensación de páginas superpuestas.

Ahora GoRouter usa ShellRoute:

AdminNavigationShell
├── AppBar único
├── contenido actual
└── NavigationBar única

Las secciones usan NoTransitionPage, así que tocar la barra inferior cambia
el contenido directamente, sin animación de una página encima de otra.

3. CLIENTA SIN INDEXEDSTACK
---------------------------
Antes Tarjeta / Turnos / Historial / Beneficios estaban dentro de IndexedStack.
Eso conservaba cuatro páginas montadas al mismo tiempo, aunque sólo una fuera
visible.

Ahora sólo se construye la pestaña seleccionada.

ARCHIVOS MODIFICADOS
--------------------
lib/app.dart
lib/widgets.dart
lib/pages/admin_pages.dart
lib/pages/public_client_page.dart
pubspec.yaml

NO HAY MIGRACIÓN SQL NUEVA.
La v2.3 no cambia tablas ni funciones de Supabase.

INSTALACIÓN
-----------
Usar sobre v2.2, conservando la migración 011 ya aplicada.

flutter clean
flutter pub get
flutter build web --release --dart-define-from-file=config/local.json

npx wrangler pages deploy build/web --project-name=bellamialashesstudio

PRUEBA
------
A) Abrir Admin → Turnos.
B) Desde el teléfono de una clienta pedir un turno.
C) La notificación admin debe llegar al instante.
D) Sin tocar actualizar, en un máximo aproximado de 3 segundos debe aparecer
   el turno en Admin → Turnos.

Luego:
E) Admin confirma/modifica el turno.
F) En la clienta, dejando abierta la pestaña Turnos, el cambio debe verse en
   máximo aproximado de 3 segundos.

NAVEGACIÓN
----------
En Admin tocar:
Inicio → Clientas → Servicios → Fidelidad → Turnos → Negocio

La AppBar y barra inferior permanecen; sólo cambia el contenido central.
No debe verse una pantalla desplazándose/apilándose sobre la anterior.
