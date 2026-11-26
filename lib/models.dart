enum RewardStatus { available, redeemed, cancelled }

class BusinessRecord {
  BusinessRecord({
    required this.id,
    required this.name,
    required this.primaryColorHex,
    required this.phone,
    required this.logoUrl,
    required this.appointmentSlotMinutes,
  });

  final String id;
  String name;
  String primaryColorHex;
  String phone;
  String logoUrl;
  int appointmentSlotMinutes;

  factory BusinessRecord.fromMap(Map<String, dynamic> map) {
    return BusinessRecord(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Loyalty Studio',
      primaryColorHex:
          map['primary_color_hex'] as String? ?? '#8F5E78',
      phone: map['phone'] as String? ?? '',
      logoUrl: map['logo_url'] as String? ?? '',
      appointmentSlotMinutes:
          (map['appointment_slot_minutes'] as num?)?.toInt() ?? 30,
    );
  }
}


class BusinessHoursRecord {
  BusinessHoursRecord({
    required this.weekday,
    required this.enabled,
    required this.opensAt,
    required this.closesAt,
  });

  final int weekday;
  bool enabled;
  String opensAt;
  String closesAt;

  BusinessHoursRecord copy() => BusinessHoursRecord(
        weekday: weekday,
        enabled: enabled,
        opensAt: opensAt,
        closesAt: closesAt,
      );

  factory BusinessHoursRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    String normalizeTime(dynamic raw, String fallback) {
      final text = raw?.toString() ?? fallback;
      return text.length >= 5 ? text.substring(0, 5) : fallback;
    }

    return BusinessHoursRecord(
      weekday: (map['weekday'] as num).toInt(),
      enabled: map['enabled'] as bool? ?? true,
      opensAt: normalizeTime(map['opens_at'], '08:00'),
      closesAt: normalizeTime(map['closes_at'], '21:00'),
    );
  }

  static List<BusinessHoursRecord> defaultWeek() =>
      List.generate(
        7,
        (index) => BusinessHoursRecord(
          weekday: index + 1,
          enabled: true,
          opensAt: '08:00',
          closesAt: '21:00',
        ),
      );
}

class LoyaltyConfig {
  LoyaltyConfig({
    required this.id,
    required this.pointsRequired,
    required this.rewardPercent,
  });

  final String id;
  int pointsRequired;
  double rewardPercent;

  factory LoyaltyConfig.fromMap(Map<String, dynamic> map) {
    return LoyaltyConfig(
      id: map['id'] as String,
      pointsRequired: (map['points_required'] as num).toInt(),
      rewardPercent: (map['reward_percent'] as num).toDouble(),
    );
  }
}

class ServiceDefinition {
  ServiceDefinition({
    required this.id,
    required this.name,
    required this.price,
    required this.points,
    required this.active,
  });

  final String id;
  String name;
  double price;
  int points;
  bool active;

  factory ServiceDefinition.fromMap(Map<String, dynamic> map) {
    return ServiceDefinition(
      id: map['id'] as String,
      name: map['name'] as String,
      price: (map['default_price'] as num).toDouble(),
      points: (map['loyalty_points'] as num).toInt(),
      active: map['active'] as bool? ?? true,
    );
  }
}

class ServiceEntry {
  ServiceEntry({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.basePrice,
    required this.discount,
    required this.finalPrice,
    required this.pointsEarned,
    required this.performedAt,
  });

  final String id;
  final String serviceId;
  final String serviceName;
  final double basePrice;
  final double discount;
  final double finalPrice;
  final int pointsEarned;
  final DateTime performedAt;

  factory ServiceEntry.fromMap(Map<String, dynamic> map) {
    return ServiceEntry(
      id: map['id'] as String,
      serviceId: map['service_id'] as String? ?? '',
      serviceName: map['service_name_snapshot'] as String? ??
          map['service_name'] as String? ??
          'Servicio',
      basePrice: (map['base_price'] as num).toDouble(),
      discount: (map['discount_amount'] as num).toDouble(),
      finalPrice: (map['final_price'] as num).toDouble(),
      pointsEarned: (map['loyalty_points_earned'] as num?)?.toInt() ??
          (map['points_earned'] as num?)?.toInt() ??
          0,
      performedAt: DateTime.parse(map['performed_at'] as String),
    );
  }
}

class RewardRecord {
  RewardRecord({
    required this.id,
    required this.percent,
    required this.status,
    required this.issuedAt,
    this.redeemedAt,
  });

  final String id;
  final double percent;
  RewardStatus status;
  final DateTime issuedAt;
  DateTime? redeemedAt;

  String get title => '${percent.toStringAsFixed(0)}% OFF';

  factory RewardRecord.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status'] as String? ?? 'available';
    return RewardRecord(
      id: map['id'] as String,
      percent: (map['reward_percent_snapshot'] as num?)?.toDouble() ??
          (map['percent'] as num?)?.toDouble() ??
          0,
      status: RewardStatus.values.firstWhere(
        (status) => status.name == rawStatus,
        orElse: () => RewardStatus.available,
      ),
      issuedAt: DateTime.parse(map['issued_at'] as String),
      redeemedAt: map['redeemed_at'] == null
          ? null
          : DateTime.parse(map['redeemed_at'] as String),
    );
  }
}

class ClientRecord {
  ClientRecord({
    required this.id,
    required this.publicToken,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.points,
    required this.availableRewards,
    required this.serviceCount,
    this.lastServiceAt,
    List<ServiceEntry>? history,
    List<RewardRecord>? rewards,
  })  : history = history ?? <ServiceEntry>[],
        rewards = rewards ?? <RewardRecord>[];

  final String id;
  String publicToken;
  String firstName;
  String lastName;
  String phone;
  String email;
  int points;
  int availableRewards;
  int serviceCount;
  DateTime? lastServiceAt;
  final List<ServiceEntry> history;
  final List<RewardRecord> rewards;

  String get fullName => '$firstName $lastName'.trim();

  factory ClientRecord.fromDashboard(Map<String, dynamic> map) {
    return ClientRecord(
      id: map['id'] as String,
      publicToken: map['public_token'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      points: (map['points'] as num?)?.toInt() ?? 0,
      availableRewards:
          (map['available_rewards'] as num?)?.toInt() ?? 0,
      serviceCount: (map['service_count'] as num?)?.toInt() ?? 0,
      lastServiceAt: map['last_service_at'] == null
          ? null
          : DateTime.parse(map['last_service_at'] as String),
    );
  }
}

class BusinessMetrics {
  const BusinessMetrics({
    required this.clientCount,
    required this.serviceCount,
    required this.availableRewards,
    required this.revenue,
    required this.servicesThisMonth,
    required this.revenueThisMonth,
    required this.upcomingAppointments,
  });

  final int clientCount;
  final int serviceCount;
  final int availableRewards;
  final double revenue;
  final int servicesThisMonth;
  final double revenueThisMonth;
  final int upcomingAppointments;

  static const empty = BusinessMetrics(
    clientCount: 0,
    serviceCount: 0,
    availableRewards: 0,
    revenue: 0,
    servicesThisMonth: 0,
    revenueThisMonth: 0,
    upcomingAppointments: 0,
  );

  factory BusinessMetrics.fromMap(Map<String, dynamic> map) {
    return BusinessMetrics(
      clientCount: (map['client_count'] as num?)?.toInt() ?? 0,
      serviceCount: (map['service_count'] as num?)?.toInt() ?? 0,
      availableRewards:
          (map['available_rewards'] as num?)?.toInt() ?? 0,
      revenue: (map['revenue'] as num?)?.toDouble() ?? 0,
      servicesThisMonth:
          (map['services_this_month'] as num?)?.toInt() ?? 0,
      revenueThisMonth:
          (map['revenue_this_month'] as num?)?.toDouble() ?? 0,
      upcomingAppointments:
          (map['upcoming_appointments'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecentActivityRecord {
  RecentActivityRecord({
    required this.clientName,
    required this.serviceName,
    required this.finalPrice,
    required this.performedAt,
  });

  final String clientName;
  final String serviceName;
  final double finalPrice;
  final DateTime performedAt;

  factory RecentActivityRecord.fromMap(Map<String, dynamic> map) {
    return RecentActivityRecord(
      clientName: map['client_name'] as String,
      serviceName: map['service_name'] as String,
      finalPrice: (map['final_price'] as num).toDouble(),
      performedAt: DateTime.parse(map['performed_at'] as String),
    );
  }
}

class AppointmentRecord {
  AppointmentRecord({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.serviceId,
    required this.serviceName,
    required this.startsAt,
    required this.status,
    required this.source,
    required this.notes,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String serviceId;
  final String serviceName;
  final DateTime startsAt;
  String status;
  final String source;
  final String notes;

  factory AppointmentRecord.fromMap(Map<String, dynamic> map) {
    return AppointmentRecord(
      id: map['id'] as String,
      clientId: map['client_id'] as String,
      clientName: map['client_name'] as String? ?? '',
      serviceId: map['service_id'] as String,
      serviceName: map['service_name'] as String? ?? '',
      startsAt: DateTime.parse(map['starts_at'] as String),
      status: map['status'] as String,
      source: map['source'] as String? ?? 'admin',
      notes: map['notes'] as String? ?? '',
    );
  }
}

class PublicCardData {
  PublicCardData({
    required this.business,
    required this.client,
    required this.loyalty,
    required this.history,
    required this.rewards,
    required this.services,
    required this.appointments,
  });

  final BusinessRecord business;
  final ClientRecord client;
  final LoyaltyConfig loyalty;
  final List<ServiceEntry> history;
  final List<RewardRecord> rewards;
  final List<ServiceDefinition> services;
  final List<AppointmentRecord> appointments;

  factory PublicCardData.fromMap(Map<String, dynamic> map) {
    final businessMap = Map<String, dynamic>.from(map['business'] as Map);
    final clientMap = Map<String, dynamic>.from(map['client'] as Map);
    final loyaltyMap = Map<String, dynamic>.from(map['loyalty'] as Map);

    final history = (map['history'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => ServiceEntry.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();

    final rewards = (map['rewards'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => RewardRecord.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();

    final services = (map['services'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => ServiceDefinition.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();

    final appointments =
        (map['appointments'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => AppointmentRecord.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();

    return PublicCardData(
      business: BusinessRecord.fromMap(businessMap),
      client: ClientRecord(
        id: clientMap['id'] as String,
        publicToken: '',
        firstName: clientMap['first_name'] as String,
        lastName: clientMap['last_name'] as String,
        phone: '',
        email: '',
        points: (clientMap['points'] as num?)?.toInt() ?? 0,
        availableRewards:
            (clientMap['available_rewards'] as num?)?.toInt() ?? 0,
        serviceCount: history.length,
        history: history,
        rewards: rewards,
      ),
      loyalty: LoyaltyConfig(
        id: loyaltyMap['id'] as String? ?? '',
        pointsRequired:
            (loyaltyMap['points_required'] as num?)?.toInt() ?? 5,
        rewardPercent:
            (loyaltyMap['reward_percent'] as num?)?.toDouble() ?? 20,
      ),
      history: history,
      rewards: rewards,
      services: services,
      appointments: appointments,
    );
  }
}
