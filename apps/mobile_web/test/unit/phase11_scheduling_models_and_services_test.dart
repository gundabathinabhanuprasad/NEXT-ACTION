import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/widgets/common_widgets.dart';

class InMemoryTokenStorage implements TokenStorage {
  String? token;
  InMemoryTokenStorage([this.token]);

  @override
  Future<void> saveToken(String token) async => this.token = token;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<bool> hasToken() async => token != null && token!.isNotEmpty;
}

void main() {
  group('Phase 11 - Model Parsing & Date Handling Tests', () {
    test('Reminder model parses from JSON and serializes to JSON correctly', () {
      final now = DateTime.utc(2026, 9, 28, 12, 0, 0);
      final json = {
        'id': 'rem-1',
        'task_id': 'task-100',
        'remind_at': now.toIso8601String(),
        'message': 'Review contract terms with client',
        'is_sent': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final reminder = Reminder.fromJson(json);
      expect(reminder.id, equals('rem-1'));
      expect(reminder.taskId, equals('task-100'));
      expect(reminder.message, equals('Review contract terms with client'));
      expect(reminder.isSent, isTrue);
      expect(reminder.remindAt.toUtc(), equals(now));

      final serialized = reminder.toJson();
      expect(serialized['id'], equals('rem-1'));
      expect(serialized['task_id'], equals('task-100'));
      expect(serialized['message'], equals('Review contract terms with client'));
      expect(serialized['is_sent'], isTrue);
    });

    test('Reminder model handles missing message, sent_at and updated_at gracefully', () {
      final json = {
        'id': 'rem-2',
        'task_id': 'task-200',
        'remind_at': '2026-09-29T10:00:00Z',
      };

      final reminder = Reminder.fromJson(json);
      expect(reminder.id, equals('rem-2'));
      expect(reminder.taskId, equals('task-200'));
      expect(reminder.message, equals(''));
      expect(reminder.isSent, isFalse);
    });

    test('ReminderCreateRequest serializes payload correctly', () {
      final remindAt = DateTime.utc(2026, 9, 30, 9, 0, 0);
      final request = ReminderCreateRequest(
        taskId: 'task-300',
        remindAt: remindAt,
        message: 'Reminder notification note',
      );

      final json = request.toJson();
      expect(json['task_id'], equals('task-300'));
      expect(json['remind_at'], equals('2026-09-30T09:00:00.000Z'));
      expect(json['message'], equals('Reminder notification note'));
    });

    test('FollowUp model parses from JSON and serializes correctly', () {
      final scheduled = DateTime.utc(2026, 9, 29, 15, 0, 0);
      final completed = DateTime.utc(2026, 9, 29, 16, 0, 0);
      final json = {
        'id': 'fol-1',
        'task_id': 'task-400',
        'scheduled_at': scheduled.toIso8601String(),
        'completed_at': completed.toIso8601String(),
        'notes': 'Spoke with CFO, agreed on pricing',
        'created_at': scheduled.toIso8601String(),
        'updated_at': completed.toIso8601String(),
      };

      final followUp = FollowUp.fromJson(json);
      expect(followUp.id, equals('fol-1'));
      expect(followUp.taskId, equals('task-400'));
      expect(followUp.isCompleted, isTrue);
      expect(followUp.notes, equals('Spoke with CFO, agreed on pricing'));
      expect(followUp.completedAt, isNotNull);

      final serialized = followUp.toJson();
      expect(serialized['id'], equals('fol-1'));
      expect(serialized['is_completed'], isNull); // not in json schema directly
      expect(serialized['notes'], equals('Spoke with CFO, agreed on pricing'));
    });

    test('FollowUp model handles pending state and null optional fields', () {
      final json = {
        'id': 'fol-2',
        'task_id': 'task-500',
        'scheduled_at': '2026-09-30T10:00:00Z',
      };

      final followUp = FollowUp.fromJson(json);
      expect(followUp.id, equals('fol-2'));
      expect(followUp.isCompleted, isFalse);
      expect(followUp.completedAt, isNull);
      expect(followUp.notes, isNull);
    });

    test('AppDateFormat formats dates consistently and safely', () {
      expect(AppDateFormat.formatDateTime(null), equals('None'));
      expect(AppDateFormat.formatDate(null), equals('None'));
      expect(AppDateFormat.formatRelativeDate(null), equals('No due date'));

      final dt = DateTime(2026, 9, 28, 14, 30);
      expect(AppDateFormat.formatDate(dt), equals('2026-09-28'));
      expect(AppDateFormat.formatDateTime(dt), equals('2026-09-28 14:30'));
    });
  });

  group('Phase 11 - ReminderService REST Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      tokenStorage = InMemoryTokenStorage('test-jwt-token');
    });

    test('getReminders sends proper query params and parses list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/reminders'));
        expect(request.url.queryParameters['task_id'], equals('task-1'));
        expect(request.url.queryParameters['is_sent'], equals('false'));
        expect(request.headers['Authorization'], equals('Bearer test-jwt-token'));

        return http.Response(
          jsonEncode([
            {
              'id': 'rem-1',
              'task_id': 'task-1',
              'remind_at': '2026-09-28T18:00:00Z',
              'message': 'Check deliverables',
              'is_sent': false,
              'created_at': '2026-09-28T12:00:00Z',
              'updated_at': '2026-09-28T12:00:00Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = ReminderService(apiClient: apiClient);

      final list = await service.getReminders(taskId: 'task-1', isSent: false);
      expect(list.length, equals(1));
      expect(list[0].id, equals('rem-1'));
      expect(list[0].message, equals('Check deliverables'));
      expect(list[0].isSent, isFalse);
    });

    test('getDueReminders calls /reminders/due with as_of parameter', () async {
      final asOf = DateTime.utc(2026, 9, 28, 20, 0, 0);
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/reminders/due'));
        expect(request.url.queryParameters['as_of'], equals(asOf.toIso8601String()));

        return http.Response(
          jsonEncode([
            {
              'id': 'rem-due-1',
              'task_id': 'task-2',
              'remind_at': '2026-09-28T19:00:00Z',
              'message': 'Due notification',
              'is_sent': false,
              'created_at': '2026-09-28T12:00:00Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = ReminderService(apiClient: apiClient);

      final due = await service.getDueReminders(asOf: asOf);
      expect(due.length, equals(1));
      expect(due[0].id, equals('rem-due-1'));
    });

    test('sendReminder calls /reminders/{id}/send', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, equals('/api/v1/reminders/rem-99/send'));

        return http.Response(
          jsonEncode({
            'id': 'rem-99',
            'task_id': 'task-3',
            'remind_at': '2026-09-28T12:00:00Z',
            'message': 'Sent alert',
            'is_sent': true,
            'sent_at': '2026-09-28T12:05:00Z',
            'created_at': '2026-09-28T10:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = ReminderService(apiClient: apiClient);

      final sent = await service.sendReminder('rem-99');
      expect(sent.id, equals('rem-99'));
      expect(sent.isSent, isTrue);
    });

    test('deleteReminder sends DELETE to /reminders/{id}', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('DELETE'));
        expect(request.url.path, equals('/api/v1/reminders/rem-delete'));
        return http.Response('', 204);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = ReminderService(apiClient: apiClient);

      await expectLater(service.deleteReminder('rem-delete'), completes);
    });
  });

  group('Phase 11 - FollowUpService REST Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      tokenStorage = InMemoryTokenStorage('test-jwt-token');
    });

    test('getFollowUps retrieves list with completion filter', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/follow-ups'));
        expect(request.url.queryParameters['is_completed'], equals('true'));

        return http.Response(
          jsonEncode([
            {
              'id': 'fol-done',
              'task_id': 'task-10',
              'scheduled_at': '2026-09-27T10:00:00Z',
              'completed_at': '2026-09-27T11:00:00Z',
              'notes': 'Done deal',
              'created_at': '2026-09-26T10:00:00Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = FollowUpService(apiClient: apiClient);

      final list = await service.getFollowUps(isCompleted: true);
      expect(list.length, equals(1));
      expect(list[0].id, equals('fol-done'));
      expect(list[0].isCompleted, isTrue);
    });

    test('completeFollowUp sends completion payload and updates notes', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, equals('/api/v1/follow-ups/fol-act/complete'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['notes'], equals('Follow-up accomplished'));

        return http.Response(
          jsonEncode({
            'id': 'fol-act',
            'task_id': 'task-11',
            'scheduled_at': '2026-09-28T09:00:00Z',
            'completed_at': '2026-09-28T10:00:00Z',
            'notes': 'Follow-up accomplished',
            'created_at': '2026-09-27T10:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = FollowUpService(apiClient: apiClient);

      final completed = await service.completeFollowUp('fol-act', notes: 'Follow-up accomplished');
      expect(completed.id, equals('fol-act'));
      expect(completed.isCompleted, isTrue);
      expect(completed.notes, equals('Follow-up accomplished'));
    });

    test('deleteFollowUp sends DELETE to /follow-ups/{id}', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('DELETE'));
        expect(request.url.path, equals('/api/v1/follow-ups/fol-remove'));
        return http.Response('', 204);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = FollowUpService(apiClient: apiClient);

      await expectLater(service.deleteFollowUp('fol-remove'), completes);
    });
  });
}
