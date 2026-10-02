import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/services/task/task_service.dart';

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
  group('TaskService Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage('valid_test_token');
    });

    test('getTasks queries /api/v1/tasks with pagination & filters', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/tasks'));
        expect(request.url.queryParameters['status'], equals('pending'));
        expect(request.url.queryParameters['priority'], equals('high'));
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 't1',
                'title': 'High Priority Task',
                'status': 'pending',
                'priority': 'high',
                'attempt_count': 0,
                'max_attempts': 2,
                'created_at': '2026-09-27T10:00:00Z',
                'updated_at': '2026-09-27T10:00:00Z',
              }
            ],
            'total': 1,
            'page': 1,
            'page_size': 20,
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final taskService = TaskService(apiClient: apiClient);

      final result = await taskService.getTasks(status: 'pending', priority: 'high');
      expect(result.items.length, equals(1));
      expect(result.items.first.title, equals('High Priority Task'));
      expect(result.total, equals(1));
    });

    test('recordAttempt and recordOverrideAttempt call respective endpoints', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks/t1/attempt') {
          return http.Response(
            jsonEncode({
              'id': 't1',
              'title': 'Task 1',
              'status': 'pending',
              'priority': 'medium',
              'attempt_count': 1,
              'max_attempts': 2,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:05:00Z',
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/tasks/t1/attempt/override') {
          final body = jsonDecode(request.body);
          expect(body['authorized_override'], isTrue);
          expect(body['reason'], equals('Manager escalation'));
          return http.Response(
            jsonEncode({
              'id': 't1',
              'title': 'Task 1',
              'status': 'pending',
              'priority': 'medium',
              'attempt_count': 3,
              'max_attempts': 2,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:10:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final taskService = TaskService(apiClient: apiClient);

      final att1 = await taskService.recordAttempt('t1', notes: 'First call');
      expect(att1.attemptCount, equals(1));

      final overrideAtt = await taskService.recordOverrideAttempt('t1', reason: 'Manager escalation');
      expect(overrideAtt.attemptCount, equals(3));
    });

    test('postponeTask and updateNextActionDate send correct payload', () async {
      final futureDate = DateTime.parse('2026-10-05T15:00:00Z');
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks/t1/postpone') {
          final body = jsonDecode(request.body);
          expect(body['reason'], equals('Client requested next week'));
          return http.Response(
            jsonEncode({
              'id': 't1',
              'title': 'Task 1',
              'status': 'pending',
              'priority': 'medium',
              'due_date': futureDate.toIso8601String(),
              'attempt_count': 0,
              'max_attempts': 2,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:15:00Z',
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/tasks/t1/next-action') {
          return http.Response(
            jsonEncode({
              'id': 't1',
              'title': 'Task 1',
              'status': 'pending',
              'priority': 'medium',
              'next_action_date': futureDate.toIso8601String(),
              'attempt_count': 0,
              'max_attempts': 2,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:20:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final taskService = TaskService(apiClient: apiClient);

      final postponed = await taskService.postponeTask(
        't1',
        newDueDate: futureDate,
        reason: 'Client requested next week',
      );
      expect(postponed.dueDate, isNotNull);

      final updatedNext = await taskService.updateNextActionDate(
        't1',
        nextActionDate: futureDate,
      );
      expect(updatedNext.nextActionDate, isNotNull);
    });

    test('completeTask and reopenTask call respective endpoints', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks/t1/complete') {
          return http.Response(
            jsonEncode({
              'id': 't1',
              'title': 'Task 1',
              'status': 'completed',
              'priority': 'medium',
              'attempt_count': 1,
              'max_attempts': 2,
              'completed_at': '2026-09-27T11:00:00Z',
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T11:00:00Z',
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/tasks/t1/reopen') {
          final body = jsonDecode(request.body);
          expect(body['reason'], equals('Additional requirements added'));
          return http.Response(
            jsonEncode({
              'id': 't1',
              'title': 'Task 1',
              'status': 'in_progress',
              'priority': 'medium',
              'attempt_count': 1,
              'max_attempts': 2,
              'completed_at': null,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T11:30:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final taskService = TaskService(apiClient: apiClient);

      final completed = await taskService.completeTask('t1');
      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);

      final reopened = await taskService.reopenTask('t1', reason: 'Additional requirements added');
      expect(reopened.isCompleted, isFalse);
      expect(reopened.status, equals('in_progress'));
    });

    test('Reminders and FollowUps integration in TaskService', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks/t1/reminders') {
          return http.Response(
            jsonEncode([
              {
                'id': 'r1',
                'task_id': 't1',
                'remind_at': '2026-09-28T10:00:00Z',
                'message': 'Prepare presentation',
                'is_sent': false,
                'created_at': '2026-09-27T10:00:00Z',
                'updated_at': '2026-09-27T10:00:00Z',
              }
            ]),
            200,
          );
        }
        if (request.url.path == '/api/v1/reminders') {
          return http.Response(
            jsonEncode({
              'id': 'r2',
              'task_id': 't1',
              'remind_at': '2026-09-28T12:00:00Z',
              'message': 'Call before lunch',
              'is_sent': false,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:00:00Z',
            }),
            201,
          );
        }
        if (request.url.path == '/api/v1/reminders/r1/send') {
          return http.Response(
            jsonEncode({
              'id': 'r1',
              'task_id': 't1',
              'remind_at': '2026-09-28T10:00:00Z',
              'message': 'Prepare presentation',
              'is_sent': true,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:05:00Z',
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/tasks/t1/follow-ups') {
          return http.Response(
            jsonEncode([
              {
                'id': 'f1',
                'task_id': 't1',
                'scheduled_at': '2026-09-30T10:00:00Z',
                'completed_at': null,
                'notes': 'Follow up on proposal feedback',
                'created_at': '2026-09-27T10:00:00Z',
                'updated_at': '2026-09-27T10:00:00Z',
              }
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final taskService = TaskService(apiClient: apiClient);

      final reminders = await taskService.getTaskReminders('t1');
      expect(reminders.length, equals(1));
      expect(reminders.first.message, equals('Prepare presentation'));

      final createdReminder = await taskService.createReminder(
        ReminderCreateRequest(
          taskId: 't1',
          remindAt: DateTime.parse('2026-09-28T12:00:00Z'),
          message: 'Call before lunch',
        ),
      );
      expect(createdReminder.id, equals('r2'));

      final sentReminder = await taskService.sendReminder('r1');
      expect(sentReminder.isSent, isTrue);

      final followUps = await taskService.getTaskFollowUps('t1');
      expect(followUps.length, equals(1));
      expect(followUps.first.notes, equals('Follow up on proposal feedback'));
    });

    test('getRecentActivity and getFollowUps query respective workspace endpoints', () async {
      final tokenStorage = InMemoryTokenStorage('valid_jwt_token');
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks/activity/recent') {
          return http.Response(
            jsonEncode([
              {
                'id': 'h1',
                'task_id': 't1',
                'action': 'created',
                'old_value': null,
                'new_value': null,
                'reason': null,
                'created_by_user_id': 'u1',
                'created_at': '2026-09-27T10:00:00Z',
              },
              {
                'id': 'h2',
                'task_id': 't1',
                'action': 'attempt',
                'old_value': '0',
                'new_value': '1',
                'reason': 'First call completed',
                'created_by_user_id': 'u1',
                'created_at': '2026-09-27T10:30:00Z',
              }
            ]),
            200,
          );
        }
        if (request.url.path == '/api/v1/follow-ups') {
          return http.Response(
            jsonEncode([
              {
                'id': 'f1',
                'task_id': 't1',
                'scheduled_at': '2026-09-30T10:00:00Z',
                'completed_at': null,
                'notes': 'Pending review',
                'created_at': '2026-09-27T10:00:00Z',
                'updated_at': '2026-09-27T10:00:00Z',
              }
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final taskService = TaskService(apiClient: apiClient);

      final activities = await taskService.getRecentActivity(limit: 10);
      expect(activities.length, equals(2));
      expect(activities.first.action, equals('created'));
      expect(activities.last.action, equals('attempt'));

      final followUps = await taskService.getFollowUps(isCompleted: false);
      expect(followUps.length, equals(1));
      expect(followUps.first.notes, equals('Pending review'));
    });
  });
}
