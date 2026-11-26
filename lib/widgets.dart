import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_state.dart';
import 'models.dart';

Color colorFromHex(String value) {
  final cleaned = value.replaceAll('#', '').trim();
  final parsed = cleaned.length == 6
      ? int.tryParse('FF$cleaned', radix: 16)
      : null;
  return Color(parsed ?? 0xFF8F5E78);
}

String formatMoney(double value) {
  final number = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < number.length; i++) {
    final reverseIndex = number.length - i;
    buffer.write(number[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write('.');
  }
  return '\$$buffer';
}

String formatDate(DateTime date) {
  const months = [
    'ene','feb','mar','abr','may','jun',
    'jul','ago','sep','oct','nov','dic'
  ];
  return '${date.day.toString().padLeft(2, '0')} '
      '${months[date.month - 1]} ${date.year}';
}

String formatDateTime(DateTime date) =>
    '${formatDate(date)} · ${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(color: Colors.black54)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                Text(label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoyaltyCardWidget extends StatelessWidget {
  const LoyaltyCardWidget({
    super.key,
    required this.client,
    required this.pointsRequired,
    required this.rewardPercent,
    required this.businessName,
  });

  final ClientRecord client;
  final int pointsRequired;
  final double rewardPercent;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final completed = client.points.clamp(0, pointsRequired);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, Colors.white, .20)!,
            Color.lerp(primary, Colors.white, .38)!,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                businessName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (client.availableRewards > 0)
              Text('🎁 ${client.availableRewards}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  )),
          ]),
          const SizedBox(height: 24),
          Text(client.fullName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              )),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(
              pointsRequired,
              (index) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < completed
                      ? Colors.white
                      : Colors.white.withOpacity(.18),
                ),
                child: Icon(
                  index < completed ? Icons.check : Icons.auto_awesome,
                  color: index < completed ? primary : Colors.white70,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('${client.points} de $pointsRequired servicios',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 4),
          Text(
            client.availableRewards > 0
                ? 'Tenés ${client.availableRewards} beneficio disponible'
                : 'Faltan ${pointsRequired - client.points} para '
                    '${rewardPercent.toStringAsFixed(0)}% OFF',
            style: TextStyle(color: Colors.white.withOpacity(.88)),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }
}

/// Compatibility wrapper used by the existing admin page bodies.
///
/// Navigation is now owned by [AdminNavigationShell], so individual tabs no
/// longer create another Scaffold on top of the previous tab.
class AdminScaffold extends StatelessWidget {
  const AdminScaffold({
    super.key,
    required this.appState,
    required this.selectedIndex,
    required this.child,
  });

  final AppState appState;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Persistent administration shell.
///
/// There is one AppBar, one body container and one NavigationBar. Changing
/// tabs only replaces [child]; no full-screen Scaffold is pushed over another.
class AdminNavigationShell extends StatelessWidget {
  const AdminNavigationShell({
    super.key,
    required this.appState,
    required this.currentPath,
    required this.child,
  });

  final AppState appState;
  final String currentPath;
  final Widget child;

  static const routes = [
    '/admin',
    '/admin/clients',
    '/admin/services',
    '/admin/loyalty',
    '/admin/appointments',
    '/admin/business',
  ];

  int get selectedIndex {
    if (currentPath == '/admin') return 0;
    if (currentPath.startsWith('/admin/clients')) return 1;
    if (currentPath.startsWith('/admin/services')) return 2;
    if (currentPath.startsWith('/admin/loyalty')) return 3;
    if (currentPath.startsWith('/admin/appointments')) return 4;
    if (currentPath.startsWith('/admin/business')) return 5;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        label: 'Inicio',
      ),
      NavigationDestination(
        icon: Icon(Icons.people_outline),
        label: 'Clientas',
      ),
      NavigationDestination(
        icon: Icon(Icons.spa_outlined),
        label: 'Servicios',
      ),
      NavigationDestination(
        icon: Icon(Icons.card_giftcard_outlined),
        label: 'Fidelidad',
      ),
      NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        label: 'Turnos',
      ),
      NavigationDestination(
        icon: Icon(Icons.storefront_outlined),
        label: 'Negocio',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          appState.business?.name ?? 'Loyalty Studio',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () async {
              await appState.refreshAdminData();
              if (currentPath.startsWith('/admin/appointments')) {
                await appState.loadAppointments();
              }
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: appState.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              child: child,
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == selectedIndex) return;
          context.go(routes[index]);
        },
        destinations: destinations,
      ),
    );
  }
}
