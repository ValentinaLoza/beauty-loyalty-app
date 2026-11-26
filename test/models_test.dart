// Parses real responses of the database functions (generated from the test
// database in supabase/tests) with the app's models, so a change on either
// side that breaks the other fails here.
import 'dart:convert';
import 'dart:io';

import 'package:beauty_loyalty_production/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _map(Object? row) =>
    Map<String, dynamic>.from(row! as Map);

void main() {
  group('get_admin_bootstrap', () {
    final data = _fixture('admin_bootstrap.json');

    test('business, loyalty, hours and services parse', () {
      final business = BusinessRecord.fromMap(_map(data['business']));
      expect(business.name, 'Test Studio');
      expect(business.primaryColorHex, '#8F5E78');

      final loyalty = LoyaltyConfig.fromMap(_map(data['loyalty']));
      expect(loyalty.id, isNotEmpty);

      final hours = (data['business_hours'] as List)
          .map((row) => BusinessHoursRecord.fromMap(_map(row)))
          .toList();
      expect(hours, hasLength(7));

      final services = (data['services'] as List)
          .map((row) => ServiceDefinition.fromMap(_map(row)))
          .toList();
      expect(services.single.name, 'Lifting');
    });

    test('client summaries parse', () {
      final clients = (data['clients'] as List)
          .map((row) => ClientRecord.fromDashboard(_map(row)))
          .toList();
      expect(clients, hasLength(1));
      expect(clients.single.firstName, 'Ana');
      expect(clients.single.serviceCount, 7);
      expect(clients.single.publicToken, isNotEmpty);
    });

    test('v3 sends reminder ids, not duplicated client records', () {
      expect(data.containsKey('reminder_clients'), isFalse);
      expect(data['reminder_client_ids'], isA<List<dynamic>>());
    });

    test('appointments, activity and metrics parse', () {
      final appointments = (data['appointments'] as List)
          .map((row) => AppointmentRecord.fromMap(_map(row)))
          .toList();
      expect(appointments, isNotEmpty);
      expect(appointments.first.clientName, 'Ana Pérez');

      final activity = (data['recent_activity'] as List)
          .map((row) => RecentActivityRecord.fromMap(_map(row)))
          .toList();
      expect(activity, isNotEmpty);

      final metrics = BusinessMetrics.fromMap(_map(data['metrics']));
      expect(metrics.clientCount, 1);
      expect(metrics.serviceCount, 7);
      expect(metrics.upcomingAppointments, greaterThanOrEqualTo(1));
    });
  });

  group('get_admin_client_detail', () {
    final data = _fixture('client_detail.json');

    test('history parses with prices and discount', () {
      final history = (data['history'] as List)
          .map((row) => ServiceEntry.fromMap(_map(row)))
          .toList();
      expect(history, hasLength(7));
      expect(
        history.any((entry) => entry.discount == 4000 && entry.finalPrice == 16000),
        isTrue,
      );
    });

    test('rewards parse with redemption date', () {
      final rewards = (data['rewards'] as List)
          .map((row) => RewardRecord.fromMap(_map(row)))
          .toList();
      expect(rewards.single.status, RewardStatus.redeemed);
      expect(rewards.single.redeemedAt, isNotNull);
      expect(rewards.single.percent, 20);
    });
  });

  test('business keeps the last backup date (v3.1)', () {
    final business = BusinessRecord.fromMap({
      'id': 'b1',
      'name': 'Test',
      'last_backup_at': '2026-11-20T10:00:00+00:00',
    });
    expect(business.lastBackupAt, DateTime.utc(2026, 11, 20, 10));
    expect(BusinessRecord.fromMap({'id': 'b2'}).lastBackupAt, isNull);
  });
}
