import 'dart:async';

import 'package:flutter/material.dart';

import '../appointment_slot_picker.dart';
import '../app_state.dart';
import '../models.dart';
import '../push_notifications.dart';
import '../widgets.dart';

class PublicClientPage extends StatefulWidget {
  const PublicClientPage({
    super.key,
    required this.appState,
    required this.token,
  });
  final AppState appState;
  final String token;

  @override
  State<PublicClientPage> createState() => _PublicClientPageState();
}

class _PublicClientPageState extends State<PublicClientPage>
    with WidgetsBindingObserver {
  PublicCardData? data;
  Object? loadError;
  bool initialLoading = true;
  bool _refreshing = false;
  Timer? _appointmentSyncTimer;
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Keep the manifest tied to this exact client token so an installed
    // iPhone/iPad Home Screen app reopens /card/<token>.
    PushNotifications.prepareClientInstall(widget.token);

    _loadCard();
  }

  @override
  void dispose() {
    _appointmentSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCard(silent: true);
    }
  }

  Future<void> _loadCard({bool silent = false}) async {
    if (_refreshing || !mounted) return;

    _refreshing = true;

    try {
      final next =
          await widget.appState.fetchPublicCard(widget.token);

      if (!mounted) return;

      setState(() {
        data = next;
        loadError = null;
        initialLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      // During background polling keep the last good card visible.
      if (data == null || !silent) {
        setState(() {
          loadError = error;
          initialLoading = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  void _configureAppointmentSync() {
    _appointmentSyncTimer?.cancel();
    _appointmentSyncTimer = null;

    if (selectedIndex != 1) return;

    _appointmentSyncTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadCard(silent: true),
    );
  }

  void _selectTab(int index) {
    if (index == selectedIndex) {
      if (index == 1) {
        _loadCard(silent: true);
      }
      return;
    }

    setState(() => selectedIndex = index);
    _configureAppointmentSync();

    if (index == 1) {
      _loadCard(silent: true);
    }
  }

  Future<void> activateNotifications() async {
    try {
      final env = PushNotifications.environment();

      if (env.isIos && !env.isStandalone) {
        if (!mounted) return;

        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Recibí tus recordatorios'),
            content: const Text(
              'En iPhone/iPad: abrí ESTA tarjeta en Safari y esperá a que '
              'termine de cargar. Después tocá Compartir → Agregar a '
              'pantalla de inicio. El nuevo ícono quedará vinculado a esta '
              'tarjeta. Luego abrilo y activá las notificaciones.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(d),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }

      final subscription =
          await PushNotifications.subscribe();

      final saved = await widget.appState
          .registerClientPushSubscription(
        token: widget.token,
        subscription: subscription,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Recordatorios activados en este dispositivo ✨'
                : widget.appState.errorMessage ??
                    'No se pudo activar.',
          ),
        ),
      );

      setState(() {});
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            PushNotifications.friendlyError(error),
          ),
        ),
      );
    }
  }

  Widget _activeTab(PublicCardData current) {
    return switch (selectedIndex) {
      0 => _CardTab(
          data: current,
          onActivateNotifications: activateNotifications,
        ),
      1 => _AppointmentsTab(
          appState: widget.appState,
          data: current,
          token: widget.token,
          onChanged: () {
            _loadCard(silent: true);
          },
        ),
      2 => _HistoryTab(data: current),
      3 => _RewardsTab(data: current),
      _ => _CardTab(
          data: current,
          onActivateNotifications: activateNotifications,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (initialLoading && data == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (data == null) {
      return Scaffold(
        body: Center(
          child: Text(
            loadError == null
                ? 'Este enlace no está disponible.'
                : 'No pudimos actualizar tu tarjeta.',
          ),
        ),
      );
    }

    final current = data!;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor:
              colorFromHex(current.business.primaryColorHex),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            current.business.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: () => _loadCard(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(18),
                // Only the selected section exists in the widget tree.
                // No IndexedStack / hidden pages underneath.
                child: _activeTab(current),
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.credit_card_outlined),
              label: 'Tarjeta',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Turnos',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Historial',
            ),
            NavigationDestination(
              icon: Icon(Icons.card_giftcard_outlined),
              label: 'Beneficios',
            ),
          ],
        ),
      ),
    );
  }
}


class _CardTab extends StatelessWidget {
  const _CardTab({
    required this.data,
    required this.onActivateNotifications,
  });

  final PublicCardData data;
  final VoidCallback onActivateNotifications;

  @override
  Widget build(BuildContext context) {
    final env = PushNotifications.environment();

    return ListView(
      children: [
        PageTitle(
          'Hola, ${data.client.firstName} ✨',
          subtitle: 'Esta es tu tarjeta digital.',
        ),
        const SizedBox(height: 16),
        LoyaltyCardWidget(
          client: data.client,
          pointsRequired: data.loyalty.pointsRequired,
          rewardPercent: data.loyalty.rewardPercent,
          businessName: data.business.name,
        ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(
                Icons.notifications_active_outlined,
              ),
            ),
            title: Text(
              env.permission == 'granted'
                  ? 'Recordatorios habilitados'
                  : 'Recibí recordatorios',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              env.permission == 'granted'
                  ? 'Este dispositivo puede recibir avisos de '
                      'turnos y beneficios.'
                  : env.isIos && !env.isStandalone
                      ? 'En iPhone agregá Bellamia a la pantalla '
                          'de inicio para activar notificaciones.'
                      : 'Te avisamos cuando confirmen o cambien '
                          'tu turno y cuando tengas un beneficio.',
            ),
            trailing: env.permission == 'granted'
                ? const Icon(Icons.check_circle_outline)
                : IconButton(
                    tooltip: 'Activar',
                    onPressed: onActivateNotifications,
                    icon: const Icon(
                      Icons.arrow_forward_ios,
                    ),
                  ),
          ),
        ),
        if (data.client.availableRewards > 0) ...[
          const SizedBox(height: 14),
          Card(
            color:
                Theme.of(context).colorScheme.primaryContainer,
            child: const ListTile(
              leading: Icon(Icons.card_giftcard),
              title: Text(
                '¡Tenés un beneficio disponible!',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle:
                  Text('Pedí un turno para aprovecharlo.'),
            ),
          ),
        ],
      ],
    );
  }
}

class _AppointmentsTab extends StatelessWidget {
  const _AppointmentsTab({
    required this.appState,
    required this.data,
    required this.token,
    required this.onChanged,
  });

  final AppState appState;
  final PublicCardData data;
  final String token;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      PageTitle(
        'Mis turnos',
        subtitle: 'Podés pedir una fecha y el negocio la confirma.',
        trailing: FilledButton.icon(
          onPressed: () => request(context),
          icon: const Icon(Icons.add),
          label: const Text('Pedir'),
        ),
      ),
      const SizedBox(height: 14),
      if (data.appointments.isEmpty)
        const EmptyState(
          icon: Icons.calendar_month,
          title: 'No tenés turnos próximos',
          message: 'Pedí uno desde el botón de arriba.',
        )
      else
        ...data.appointments.map((a) => Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.calendar_month)),
            title: Text(a.serviceName),
            subtitle: Text(formatDateTime(a.startsAt.toLocal())),
            trailing: Chip(
              label: Text(a.status == 'requested' ? 'Pendiente' : 'Confirmado'),
            ),
          ),
        )),
    ]);
  }

  Future<void> request(BuildContext context) async {
    final active = data.services.where((s) => s.active).toList();
    if (active.isEmpty) return;
    var serviceId = active.first.id;
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Pedir turno'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: serviceId,
                items: active.map((s) => DropdownMenuItem(
                  value: s.id,
                  child: Text(s.name),
                )).toList(),
                onChanged: (v) => setDialog(() => serviceId = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Comentario opcional',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Elegir fecha')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;

    final startsAt = await pickAvailableAppointmentSlot(
      context,
      loadSlots: (day) =>
          appState.getPublicAvailableAppointmentSlots(
        token: token,
        day: day,
      ),
    );

    if (startsAt == null || !context.mounted) return;
    final saved = await appState.requestPublicAppointment(
      token: token,
      serviceId: serviceId,
      startsAt: startsAt,
      notes: notes.text,
    );

    if (!context.mounted) return;

    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud enviada. El negocio debe confirmarla.',
          ),
        ),
      );
      onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appState.errorMessage ??
                'No se pudo pedir el turno.',
          ),
        ),
      );
    }
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.data});
  final PublicCardData data;

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      const PageTitle('Historial'),
      const SizedBox(height: 12),
      ...data.history.map((e) => Card(
        child: ListTile(
          title: Text(e.serviceName),
          subtitle: Text(formatDateTime(e.performedAt.toLocal())),
          trailing: Text(formatMoney(e.finalPrice)),
        ),
      )),
    ]);
  }
}

class _RewardsTab extends StatelessWidget {
  const _RewardsTab({required this.data});
  final PublicCardData data;

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      PageTitle(
        'Beneficios',
        subtitle: '${data.client.availableRewards} disponibles',
      ),
      const SizedBox(height: 12),
      ...data.rewards.map((r) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.card_giftcard)),
          title: Text(r.title),
          subtitle: Text(formatDate(r.issuedAt.toLocal())),
          trailing: Chip(
            label: Text(r.status == RewardStatus.available ? 'Disponible' : 'Utilizado'),
          ),
        ),
      )),
    ]);
  }
}
