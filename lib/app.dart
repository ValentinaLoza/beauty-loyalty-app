import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_state.dart';
import 'config.dart';
import 'pages/admin_pages.dart';
import 'pages/login_page.dart';
import 'pages/public_client_page.dart';
import 'pages/setup_page.dart';
import 'push_notifications.dart';
import 'widgets.dart';

class _MissingClientTokenPage extends StatelessWidget {
  const _MissingClientTokenPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.credit_card_outlined, size: 48),
                SizedBox(height: 16),
                Text(
                  'No pudimos identificar tu tarjeta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Abrí nuevamente el enlace privado que te envió Bellamia '
                  'y, cuando veas tu tarjeta, agregala a la pantalla de inicio.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BeautyLoyaltyApp extends StatefulWidget {
  const BeautyLoyaltyApp({super.key, required this.appState});
  final AppState appState;

  @override
  State<BeautyLoyaltyApp> createState() => _BeautyLoyaltyAppState();
}

class _BeautyLoyaltyAppState extends State<BeautyLoyaltyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      refreshListenable: widget.appState,
      redirect: (context, state) {
        final path = state.uri.path;

        // Client entry points are ALWAYS public, even if this browser
        // also has an authenticated admin session.
        if (path.startsWith('/card/') ||
            path == '/client' ||
            path == '/client/index.html' ||
            path.startsWith('/c/')) {
          return null;
        }

        final isAdminPath =
            path == '/admin' || path.startsWith('/admin/');

        if (!widget.appState.isAuthenticated) {
          if (isAdminPath) {
            return path == '/admin/login' ? null : '/admin/login';
          }
          return path == '/login' ? null : '/login';
        }

        if (widget.appState.needsBusinessSetup) {
          if (isAdminPath) {
            return path == '/admin/setup' ? null : '/admin/setup';
          }
          return path == '/setup' ? null : '/setup';
        }

        if (path == '/' ||
            path == '/login' ||
            path == '/setup' ||
            path == '/admin/login' ||
            path == '/admin/setup') {
          return '/admin';
        }

        return null;
      },
      routes: [
        // Normal browser login/setup.
        GoRoute(
          path: '/login',
          builder: (_, __) => LoginPage(appState: widget.appState),
        ),
        GoRoute(
          path: '/setup',
          builder: (_, __) => BusinessSetupPage(appState: widget.appState),
        ),

        // Installed ADMIN PWA keeps all auth/setup navigation inside /admin.
        GoRoute(
          path: '/admin/login',
          builder: (_, __) => LoginPage(appState: widget.appState),
        ),
        GoRoute(
          path: '/admin/setup',
          builder: (_, __) => BusinessSetupPage(appState: widget.appState),
        ),

        // Administration uses one persistent shell. Bottom navigation is
        // not recreated or stacked when changing tabs.
        ShellRoute(
          builder: (_, state, child) => AdminNavigationShell(
            appState: widget.appState,
            currentPath: state.uri.path,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/admin',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminDashboardPage(
                  appState: widget.appState,
                ),
              ),
            ),
            GoRoute(
              path: '/admin/clients',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminClientsPage(
                  appState: widget.appState,
                ),
              ),
            ),
            GoRoute(
              path: '/admin/clients/:clientId',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminClientDetailPage(
                  appState: widget.appState,
                  clientId: state.pathParameters['clientId']!,
                ),
              ),
            ),
            GoRoute(
              path: '/admin/services',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminServicesPage(
                  appState: widget.appState,
                ),
              ),
            ),
            GoRoute(
              path: '/admin/loyalty',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminLoyaltyPage(
                  appState: widget.appState,
                ),
              ),
            ),
            GoRoute(
              path: '/admin/appointments',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminAppointmentsPage(
                  appState: widget.appState,
                  initialAppointmentId:
                      state.uri.queryParameters['appointment'],
                ),
              ),
            ),
            GoRoute(
              path: '/admin/business',
              pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey,
                child: AdminBusinessPage(
                  appState: widget.appState,
                ),
              ),
            ),
          ],
        ),

        // Canonical client PWA route.
        //
        // The token stays in the URL itself. This is important on iOS:
        // the installed Home Screen web app does not need to inherit
        // localStorage from Safari to know which client it belongs to.
        GoRoute(
          path: '/card/:token',
          builder: (_, state) => PublicClientPage(
            appState: widget.appState,
            token: state.pathParameters['token']!,
          ),
        ),

        // Canonical client PWA entry point.
        //
        // The first browser visit carries ?token=UUID and the public page
        // persists it. The installed PWA later starts at this same physical
        // HTML file without a query string and recovers the saved token.
        // Cloudflare Pages uses clean URLs and canonicalizes
        // /client/index.html to /client. Therefore /client is the
        // canonical public client route.
        GoRoute(
          path: '/client',
          builder: (_, state) {
            final queryToken =
                state.uri.queryParameters['token']?.trim() ?? '';
            final savedToken =
                PushNotifications.clientPwaTarget.trim();
            final token =
                queryToken.isNotEmpty ? queryToken : savedToken;

            if (token.isEmpty) {
              return const _MissingClientTokenPage();
            }

            return PublicClientPage(
              appState: widget.appState,
              token: token,
            );
          },
        ),

        // Compatibility if a host/browser does not strip index.html.
        GoRoute(
          path: '/client/index.html',
          builder: (_, state) {
            final queryToken =
                state.uri.queryParameters['token']?.trim() ?? '';
            final savedToken =
                PushNotifications.clientPwaTarget.trim();
            final token =
                queryToken.isNotEmpty ? queryToken : savedToken;

            if (token.isEmpty) {
              return const _MissingClientTokenPage();
            }

            return PublicClientPage(
              appState: widget.appState,
              token: token,
            );
          },
        ),

        // Legacy route kept only for compatibility inside Flutter.
        // New copied links no longer depend on this server path.
        GoRoute(
          path: '/c/:token',
          builder: (_, state) => PublicClientPage(
            appState: widget.appState,
            token: state.pathParameters['token']!,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (_, __) {
        final primary = colorFromHex(
          widget.appState.business?.primaryColorHex ?? '#8F5E78',
        );
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: widget.appState.business?.name ?? AppConfig.fallbackTitle,
          routerConfig: _router,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: primary),
            scaffoldBackgroundColor: const Color(0xFFFFF9FB),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        );
      },
    );
  }
}
