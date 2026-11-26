// PATCH v1.3 — reemplazá tu lib/pages/admin_pages.dart por este archivo.
import 'dart:async';

// Incluye todo lo de v1.2 + eliminación segura.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../appointment_slot_picker.dart';
import '../app_state.dart';
import '../models.dart';
import '../push_notifications.dart';
import '../widgets.dart';

Future<bool> confirmDanger(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Eliminar',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, required this.appState});
  final AppState appState;

  Future<void> sendReminder(BuildContext context, ClientRecord client) async {
    final url = appState.publicUrlFor(client);
    final business = appState.business?.name ?? 'el emprendimiento';
    final message =
        'Hola ${client.firstName} ✨ Tenés un beneficio disponible en $business. '
        'Si querés aprovecharlo podés ver tu tarjeta y pedir un turno acá:\n$url';
    final digits = client.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = digits.isNotEmpty
        ? Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}')
        : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final m = appState.metrics;
    return AdminScaffold(
      appState: appState,
      selectedIndex: 0,
      child: RefreshIndicator(
        onRefresh: appState.refreshAdminData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const PageTitle(
              'Dashboard',
              subtitle: 'Actividad, métricas y oportunidades del negocio.',
            ),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (_, constraints) {
              final width = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: width, child: StatCard(
                    icon: Icons.people, label: 'Clientas', value: '${m.clientCount}')),
                  SizedBox(width: width, child: StatCard(
                    icon: Icons.spa, label: 'Servicios este mes', value: '${m.servicesThisMonth}')),
                  SizedBox(width: width, child: StatCard(
                    icon: Icons.payments, label: 'Facturación este mes', value: formatMoney(m.revenueThisMonth))),
                  SizedBox(width: width, child: StatCard(
                    icon: Icons.calendar_month, label: 'Próximos turnos', value: '${m.upcomingAppointments}')),
                  SizedBox(width: width, child: StatCard(
                    icon: Icons.card_giftcard, label: 'Beneficios disponibles', value: '${m.availableRewards}')),
                  SizedBox(width: width, child: StatCard(
                    icon: Icons.receipt_long, label: 'Facturación histórica', value: formatMoney(m.revenue))),
                ],
              );
            }),
            const SizedBox(height: 28),
            Text(
              'Beneficios sin turno',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (appState.reminderClients.isEmpty)
              const Card(child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Todo al día'),
                subtitle: Text('No hay clientas con beneficio disponible y sin turno.'),
              ))
            else
              ...appState.reminderClients.take(6).map((client) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.card_giftcard)),
                  title: Text(client.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${client.availableRewards} beneficio disponible'),
                  trailing: IconButton(
                    tooltip: 'Recordar por WhatsApp',
                    onPressed: () => sendReminder(context, client),
                    icon: const Icon(Icons.chat_outlined),
                  ),
                ),
              )),
            const SizedBox(height: 26),
            Text(
              'Actividad reciente',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...appState.recentActivity.map((item) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.spa)),
                title: Text('${item.clientName} · ${item.serviceName}'),
                subtitle: Text(formatDateTime(item.performedAt.toLocal())),
                trailing: Text(formatMoney(item.finalPrice),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class AdminClientsPage extends StatefulWidget {
  const AdminClientsPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<AdminClientsPage> createState() => _AdminClientsPageState();
}

class _AdminClientsPageState extends State<AdminClientsPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase().trim();
    final list = widget.appState.clients.where((c) =>
      q.isEmpty ||
      c.fullName.toLowerCase().contains(q) ||
      c.phone.toLowerCase().contains(q) ||
      c.email.toLowerCase().contains(q)
    ).toList();

    return AdminScaffold(
      appState: widget.appState,
      selectedIndex: 1,
      child: ListView(children: [
        PageTitle(
          'Clientas',
          subtitle: '${widget.appState.clients.length} registradas',
          trailing: FilledButton.icon(
            onPressed: () => showClientForm(context),
            icon: const Icon(Icons.add),
            label: const Text('Nueva'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar clienta...',
          ),
        ),
        const SizedBox(height: 12),
        ...list.map((c) => Card(
          child: ListTile(
            onTap: () => context.go('/admin/clients/${c.id}'),
            leading: CircleAvatar(child: Text(c.firstName.isEmpty ? '?' : c.firstName[0])),
            title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${c.points}/${widget.appState.loyalty?.pointsRequired ?? 5} · '
                '${c.availableRewards} beneficios'),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  final confirmed = await confirmDanger(
                    context,
                    title: 'Eliminar clienta',
                    message:
                        'Si nunca tuvo servicios ni beneficios se elimina definitivamente. '
                        'Si ya tiene historial, se archivará para conservar los registros.',
                  );
                  if (!confirmed) return;
                  final result = await widget.appState.deleteClient(c.id);
                  if (context.mounted && result != null) {
                    final action = result['action'] == 'deleted'
                        ? 'Clienta eliminada.'
                        : 'Clienta archivada porque tenía historial.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(action)),
                    );
                    setState(() {});
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 8),
                    Text('Eliminar / archivar'),
                  ]),
                ),
              ],
            ),
          ),
        )),
      ]),
    );
  }

  Future<void> showClientForm(BuildContext context) async {
    final first = TextEditingController();
    final last = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Nueva clienta'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: first, decoration: const InputDecoration(labelText: 'Nombre *')),
            const SizedBox(height: 8),
            TextField(controller: last, decoration: const InputDecoration(labelText: 'Apellido *')),
            const SizedBox(height: 8),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'WhatsApp')),
            const SizedBox(height: 8),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (first.text.trim().isEmpty || last.text.trim().isEmpty) return;
              Navigator.pop(d, true);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await widget.appState.addClient(
        firstName: first.text,
        lastName: last.text,
        phone: phone.text,
        email: email.text,
      );
      if (mounted) setState(() {});
    }
  }
}

class AdminClientDetailPage extends StatefulWidget {
  const AdminClientDetailPage({
    super.key,
    required this.appState,
    required this.clientId,
  });
  final AppState appState;
  final String clientId;

  @override
  State<AdminClientDetailPage> createState() => _AdminClientDetailPageState();
}

class _AdminClientDetailPageState extends State<AdminClientDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.appState.loadClientDetail(widget.clientId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.appState.clientById(widget.clientId);
    if (client == null) {
      return AdminScaffold(
        appState: widget.appState,
        selectedIndex: 1,
        child: const EmptyState(
          icon: Icons.person_off,
          title: 'Clienta no encontrada',
          message: 'Volvé al listado.',
        ),
      );
    }

    final available = client.rewards
        .where((r) => r.status == RewardStatus.available)
        .toList();

    return AdminScaffold(
      appState: widget.appState,
      selectedIndex: 1,
      child: ListView(children: [
        Row(children: [
          IconButton(
            onPressed: () => context.go('/admin/clients'),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(child: PageTitle(
            client.fullName,
            subtitle: [client.phone, client.email].where((e) => e.isNotEmpty).join(' · '),
            trailing: IconButton(
              tooltip: 'Eliminar clienta',
              onPressed: () async {
                final confirmed = await confirmDanger(
                  context,
                  title: 'Eliminar clienta',
                  message:
                      'Si tiene historial quedará archivada y dejará de aparecer en las clientas activas. '
                      'Sus servicios anteriores no se pierden.',
                );
                if (!confirmed) return;
                final result = await widget.appState.deleteClient(client.id);
                if (context.mounted && result != null) {
                  context.go('/admin/clients');
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
          )),
        ]),
        const SizedBox(height: 14),
        LoyaltyCardWidget(
          client: client,
          pointsRequired: widget.appState.loyalty?.pointsRequired ?? 5,
          rewardPercent: widget.appState.loyalty?.rewardPercent ?? 20,
          businessName: widget.appState.business?.name ?? 'Loyalty Studio',
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => registerService(context, client),
            icon: const Icon(Icons.add),
            label: const Text('Registrar servicio'),
          ),
          if (client.availableRewards > 0)
            FilledButton.tonalIcon(
              onPressed: () async {
                await widget.appState.loadClientDetail(client.id);
                if (!context.mounted) return;

                final current =
                    widget.appState.clientById(client.id);
                if (current == null) return;

                final currentAvailable = current.rewards
                    .where(
                      (reward) =>
                          reward.status == RewardStatus.available,
                    )
                    .toList();

                if (currentAvailable.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No hay un beneficio disponible para canjear.',
                      ),
                    ),
                  );
                  return;
                }

                await redeem(
                  context,
                  current,
                  currentAvailable,
                );
              },
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Canjear'),
            ),
          OutlinedButton.icon(
            onPressed: () => editClient(context, client),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
          OutlinedButton.icon(
            onPressed: () => createAppointment(context, client),
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('Nuevo turno'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.appState.publicUrlFor(client)),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarjeta copiada')),
                );
              }
            },
            icon: const Icon(Icons.link),
            label: const Text('Copiar tarjeta'),
          ),
        ]),
        const SizedBox(height: 24),
        Text('Historial',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
        const SizedBox(height: 8),
        ...client.history.map((entry) => Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.spa)),
            title: Text(entry.serviceName),
            subtitle: Text(formatDateTime(entry.performedAt.toLocal())),
            trailing: Text(formatMoney(entry.finalPrice),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        )),
      ]),
    );
  }

  Future<void> editClient(BuildContext context, ClientRecord client) async {
    final first = TextEditingController(text: client.firstName);
    final last = TextEditingController(text: client.lastName);
    final phone = TextEditingController(text: client.phone);
    final email = TextEditingController(text: client.email);

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Editar clienta'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: first, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(controller: last, decoration: const InputDecoration(labelText: 'Apellido')),
            const SizedBox(height: 8),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'WhatsApp')),
            const SizedBox(height: 8),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true) {
      await widget.appState.updateClient(
        clientId: client.id,
        firstName: first.text,
        lastName: last.text,
        phone: phone.text,
        email: email.text,
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> createAppointment(BuildContext context, ClientRecord client) async {
    final active = widget.appState.services.where((s) => s.active).toList();
    if (active.isEmpty) return;
    var serviceId = active.first.id;
    final notes = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setStateDialog) => AlertDialog(
          title: const Text('Nuevo turno'),
          content: SizedBox(
            width: 430,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: serviceId,
                items: active.map((s) => DropdownMenuItem(
                  value: s.id,
                  child: Text(s.name),
                )).toList(),
                onChanged: (v) => setStateDialog(() => serviceId = v!),
                decoration: const InputDecoration(labelText: 'Servicio'),
              ),
              const SizedBox(height: 8),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Elegir fecha')),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final date = await pickAvailableAppointmentSlot(
      context,
      loadSlots: (day) =>
          widget.appState.getAdminAvailableAppointmentSlots(day),
    );
    if (date == null) return;

    final saved = await widget.appState.createAdminAppointment(
      clientId: client.id,
      serviceId: serviceId,
      startsAt: date,
      notes: notes.text,
    );

    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.appState.errorMessage ??
                'No se pudo crear el turno.',
          ),
        ),
      );
    }
  }

  Future<void> registerService(BuildContext context, ClientRecord client) async {
    final active = widget.appState.services.where((s) => s.active).toList();
    if (active.isEmpty) return;
    var selected = active.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Registrar servicio'),
          content: DropdownButtonFormField<String>(
            value: selected,
            items: active.map((s) => DropdownMenuItem(
              value: s.id,
              child: Text('${s.name} · ${formatMoney(s.price)}'),
            )).toList(),
            onChanged: (v) => setDialog(() => selected = v!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.appState.registerService(clientId: client.id, serviceId: selected);
      if (mounted) setState(() {});
    }
  }

  Future<void> redeem(
    BuildContext context,
    ClientRecord client,
    List<RewardRecord> rewards,
  ) async {
    final active = widget.appState.services.where((s) => s.active).toList();
    if (active.isEmpty) return;
    var rewardId = rewards.first.id;
    var serviceId = active.first.id;

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Canjear beneficio'),
          content: SizedBox(
            width: 430,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: rewardId,
                items: rewards.map((r) => DropdownMenuItem(
                  value: r.id,
                  child: Text(r.title),
                )).toList(),
                onChanged: (v) => setDialog(() => rewardId = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: serviceId,
                items: active.map((s) => DropdownMenuItem(
                  value: s.id,
                  child: Text(s.name),
                )).toList(),
                onChanged: (v) => setDialog(() => serviceId = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Canjear')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.appState.redeemReward(
        clientId: client.id,
        rewardId: rewardId,
        serviceId: serviceId,
      );
      if (mounted) setState(() {});
    }
  }
}


class AdminAppointmentsPage extends StatefulWidget {
  const AdminAppointmentsPage({
    super.key,
    required this.appState,
    this.initialAppointmentId,
  });

  final AppState appState;
  final String? initialAppointmentId;

  @override
  State<AdminAppointmentsPage> createState() =>
      _AdminAppointmentsPageState();
}

class _AdminAppointmentsPageState
    extends State<AdminAppointmentsPage>
    with WidgetsBindingObserver {
  Timer? _syncTimer;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPriorityAppointment();
      _refreshAppointments();
      _syncTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshAppointments(),
      );
    });
  }

  @override
  void didUpdateWidget(covariant AdminAppointmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialAppointmentId !=
        oldWidget.initialAppointmentId) {
      _loadPriorityAppointment();
      _refreshAppointments();
    }
  }

  Future<void> _loadPriorityAppointment() async {
    final id = widget.initialAppointmentId;
    if (id == null || id.isEmpty || !mounted) return;

    await widget.appState.loadAppointmentById(id);
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAppointments();
    }
  }

  Future<void> _refreshAppointments() async {
    if (_syncing || !mounted) return;

    _syncing = true;
    try {
      await widget.appState.loadAppointments();
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final upcoming = widget.appState.appointments
        .where((a) =>
            a.startsAt.toLocal().isAfter(now) &&
            a.status != 'cancelled' &&
            a.status != 'completed')
        .toList();

    final history = widget.appState.appointments
        .where((a) => !upcoming.contains(a))
        .toList();

    return AdminScaffold(
      appState: widget.appState,
      selectedIndex: 4,
      child: ListView(
        children: [
          PageTitle(
            'Turnos',
            subtitle:
                'Podés crear, editar, confirmar, cancelar y revisar el historial.',
            trailing: FilledButton.icon(
              onPressed: () => newAppointment(context),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            ),
          ),
          const SizedBox(height: 18),
          if (widget.initialAppointmentId != null)
            ..._priorityAppointmentSection(context),
          Text(
            'Próximos',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            const EmptyState(
              icon: Icons.calendar_month,
              title: 'No hay turnos próximos',
              message:
                  'Los pedidos de las clientas y los turnos nuevos aparecerán acá.',
            )
          else
            ...upcoming.map(
              (a) => _appointmentCard(context, a),
            ),
          const SizedBox(height: 24),
          Text(
            'Historial de turnos',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.history),
                title: Text('Todavía no hay historial'),
              ),
            )
          else
            ...history.take(50).map(
              (a) => _appointmentCard(context, a),
            ),
        ],
      ),
    );
  }

  List<Widget> _priorityAppointmentSection(
    BuildContext context,
  ) {
    AppointmentRecord? priority;

    for (final item in widget.appState.appointments) {
      if (item.id == widget.initialAppointmentId) {
        priority = item;
        break;
      }
    }

    if (priority == null) {
      return const [
        Card(
          child: ListTile(
            leading: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            title: Text('Cargando la solicitud nueva...'),
          ),
        ),
        SizedBox(height: 14),
      ];
    }

    return [
      Text(
        priority.status == 'requested'
            ? 'Solicitud recibida'
            : 'Turno de la notificación',
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      _appointmentCard(context, priority),
      const SizedBox(height: 22),
    ];
  }

  Widget _appointmentCard(
    BuildContext context,
    AppointmentRecord a,
  ) {
    final statusLabel = switch (a.status) {
      'requested' => 'Pendiente',
      'confirmed' => 'Confirmado',
      'completed' => 'Realizado',
      'cancelled' => 'Cancelado',
      _ => a.status,
    };

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            a.status == 'requested'
                ? Icons.notifications_active_outlined
                : Icons.calendar_month,
          ),
        ),
        title: Text(
          '${a.clientName} · ${a.serviceName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${formatDateTime(a.startsAt.toLocal())}\n'
          '${a.source == 'client' ? 'Pedido por clienta' : 'Cargado por admin'}'
          '${a.notes.isEmpty ? '' : '\n${a.notes}'}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await editAppointment(context, a);
            } else if (value == 'confirm') {
              await widget.appState.updateAppointmentStatus(
                appointmentId: a.id,
                status: 'confirmed',
              );
            } else if (value == 'complete') {
              await completeAppointment(context, a);
            } else if (value == 'cancel') {
              await widget.appState.updateAppointmentStatus(
                appointmentId: a.id,
                status: 'cancelled',
              );
            } else if (value == 'delete') {
              final confirmed = await confirmDanger(
                context,
                title: 'Eliminar turno',
                message:
                    'Los turnos futuros se eliminan. Los turnos históricos '
                    'se conservan para no perder trazabilidad.',
              );

              if (confirmed) {
                final result =
                    await widget.appState.deleteAppointment(a.id);

                if (context.mounted && result != null) {
                  final msg = result['action'] == 'deleted'
                      ? 'Turno eliminado.'
                      : 'El turno se conservó como histórico.';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg)),
                  );
                }
              }
            }

            if (mounted) setState(() {});
          },
          itemBuilder: (_) => [
            if (a.status != 'completed' && a.status != 'cancelled')
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ],
                ),
              ),
            if (a.status == 'requested')
              const PopupMenuItem(
                value: 'confirm',
                child: Text('Confirmar'),
              ),
            if (a.status == 'confirmed')
              const PopupMenuItem(
                value: 'complete',
                child: Text('Marcar realizado'),
              ),
            if (a.status != 'completed' && a.status != 'cancelled')
              const PopupMenuItem(
                value: 'cancel',
                child: Text('Cancelar'),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline),
                  SizedBox(width: 8),
                  Text('Eliminar'),
                ],
              ),
            ),
            PopupMenuItem(
              enabled: false,
              child: Text('Estado: $statusLabel'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> completeAppointment(
    BuildContext context,
    AppointmentRecord appointment,
  ) async {
    // Always reload the real client detail before deciding whether a reward
    // can be applied. Dashboard rows only contain reward counts.
    await widget.appState.loadClientDetail(appointment.clientId);
    if (!context.mounted) return;

    final client =
        widget.appState.clientById(appointment.clientId);

    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo encontrar la clienta del turno.'),
        ),
      );
      return;
    }

    final availableRewards = client.rewards
        .where(
          (reward) => reward.status == RewardStatus.available,
        )
        .toList();

    // Use the oldest available reward first when several exist.
    final reward =
        availableRewards.isEmpty ? null : availableRewards.last;

    var applyReward = reward != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Completar turno'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${appointment.clientName} · '
                  '${appointment.serviceName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Al marcarlo como realizado, el servicio se '
                  'registrará automáticamente en la tarjeta y '
                  'sumará sus puntos de fidelidad.',
                ),
                if (reward != null) ...[
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: applyReward,
                    onChanged: (value) => setDialog(
                      () => applyReward = value ?? false,
                    ),
                    title: Text(
                      'Aplicar beneficio ${reward.title}',
                    ),
                    subtitle: const Text(
                      'Si lo desmarcás, el beneficio seguirá '
                      'disponible para otro servicio.',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Marcar realizado'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final result = await widget.appState.completeAppointment(
      appointmentId: appointment.id,
      clientId: appointment.clientId,
      rewardId:
          applyReward && reward != null ? reward.id : null,
    );

    if (!context.mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.appState.errorMessage ??
                'No se pudo completar el turno.',
          ),
        ),
      );
      return;
    }

    final discount =
        (result['discount_amount'] as num?)?.toDouble() ?? 0;
    final points =
        (result['points_balance'] as num?)?.toInt();

    var message = 'Turno realizado y servicio sumado a la tarjeta.';
    if (discount > 0) {
      message += ' Beneficio aplicado.';
    }
    if (points != null) {
      message += ' Saldo: $points punto${points == 1 ? '' : 's'}.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> newAppointment(BuildContext context) async {
    final activeServices = widget.appState.services
        .where((s) => s.active)
        .toList();

    if (widget.appState.clients.isEmpty ||
        activeServices.isEmpty) {
      return;
    }

    var clientId = widget.appState.clients.first.id;
    var serviceId = activeServices.first.id;
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Nuevo turno'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: clientId,
                  decoration:
                      const InputDecoration(labelText: 'Clienta'),
                  items: widget.appState.clients
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialog(() => clientId = v!),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: serviceId,
                  decoration:
                      const InputDecoration(labelText: 'Servicio'),
                  items: activeServices
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialog(() => serviceId = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  decoration:
                      const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Elegir fecha'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !context.mounted) return;

    final date = await pickAvailableAppointmentSlot(
      context,
      loadSlots: (day) =>
          widget.appState.getAdminAvailableAppointmentSlots(day),
    );
    if (date == null) return;

    final saved = await widget.appState.createAdminAppointment(
      clientId: clientId,
      serviceId: serviceId,
      startsAt: date,
      notes: notes.text,
    );

    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.appState.errorMessage ??
                'No se pudo crear el turno.',
          ),
        ),
      );
    }

    if (mounted) setState(() {});
  }

  Future<void> editAppointment(
    BuildContext context,
    AppointmentRecord appointment,
  ) async {
    final activeServices = widget.appState.services
        .where((s) => s.active)
        .toList();

    if (widget.appState.clients.isEmpty ||
        activeServices.isEmpty) {
      return;
    }

    var clientId = appointment.clientId;
    var serviceId = activeServices.any(
      (s) => s.id == appointment.serviceId,
    )
        ? appointment.serviceId
        : activeServices.first.id;

    final notes =
        TextEditingController(text: appointment.notes);

    final choose = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Editar turno'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: clientId,
                  decoration:
                      const InputDecoration(labelText: 'Clienta'),
                  items: widget.appState.clients
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialog(() => clientId = v!),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: serviceId,
                  decoration:
                      const InputDecoration(labelText: 'Servicio'),
                  items: activeServices
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialog(() => serviceId = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  decoration:
                      const InputDecoration(labelText: 'Notas'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Fecha actual: '
                  '${formatDateTime(appointment.startsAt.toLocal())}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Cambiar fecha/hora'),
            ),
          ],
        ),
      ),
    );

    if (choose != true || !context.mounted) return;

    final date = await pickAvailableAppointmentSlot(
      context,
      initialDate: appointment.startsAt.toLocal(),
      loadSlots: (day) =>
          widget.appState.getAdminAvailableAppointmentSlots(
        day,
        excludeAppointmentId: appointment.id,
      ),
    );
    if (date == null) return;

    final ok = await widget.appState.updateAppointment(
      appointmentId: appointment.id,
      clientId: clientId,
      serviceId: serviceId,
      startsAt: date,
      notes: notes.text,
    );

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.appState.errorMessage ??
                'No se pudo editar el turno.',
          ),
        ),
      );
    }
  }
}


class AdminServicesPage extends StatefulWidget {
  const AdminServicesPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<AdminServicesPage> createState() =>
      _AdminServicesPageState();
}

class _AdminServicesPageState extends State<AdminServicesPage> {
  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appState: widget.appState,
      selectedIndex: 2,
      child: ListView(
        children: [
          PageTitle(
            'Servicios',
            subtitle:
                'Editá nombre, precio y puntos. El cambio aplica solo a futuros registros.',
            trailing: FilledButton.icon(
              onPressed: () => addService(context),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.appState.services.isEmpty)
            const EmptyState(
              icon: Icons.spa_outlined,
              title: 'No hay servicios activos',
              message: 'Creá uno nuevo o restaurá uno archivado.',
            )
          else
            ...widget.appState.services.map(
              (s) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      s.active
                          ? Icons.spa
                          : Icons.pause_circle_outline,
                    ),
                  ),
                  title: Text(
                    s.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${formatMoney(s.price)} · +${s.points} punto'
                    '${s.active ? '' : ' · Desactivado'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar servicio',
                        onPressed: () => editService(context, s),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      Switch(
                        value: s.active,
                        onChanged: (v) async {
                          await widget.appState
                              .toggleService(s.id, v);
                          if (mounted) setState(() {});
                        },
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value != 'delete') return;

                          final confirmed =
                              await confirmDanger(
                            context,
                            title: 'Eliminar servicio',
                            message:
                                'Si nunca fue usado se elimina definitivamente. '
                                'Si ya tiene historial se archivará. '
                                'Los precios de servicios anteriores no se modifican.',
                          );

                          if (!confirmed) return;

                          final result = await widget.appState
                              .deleteService(s.id);

                          if (context.mounted &&
                              result != null) {
                            final msg =
                                result['action'] == 'deleted'
                                    ? 'Servicio eliminado.'
                                    : 'Servicio archivado. Podés restaurarlo desde Negocio → Archivados.';
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                            setState(() {});
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.archive_outlined),
                                SizedBox(width: 8),
                                Text('Eliminar / archivar'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> editService(
    BuildContext context,
    ServiceDefinition service,
  ) async {
    final name =
        TextEditingController(text: service.name);
    final price = TextEditingController(
      text: service.price.toStringAsFixed(0),
    );
    final points =
        TextEditingController(text: '${service.points}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Editar servicio'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(labelText: 'Precio'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: points,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Puntos'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Importante: cambiar el precio no modifica servicios históricos. '
                'Cada servicio realizado conserva el precio cobrado en ese momento.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final parsedPrice = double.tryParse(
                price.text.replaceAll(',', '.'),
              );
              final parsedPoints =
                  int.tryParse(points.text);

              if (name.text.trim().isEmpty ||
                  parsedPrice == null ||
                  parsedPrice < 0 ||
                  parsedPoints == null ||
                  parsedPoints < 0) {
                return;
              }

              Navigator.pop(d, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final saved = await widget.appState.updateService(
        serviceId: service.id,
        name: name.text,
        price: double.parse(
          price.text.replaceAll(',', '.'),
        ),
        points: int.parse(points.text),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Servicio actualizado.'
                  : widget.appState.errorMessage ??
                      'No se pudo guardar.',
            ),
          ),
        );
      }

      if (mounted) setState(() {});
    }
  }

  Future<void> addService(BuildContext context) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final points = TextEditingController(text: '1');

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Nuevo servicio'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                decoration:
                    const InputDecoration(labelText: 'Precio'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: points,
                decoration:
                    const InputDecoration(labelText: 'Puntos'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await widget.appState.addService(
        name: name.text,
        price: double.tryParse(
              price.text.replaceAll(',', '.'),
            ) ??
            0,
        points: int.tryParse(points.text) ?? 1,
      );

      if (mounted) setState(() {});
    }
  }
}

class AdminLoyaltyPage extends StatelessWidget {
  const AdminLoyaltyPage({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final points = TextEditingController(text: '${appState.loyalty?.pointsRequired ?? 5}');
    final percent = TextEditingController(text: '${appState.loyalty?.rewardPercent ?? 20}');
    return AdminScaffold(
      appState: appState,
      selectedIndex: 3,
      child: ListView(children: [
        const PageTitle('Fidelización'),
        const SizedBox(height: 16),
        TextField(controller: points, decoration: const InputDecoration(labelText: 'Servicios necesarios')),
        const SizedBox(height: 8),
        TextField(controller: percent, decoration: const InputDecoration(labelText: 'Descuento %')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => appState.updateLoyalty(
            pointsRequired: int.tryParse(points.text) ?? 5,
            rewardPercent: double.tryParse(percent.text) ?? 20,
          ),
          child: const Text('Guardar'),
        ),
      ]),
    );
  }
}


class AdminBusinessPage extends StatefulWidget {
  const AdminBusinessPage({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  State<AdminBusinessPage> createState() =>
      _AdminBusinessPageState();
}

class _AdminBusinessPageState
    extends State<AdminBusinessPage> {
  late final TextEditingController name;
  late final TextEditingController color;
  late final TextEditingController phone;
  late final TextEditingController logo;
  late List<BusinessHoursRecord> schedule;
  late int slotMinutes;

  @override
  void initState() {
    super.initState();

    final b = widget.appState.business!;
    name = TextEditingController(text: b.name);
    color =
        TextEditingController(text: b.primaryColorHex);
    phone = TextEditingController(text: b.phone);
    logo = TextEditingController(text: b.logoUrl);
    slotMinutes = b.appointmentSlotMinutes;
    schedule = widget.appState.businessHours
        .map((item) => item.copy())
        .toList()
      ..sort((a, b) => a.weekday.compareTo(b.weekday));

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.appState.loadArchivedEntities(),
    );
  }

  @override
  void dispose() {
    name.dispose();
    color.dispose();
    phone.dispose();
    logo.dispose();
    super.dispose();
  }


  String _weekdayName(int weekday) {
    const names = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    return names[weekday - 1];
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1
          ? int.tryParse(parts[1]) ?? 0
          : 0,
    );
  }

  String _timeText(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Future<void> _pickScheduleTime(
    BusinessHoursRecord item, {
    required bool opening,
  }) async {
    final current = _parseTime(
      opening ? item.opensAt : item.closesAt,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: opening ? 'Hora de apertura' : 'Hora de cierre',
      cancelText: 'Cancelar',
      confirmText: 'Usar',
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (opening) {
        item.opensAt = _timeText(picked);
      } else {
        item.closesAt = _timeText(picked);
      }
    });
  }

  Future<void> _saveSchedule() async {
    for (final item in schedule.where((item) => item.enabled)) {
      final start = _parseTime(item.opensAt);
      final end = _parseTime(item.closesAt);

      final startMinutes = start.hour * 60 + start.minute;
      final endMinutes = end.hour * 60 + end.minute;

      if (endMinutes <= startMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_weekdayName(item.weekday)}: '
              'el cierre debe ser posterior a la apertura.',
            ),
          ),
        );
        return;
      }

      if (endMinutes - startMinutes < slotMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_weekdayName(item.weekday)}: '
              'la franja debe permitir al menos un turno.',
            ),
          ),
        );
        return;
      }
    }

    final ok = await widget.appState.updateBusinessSchedule(
      slotMinutes: slotMinutes,
      hours: schedule,
    );

    if (!mounted) return;

    if (ok) {
      final b = widget.appState.business!;
      setState(() {
        slotMinutes = b.appointmentSlotMinutes;
        schedule = widget.appState.businessHours
            .map((item) => item.copy())
            .toList()
          ..sort((a, b) => a.weekday.compareTo(b.weekday));
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Horarios de atención guardados.'
              : widget.appState.errorMessage ??
                  'No se pudieron guardar los horarios.',
        ),
      ),
    );
  }

  Future<void> activatePushNotifications() async {
    try {
      final env = PushNotifications.environment();

      if (env.isIos && !env.isStandalone) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Activar en iPhone/iPad'),
            content: const Text(
              'Primero abrí el menú Compartir de Safari, elegí '
              '"Agregar a pantalla de inicio", abrí Bellamia desde '
              'ese ícono y después tocá nuevamente Activar notificaciones.',
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

      PushNotifications.setAdminPwaTarget();

      final subscription =
          await PushNotifications.subscribe();

      final saved = await widget.appState
          .registerAdminPushSubscription(subscription);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Notificaciones activadas en este dispositivo.'
                : widget.appState.errorMessage ??
                    'No se pudo guardar la suscripción.',
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



  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appState: widget.appState,
      selectedIndex: 5,
      child: ListView(
        children: [
          const PageTitle(
            'Negocio y configuración',
            subtitle:
                'Marca, agenda, notificaciones y elementos archivados.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: color,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: logo,
                    decoration: const InputDecoration(
                      labelText: 'URL logo',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final ok = await widget.appState
                            .updateBusiness(
                          name: name.text,
                          primaryColorHex: color.text,
                          phone: phone.text,
                          logoUrl: logo.text,
                        );

                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Configuración guardada.'
                                    : widget.appState
                                            .errorMessage ??
                                        'No se pudo guardar.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Horarios de atención',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Estos horarios determinan qué opciones pueden reservar '
            'las clientas y la administración.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    value: slotMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Duración / intervalo de cada turno',
                      prefixIcon: Icon(Icons.timelapse_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 15,
                        child: Text('Cada 15 minutos'),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text('Cada 30 minutos'),
                      ),
                      DropdownMenuItem(
                        value: 45,
                        child: Text('Cada 45 minutos'),
                      ),
                      DropdownMenuItem(
                        value: 60,
                        child: Text('Cada 60 minutos'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => slotMinutes = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  ...schedule.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _weekdayName(item.weekday),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: item.enabled,
                                    onChanged: (value) {
                                      setState(
                                        () => item.enabled = value,
                                      );
                                    },
                                  ),
                                ],
                              ),
                              if (!item.enabled)
                                const Text(
                                  'Cerrado',
                                  style: TextStyle(
                                    color: Colors.black54,
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _pickScheduleTime(
                                        item,
                                        opening: true,
                                      ),
                                      icon: const Icon(
                                        Icons.login_outlined,
                                      ),
                                      label: Text(
                                        'Abre ${item.opensAt}',
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward,
                                      size: 18,
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _pickScheduleTime(
                                        item,
                                        opening: false,
                                      ),
                                      icon: const Icon(
                                        Icons.logout_outlined,
                                      ),
                                      label: Text(
                                        'Cierra ${item.closesAt}',
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saveSchedule,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text(
                        'Guardar horarios de atención',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Notificaciones',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Este dispositivo puede recibir avisos de nuevos turnos '
            'aunque la app no esté abierta.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child:
                          Icon(Icons.notifications_active_outlined),
                    ),
                    title: const Text(
                      'Notificaciones push',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      !PushNotifications.configured
                          ? 'Falta configurar la clave VAPID pública.'
                          : (() {
                              final env =
                                  PushNotifications.environment();
                              if (!env.supported) {
                                return 'Este navegador no es compatible.';
                              }
                              if (env.isIos &&
                                  !env.isStandalone) {
                                return 'En iPhone/iPad: agregá Bellamia a la pantalla de inicio.';
                              }
                              if (env.permission ==
                                  'granted') {
                                return 'Permiso concedido en este navegador.';
                              }
                              if (env.permission ==
                                  'denied') {
                                return 'Permiso bloqueado en el navegador.';
                              }
                              return 'Todavía no están activadas en este dispositivo.';
                            })(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            PushNotifications.configured
                                ? activatePushNotifications
                                : null,
                        icon: const Icon(
                          Icons.notifications_active,
                        ),
                        label: const Text(
                          'Activar notificaciones',
                        ),
                      ),
                      
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Archivados',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Archivar no borra el historial. Podés restaurar una clienta '
            'o un servicio desde acá.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.people_outline),
              title: Text(
                'Clientas archivadas '
                '(${widget.appState.archivedClients.length})',
              ),
              children: widget.appState.archivedClients.isEmpty
                  ? const [
                      ListTile(
                        title:
                            Text('No hay clientas archivadas'),
                      ),
                    ]
                  : widget.appState.archivedClients
                      .map(
                        (c) => ListTile(
                          title: Text(c.fullName),
                          subtitle: Text(
                            '${c.serviceCount} servicios históricos',
                          ),
                          trailing: TextButton.icon(
                            onPressed: () async {
                              final ok = await widget.appState
                                  .restoreClient(c.id);
                              if (mounted) {
                                setState(() {});
                              }
                              if (context.mounted && ok) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Clienta restaurada.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon:
                                const Icon(Icons.restore),
                            label:
                                const Text('Restaurar'),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.spa_outlined),
              title: Text(
                'Servicios archivados '
                '(${widget.appState.archivedServices.length})',
              ),
              children: widget.appState.archivedServices.isEmpty
                  ? const [
                      ListTile(
                        title:
                            Text('No hay servicios archivados'),
                      ),
                    ]
                  : widget.appState.archivedServices
                      .map(
                        (s) => ListTile(
                          title: Text(s.name),
                          subtitle: Text(
                            '${formatMoney(s.price)} · '
                            '+${s.points} punto',
                          ),
                          trailing: TextButton.icon(
                            onPressed: () async {
                              final ok = await widget.appState
                                  .restoreService(s.id);
                              if (mounted) {
                                setState(() {});
                              }
                              if (context.mounted && ok) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Servicio restaurado.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon:
                                const Icon(Icons.restore),
                            label:
                                const Text('Restaurar'),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Diferencia importante:\n'
                '• Desactivar servicio: deja de ofrecerse temporalmente y sigue en Servicios.\n'
                '• Archivar servicio: sale de Servicios y pasa a esta sección.\n'
                '• Editar precio: modifica el valor actual, pero nunca reescribe precios históricos.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
