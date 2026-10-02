// Phase 19: Scheduler Models & Service Unit Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/models/notification/notification_models.dart';
import 'package:nextaction/models/scheduler/scheduler_models.dart';
import 'package:nextaction/services/scheduler/scheduler_service.dart';

class MockSchedulerApiClient extends ApiClient {
  Map<String, dynamic>? lastPostBody;
  Map<String, dynamic>? mockResponse;

  @override
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    if (path == '/scheduler/evaluate') {
      lastPostBody = body as Map<String, dynamic>?;
      return mockResponse ?? _sampleEvaluationResponse();
    }
    throw UnimplementedError('POST $path not mocked');
  }

  static Map<String, dynamic> _sampleEvaluationResponse() {
    return {
      'evaluated': 25,
      'notifications_created': 5,
      'duplicates_skipped': 3,
      'preferences_suppressed': 2,
      'errors_count': 0,
      'duration_ms': 14.5,
      'evaluated_at': '2026-09-29T15:30:00.000Z',
      'user_id': 'user-456',
      'details': {
        'reminders': {
          'evaluated': 5,
          'notifications_created': 1,
          'duplicates_skipped': 1,
          'preferences_suppressed': 0,
          'errors': 0,
        },
        'follow_ups': {
          'evaluated': 5,
          'notifications_created': 1,
          'duplicates_skipped': 1,
          'preferences_suppressed': 0,
          'errors': 0,
        },
        'next_actions': {
          'evaluated': 5,
          'notifications_created': 1,
          'duplicates_skipped': 0,
          'preferences_suppressed': 1,
          'errors': 0,
        },
        'overdue_tasks': {
          'evaluated': 5,
          'notifications_created': 1,
          'duplicates_skipped': 1,
          'preferences_suppressed': 1,
          'errors': 0,
        },
        'attempt_limits': {
          'evaluated': 5,
          'notifications_created': 1,
          'duplicates_skipped': 0,
          'preferences_suppressed': 0,
          'errors': 0,
        },
      },
    };
  }
}

void main() {
  group('Phase 19 Scheduler Models Tests', () {
    test('CategoryEvaluationDetail fromJson and toJson round-trip', () {
      final json = {
        'evaluated': 10,
        'notifications_created': 3,
        'duplicates_skipped': 2,
        'preferences_suppressed': 1,
        'errors': 0,
      };

      final detail = CategoryEvaluationDetail.fromJson(json);
      expect(detail.evaluated, 10);
      expect(detail.notificationsCreated, 3);
      expect(detail.duplicatesSkipped, 2);
      expect(detail.preferencesSuppressed, 1);
      expect(detail.errors, 0);

      final encoded = detail.toJson();
      expect(encoded['evaluated'], 10);
      expect(encoded['notifications_created'], 3);
      expect(encoded['duplicates_skipped'], 2);
      expect(encoded['preferences_suppressed'], 1);
    });

    test('SchedulerEvaluationResponse fromJson parses details map and metrics', () {
      final json = MockSchedulerApiClient._sampleEvaluationResponse();
      final res = SchedulerEvaluationResponse.fromJson(json);

      expect(res.evaluated, 25);
      expect(res.notificationsCreated, 5);
      expect(res.duplicatesSkipped, 3);
      expect(res.preferencesSuppressed, 2);
      expect(res.errorsCount, 0);
      expect(res.durationMs, 14.5);
      expect(res.userId, 'user-456');

      expect(res.details.containsKey('reminders'), isTrue);
      expect(res.details['reminders']!.evaluated, 5);
      expect(res.details['reminders']!.notificationsCreated, 1);
      expect(res.details.containsKey('attempt_limits'), isTrue);

      final encoded = res.toJson();
      expect(encoded['evaluated'], 25);
      expect(encoded['details']['reminders']['evaluated'], 5);
    });

    test('AppNotification isAttemptLimit recognizes both max and near max types', () {
      final n1 = AppNotification(
        id: 'n1',
        userId: 'u1',
        type: 'attempt_limit_reached',
        title: 'Max Attempts',
        message: 'Max reached',
        isRead: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(n1.isAttemptLimit, isTrue);

      final n2 = AppNotification(
        id: 'n2',
        userId: 'u1',
        type: 'near_max_attempts',
        title: 'Near Max',
        message: 'Approaching limit',
        isRead: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(n2.isAttemptLimit, isTrue);

      final n3 = AppNotification(
        id: 'n3',
        userId: 'u1',
        type: 'task_assigned',
        title: 'Assigned',
        message: 'Assigned',
        isRead: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(n3.isAttemptLimit, isFalse);
    });
  });

  group('Phase 19 SchedulerService Tests', () {
    test('evaluateScheduler sends correct request body and parses response', () async {
      final mockClient = MockSchedulerApiClient();
      final service = SchedulerService(apiClient: mockClient);

      final asOf = DateTime.utc(2026, 9, 29, 20, 0, 0);
      final response = await service.evaluateScheduler(
        asOf: asOf,
        userScoped: true,
      );

      expect(mockClient.lastPostBody, isNotNull);
      expect(mockClient.lastPostBody!['user_scoped'], isTrue);
      expect(mockClient.lastPostBody!['as_of'], '2026-09-29T20:00:00.000Z');

      expect(response.evaluated, 25);
      expect(response.notificationsCreated, 5);
      expect(response.duplicatesSkipped, 3);
      expect(response.details.length, 5);
    });
  });
}
