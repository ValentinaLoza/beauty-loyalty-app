import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'push_notifications.dart';

class AppState extends ChangeNotifier {
  AppState(this.supabase);

  final SupabaseClient supabase;
  final Uuid _uuid = const Uuid();

  bool initialized = false;
  bool busy = false;
  String? errorMessage;

  BusinessRecord? business;
  String? memberRole;
  LoyaltyConfig? loyalty;
  List<BusinessHoursRecord> businessHours =
      BusinessHoursRecord.defaultWeek();

  List<ClientRecord> clients = <ClientRecord>[];
  List<ServiceDefinition> services = <ServiceDefinition>[];
  List<ClientRecord> archivedClients = <ClientRecord>[];
  List<ServiceDefinition> archivedServices = <ServiceDefinition>[];
  List<ClientRecord> reminderClients = <ClientRecord>[];
  List<RecentActivityRecord> recentActivity = <RecentActivityRecord>[];
  List<AppointmentRecord> appointments = <AppointmentRecord>[];
  BusinessMetrics metrics = BusinessMetrics.empty;

  bool get isAuthenticated => supabase.auth.currentSession != null;
  bool get needsBusinessSetup => isAuthenticated && business == null;

  Future<void> initialize() async {
    if (isAuthenticated) await refreshAdminData();
    initialized = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      PushNotifications.prepareAdminInstall();

      await refreshAdminData();
      return true;
    } on AuthException catch (error) {
      errorMessage = error.message;
      return false;
    } catch (error) {
      errorMessage = 'No se pudo iniciar sesión: $error';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    business = null;
    memberRole = null;
    loyalty = null;
    businessHours = BusinessHoursRecord.defaultWeek();
    clients = [];
    services = [];
    archivedClients = [];
    archivedServices = [];
    reminderClients = [];
    recentActivity = [];
    appointments = [];
    metrics = BusinessMetrics.empty;
    notifyListeners();
  }

  Future<bool> createBusiness({
    required String name,
    required String primaryColorHex,
  }) async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await supabase.rpc(
        'create_business_for_current_user',
        params: {
          'p_name': name.trim(),
          'p_primary_color_hex': primaryColorHex.trim(),
        },
      );
      await refreshAdminData();
      return business != null;
    } catch (error) {
      errorMessage = 'No se pudo crear el emprendimiento: $error';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshAdminData() async {
    if (supabase.auth.currentUser == null) return;

    try {
      final raw = await supabase.rpc('get_admin_bootstrap');
      final data = Map<String, dynamic>.from(raw as Map);

      if (!(data['has_business'] as bool? ?? false)) {
        business = null;
        memberRole = null;
        loyalty = null;
        businessHours = BusinessHoursRecord.defaultWeek();
        clients = [];
        services = [];
        reminderClients = [];
        recentActivity = [];
        metrics = BusinessMetrics.empty;
        notifyListeners();
        return;
      }

      memberRole = data['role'] as String? ?? 'owner';

      business = BusinessRecord.fromMap(
        Map<String, dynamic>.from(data['business'] as Map),
      );

      final hoursRaw =
          data['business_hours'] as List<dynamic>? ?? <dynamic>[];

      businessHours = hoursRaw.isEmpty
          ? BusinessHoursRecord.defaultWeek()
          : hoursRaw
              .map(
                (row) => BusinessHoursRecord.fromMap(
                  Map<String, dynamic>.from(row as Map),
                ),
              )
              .toList()
            ..sort((a, b) => a.weekday.compareTo(b.weekday));

      final loyaltyRaw = data['loyalty'];
      loyalty = loyaltyRaw == null
          ? null
          : LoyaltyConfig.fromMap(
              Map<String, dynamic>.from(loyaltyRaw as Map),
            );

      services = (data['services'] as List<dynamic>? ?? [])
          .map((row) => ServiceDefinition.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList();

      final previousClients = <String, ClientRecord>{
        for (final client in clients) client.id: client,
      };

      clients = (data['clients'] as List<dynamic>? ?? [])
          .map((row) => ClientRecord.fromDashboard(
                Map<String, dynamic>.from(row as Map),
              ))
          .map((client) {
            final previous = previousClients[client.id];

            // Dashboard bootstrap contains summary data only.
            // Keep an already-loaded detail until we explicitly refresh it,
            // otherwise rewards/history temporarily disappear from the UI.
            if (previous != null) {
              client.history.addAll(previous.history);
              client.rewards.addAll(previous.rewards);
            }

            return client;
          })
          .toList();

      reminderClients =
          (data['reminder_clients'] as List<dynamic>? ?? [])
              .map((row) => ClientRecord.fromDashboard(
                    Map<String, dynamic>.from(row as Map),
                  ))
              .toList();

      recentActivity =
          (data['recent_activity'] as List<dynamic>? ?? [])
              .map((row) => RecentActivityRecord.fromMap(
                    Map<String, dynamic>.from(row as Map),
                  ))
              .toList();

      metrics = BusinessMetrics.fromMap(
        Map<String, dynamic>.from(data['metrics'] as Map),
      );

      final appointmentRows =
          data['appointments'] as List<dynamic>?;
      if (appointmentRows != null) {
        appointments = appointmentRows
            .map(
              (row) => AppointmentRecord.fromMap(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
      }

      errorMessage = null;
    } catch (error) {
      errorMessage = 'Error cargando los datos: $error';
    }

    notifyListeners();
  }

  Future<void> loadArchivedEntities() async {
    if (business == null) return;

    try {
      final raw = await supabase.rpc(
        'get_archived_entities',
        params: {'p_business_id': business!.id},
      );

      final data = Map<String, dynamic>.from(raw as Map);

      archivedClients =
          (data['clients'] as List<dynamic>? ?? [])
              .map((row) => ClientRecord.fromDashboard(
                    Map<String, dynamic>.from(row as Map),
                  ))
              .toList();

      archivedServices =
          (data['services'] as List<dynamic>? ?? [])
              .map((row) => ServiceDefinition.fromMap(
                    Map<String, dynamic>.from(row as Map),
                  ))
              .toList();

      errorMessage = null;
    } catch (error) {
      errorMessage = 'No se pudieron cargar los archivados: $error';
    }

    notifyListeners();
  }

  ClientRecord? clientById(String id) {
    for (final client in clients) {
      if (client.id == id) return client;
    }
    return null;
  }

  Future<void> loadClientDetail(String clientId) async {
    final client = clientById(clientId);
    if (client == null) return;

    try {
      final raw = await supabase.rpc(
        'get_admin_client_detail',
        params: {'p_client_id': clientId},
      );

      final data = Map<String, dynamic>.from(raw as Map);

      client.history
        ..clear()
        ..addAll((data['history'] as List<dynamic>? ?? [])
            .map((row) => ServiceEntry.fromMap(
                  Map<String, dynamic>.from(row as Map),
                )));

      client.rewards
        ..clear()
        ..addAll((data['rewards'] as List<dynamic>? ?? [])
            .map((row) => RewardRecord.fromMap(
                  Map<String, dynamic>.from(row as Map),
                )));

      client.availableRewards = client.rewards
          .where((reward) => reward.status == RewardStatus.available)
          .length;
      client.serviceCount = client.history.length;

      notifyListeners();
    } catch (error) {
      errorMessage = 'No se pudo cargar la clienta: $error';
      notifyListeners();
    }
  }

  Future<bool> addClient({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
  }) async {
    if (business == null) return false;

    try {
      await supabase.from('clients').insert({
        'business_id': business!.id,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'email': email.trim().isEmpty ? null : email.trim(),
      });

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo crear la clienta: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateClient({
    required String clientId,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
  }) async {
    try {
      await supabase.from('clients').update({
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'email': email.trim().isEmpty ? null : email.trim(),
      }).eq('id', clientId);

      await refreshAdminData();
      await loadClientDetail(clientId);
      return true;
    } catch (error) {
      errorMessage = 'No se pudo editar la clienta: $error';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> deleteClient(String clientId) async {
    try {
      final raw = await supabase.rpc(
        'delete_or_archive_client',
        params: {'p_client_id': clientId},
      );

      await refreshAdminData();
      await loadArchivedEntities();

      return Map<String, dynamic>.from(raw as Map);
    } catch (error) {
      errorMessage = 'No se pudo eliminar la clienta: $error';
      notifyListeners();
      return null;
    }
  }

  Future<bool> restoreClient(String clientId) async {
    try {
      await supabase.rpc(
        'restore_client',
        params: {'p_client_id': clientId},
      );
      await refreshAdminData();
      await loadArchivedEntities();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo restaurar la clienta: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addService({
    required String name,
    required double price,
    required int points,
  }) async {
    if (business == null) return false;

    try {
      await supabase.from('services').insert({
        'business_id': business!.id,
        'name': name.trim(),
        'default_price': price,
        'loyalty_points': points,
      });

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo crear el servicio: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateService({
    required String serviceId,
    required String name,
    required double price,
    required int points,
  }) async {
    try {
      await supabase.rpc(
        'update_service_definition',
        params: {
          'p_service_id': serviceId,
          'p_name': name.trim(),
          'p_default_price': price,
          'p_loyalty_points': points,
        },
      );

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo editar el servicio: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleService(String serviceId, bool active) async {
    try {
      await supabase.from('services').update({
        'active': active,
      }).eq('id', serviceId);

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo actualizar el servicio: $error';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> deleteService(String serviceId) async {
    try {
      final raw = await supabase.rpc(
        'delete_or_archive_service',
        params: {'p_service_id': serviceId},
      );

      await refreshAdminData();
      await loadArchivedEntities();

      return Map<String, dynamic>.from(raw as Map);
    } catch (error) {
      errorMessage = 'No se pudo eliminar el servicio: $error';
      notifyListeners();
      return null;
    }
  }

  Future<bool> restoreService(String serviceId) async {
    try {
      await supabase.rpc(
        'restore_service',
        params: {'p_service_id': serviceId},
      );

      await refreshAdminData();
      await loadArchivedEntities();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo restaurar el servicio: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateLoyalty({
    required int pointsRequired,
    required double rewardPercent,
  }) async {
    if (loyalty == null) return false;

    try {
      await supabase.from('loyalty_programs').update({
        'points_required': pointsRequired,
        'reward_percent': rewardPercent,
      }).eq('id', loyalty!.id);

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo actualizar el beneficio: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateBusiness({
    required String name,
    required String primaryColorHex,
    required String phone,
    required String logoUrl,
  }) async {
    if (business == null) return false;

    try {
      await supabase.from('businesses').update({
        'name': name.trim(),
        'primary_color_hex': primaryColorHex.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'logo_url': logoUrl.trim().isEmpty ? null : logoUrl.trim(),
      }).eq('id', business!.id);

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo actualizar el negocio: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateBusinessSchedule({
    required int slotMinutes,
    required List<BusinessHoursRecord> hours,
  }) async {
    if (business == null) return false;

    try {
      await supabase.rpc(
        'update_business_schedule',
        params: {
          'p_business_id': business!.id,
          'p_slot_minutes': slotMinutes,
          'p_hours': hours
              .map(
                (item) => {
                  'weekday': item.weekday,
                  'enabled': item.enabled,
                  'opens_at': item.opensAt,
                  'closes_at': item.closesAt,
                },
              )
              .toList(),
        },
      );

      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage =
          'No se pudieron guardar los horarios: $error';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> registerService({
    required String clientId,
    required String serviceId,
  }) async {
    if (business == null) return null;

    try {
      final result = await supabase.rpc(
        'register_service',
        params: {
          'p_business_id': business!.id,
          'p_client_id': clientId,
          'p_service_id': serviceId,
          'p_idempotency_key': _uuid.v4(),
        },
      );

      await refreshAdminData();
      await loadClientDetail(clientId);

      return Map<String, dynamic>.from(result as Map);
    } catch (error) {
      errorMessage = 'No se pudo registrar el servicio: $error';
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> redeemReward({
    required String clientId,
    required String rewardId,
    required String serviceId,
  }) async {
    if (business == null) return null;

    try {
      final result = await supabase.rpc(
        'redeem_reward',
        params: {
          'p_business_id': business!.id,
          'p_client_id': clientId,
          'p_service_id': serviceId,
          'p_reward_id': rewardId,
          'p_idempotency_key': _uuid.v4(),
        },
      );

      await refreshAdminData();
      await loadClientDetail(clientId);

      return Map<String, dynamic>.from(result as Map);
    } catch (error) {
      errorMessage = 'No se pudo canjear el beneficio: $error';
      notifyListeners();
      return null;
    }
  }

  String publicUrlFor(ClientRecord client) =>
      '${Uri.base.origin}/card/${client.publicToken}';

  Future<String?> rotateClientPublicToken(String clientId) async {
    try {
      final result = await supabase.rpc(
        'rotate_client_public_token',
        params: {'p_client_id': clientId},
      );

      await refreshAdminData();
      return result as String?;
    } catch (error) {
      errorMessage = 'No se pudo regenerar el enlace: $error';
      notifyListeners();
      return null;
    }
  }

  String _dateOnly(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<List<DateTime>> getAdminAvailableAppointmentSlots(
    DateTime day, {
    String? excludeAppointmentId,
  }) async {
    if (business == null) return <DateTime>[];

    try {
      final raw = await supabase.rpc(
        'get_admin_available_appointment_slots',
        params: {
          'p_business_id': business!.id,
          'p_date': _dateOnly(day),
          'p_exclude_appointment_id': excludeAppointmentId,
        },
      );

      return (raw as List<dynamic>? ?? <dynamic>[])
          .map((value) => DateTime.parse(value as String).toLocal())
          .toList();
    } catch (error) {
      errorMessage =
          'No se pudieron consultar los horarios: $error';
      notifyListeners();
      return <DateTime>[];
    }
  }

  Future<List<DateTime>> getPublicAvailableAppointmentSlots({
    required String token,
    required DateTime day,
  }) async {
    try {
      final raw = await supabase.rpc(
        'get_public_available_appointment_slots',
        params: {
          'p_token': token,
          'p_date': _dateOnly(day),
        },
      );

      return (raw as List<dynamic>? ?? <dynamic>[])
          .map((value) => DateTime.parse(value as String).toLocal())
          .toList();
    } catch (error) {
      errorMessage =
          'No se pudieron consultar los horarios: $error';
      notifyListeners();
      return <DateTime>[];
    }
  }

  Future<void> loadAppointmentById(
    String appointmentId,
  ) async {
    try {
      final raw = await supabase.rpc(
        'get_admin_appointment_by_id',
        params: {'p_appointment_id': appointmentId},
      );

      if (raw == null) return;

      final item = AppointmentRecord.fromMap(
        Map<String, dynamic>.from(raw as Map),
      );

      appointments = [
        item,
        ...appointments.where((a) => a.id != item.id),
      ];

      errorMessage = null;
      notifyListeners();
    } catch (error) {
      // The full list load will still run immediately afterwards.
      errorMessage =
          'No se pudo cargar la solicitud nueva: $error';
      notifyListeners();
    }
  }

  Future<void> loadAppointments() async {
    if (business == null) return;

    try {
      final raw = await supabase.rpc(
        'get_admin_appointments',
        params: {'p_business_id': business!.id},
      );

      appointments = (raw as List<dynamic>)
          .map((row) => AppointmentRecord.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList();

      errorMessage = null;
      notifyListeners();
    } catch (error) {
      errorMessage = 'No se pudieron cargar los turnos: $error';
      notifyListeners();
    }
  }

  Future<bool> createAdminAppointment({
    required String clientId,
    required String serviceId,
    required DateTime startsAt,
    String notes = '',
  }) async {
    if (business == null) return false;

    try {
      await supabase.rpc(
        'create_admin_appointment',
        params: {
          'p_business_id': business!.id,
          'p_client_id': clientId,
          'p_service_id': serviceId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        },
      );

      await loadAppointments();
      await refreshAdminData();
      return true;
    } catch (error) {
      final text = '$error';
      errorMessage = text.contains('appointments_one_slot_uq') ||
              text.contains('APPOINTMENT_SLOT_TAKEN')
          ? 'Ese horario acaba de ocuparse. Elegí otro horario disponible.'
          : 'No se pudo crear el turno: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAppointment({
    required String appointmentId,
    required String clientId,
    required String serviceId,
    required DateTime startsAt,
    String notes = '',
  }) async {
    try {
      await supabase.rpc(
        'update_admin_appointment',
        params: {
          'p_appointment_id': appointmentId,
          'p_client_id': clientId,
          'p_service_id': serviceId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        },
      );

      await loadAppointments();
      await refreshAdminData();
      return true;
    } catch (error) {
      final text = '$error';
      errorMessage = text.contains('appointments_one_slot_uq') ||
              text.contains('APPOINTMENT_SLOT_TAKEN')
          ? 'Ese horario ya está ocupado. Elegí otro.'
          : 'No se pudo editar el turno: $error';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> completeAppointment({
    required String appointmentId,
    required String clientId,
    String? rewardId,
  }) async {
    try {
      final raw = await supabase.rpc(
        'complete_appointment',
        params: {
          'p_appointment_id': appointmentId,
          'p_reward_id': rewardId,
        },
      );

      // refreshAdminData rebuilds the client summaries, therefore reload the
      // selected client's real history/rewards afterwards.
      await loadAppointments();
      await refreshAdminData();
      await loadClientDetail(clientId);

      errorMessage = null;
      notifyListeners();

      return Map<String, dynamic>.from(raw as Map);
    } catch (error) {
      errorMessage = 'No se pudo completar el turno: $error';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    if (status == 'completed') {
      errorMessage =
          'Los turnos realizados deben procesarse con completeAppointment.';
      notifyListeners();
      return false;
    }

    try {
      await supabase.from('appointments').update({
        'status': status,
      }).eq('id', appointmentId);

      await loadAppointments();
      await refreshAdminData();
      return true;
    } catch (error) {
      errorMessage = 'No se pudo actualizar el turno: $error';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> deleteAppointment(
    String appointmentId,
  ) async {
    try {
      final raw = await supabase.rpc(
        'delete_or_cancel_appointment',
        params: {'p_appointment_id': appointmentId},
      );

      await loadAppointments();
      await refreshAdminData();

      return Map<String, dynamic>.from(raw as Map);
    } catch (error) {
      errorMessage = 'No se pudo eliminar el turno: $error';
      notifyListeners();
      return null;
    }
  }

  Future<PublicCardData> fetchPublicCard(String token) async {
    final result = await supabase.rpc(
      'get_public_client_card',
      params: {'p_token': token},
    );

    return PublicCardData.fromMap(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<bool> requestPublicAppointment({
    required String token,
    required String serviceId,
    required DateTime startsAt,
    String notes = '',
  }) async {
    try {
      await supabase.rpc(
        'request_public_appointment',
        params: {
          'p_token': token,
          'p_service_id': serviceId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        },
      );

      return true;
    } catch (error) {
      final text = '$error';
      errorMessage = text.contains('appointments_one_slot_uq') ||
              text.contains('APPOINTMENT_SLOT_TAKEN')
          ? 'Ese horario acaba de reservarse. Elegí otro horario disponible.'
          : 'No se pudo pedir el turno: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> registerAdminPushSubscription(
    PushSubscriptionPayload subscription,
  ) async {
    try {
      await supabase.rpc(
        'register_admin_push_subscription',
        params: subscription.toRpcParams(),
      );
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage =
          'No se pudieron activar las notificaciones: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> registerClientPushSubscription({
    required String token,
    required PushSubscriptionPayload subscription,
  }) async {
    try {
      final params = subscription.toRpcParams();
      params['p_token'] = token;

      await supabase.rpc(
        'register_client_push_subscription',
        params: params,
      );

      errorMessage = null;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage =
          'No se pudieron activar los recordatorios: $error';
      notifyListeners();
      return false;
    }
  }



}
