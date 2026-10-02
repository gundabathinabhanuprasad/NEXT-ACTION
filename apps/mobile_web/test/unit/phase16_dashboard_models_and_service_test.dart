import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/dashboard/dashboard_models.dart';
import 'package:nextaction/services/dashboard/dashboard_service.dart';

class TestTokenStorage implements TokenStorage {
  String? _token = 'mock_valid_token';
  @override
  Future<void> saveToken(String token) async => _token = token;
  @override
  Future<String?> getToken() async => _token;
  @override
  Future<void> deleteToken() async => _token = null;
  @override
  Future<bool> hasToken() async => _token != null && _token!.isNotEmpty;
}

void main() {
  group('Phase 16: Dashboard Models & Time Ranges', () {
    test('DashboardTimeRange enum and helper parsing', () {
      expect(DashboardTimeRange.fromApiValue('today'), equals(DashboardTimeRange.today));
      expect(DashboardTimeRange.fromApiValue('last_7_days'), equals(DashboardTimeRange.last7Days));
      expect(DashboardTimeRange.fromApiValue('last_30_days'), equals(DashboardTimeRange.last30Days));
      expect(DashboardTimeRange.fromApiValue('this_month'), equals(DashboardTimeRange.thisMonth));
      expect(DashboardTimeRange.fromApiValue('unknown'), equals(DashboardTimeRange.last7Days));
    });

    test('DashboardSummary parses complete server JSON response correctly', () {
      final jsonMap = {
        'time_range': 'last_7_days',
        'range_start': '2026-09-22T00:00:00Z',
        'range_end': '2026-09-29T23:59:59Z',
        'kpis': {
          'total_open_tasks': 15,
          'due_today_tasks': 4,
          'overdue_tasks': 2,
          'upcoming_tasks': 6,
          'completed_tasks': 25,
          'completed_in_range': 8,
          'created_in_range': 10,
          'near_max_attempts': 3,
          'max_attempts_reached': 1,
          'pending_follow_ups': 5,
          'overdue_follow_ups': 1,
          'due_today_follow_ups': 2,
          'due_reminders': 3,
          'unread_notifications': 4,
        },
        'attention': {
          'urgent_count': 6,
          'today_count': 7,
        },
        'status_distribution': {
          'pending': 7,
          'in_progress': 8,
          'completed': 25,
          'cancelled': 2,
        },
        'priority_distribution': {
          'urgent': 3,
          'high': 5,
          'medium': 4,
          'low': 3,
        },
        'attempt_pressure': {
          'zero_attempts': 6,
          'one_attempt': 5,
          'near_max': 3,
          'max_reached': 1,
        },
        'workload': {
          'by_assignee': [
            {
              'user_id': 'u1',
              'user_name': 'Alice Developer',
              'open_tasks': 8,
              'due_today': 2,
              'overdue': 1,
              'completed': 12,
            },
            {
              'user_id': null,
              'user_name': 'Unassigned',
              'open_tasks': 4,
              'due_today': 1,
              'overdue': 0,
              'completed': 0,
            }
          ],
          'by_client': [
            {
              'client_id': 'c1',
              'client_name': 'Acme Corp',
              'open_tasks': 6,
              'due_today': 2,
              'overdue': 1,
              'completed': 10,
            }
          ],
          'by_workflow': [
            {
              'workflow_id': 'w1',
              'workflow_name': 'Customer Onboarding',
              'open_tasks': 5,
              'due_today': 1,
              'overdue': 0,
              'completed': 8,
            }
          ],
        },
        'scheduling': {
          'follow_ups': {
            'pending': 5,
            'overdue': 1,
            'due_today': 2,
            'upcoming': 2,
            'completed': 8,
          },
          'reminders': {
            'pending': 7,
            'due_today': 3,
            'overdue': 1,
            'upcoming': 3,
          },
        },
        'trends': [
          {
            'date': '2026-09-28',
            'created_count': 3,
            'completed_count': 2,
            'overdue_count': 1,
          },
          {
            'date': '2026-09-29',
            'created_count': 4,
            'completed_count': 3,
            'overdue_count': 0,
          },
        ],
        'recent_activities': [],
        'recent_notifications': [],
      };

      final summary = DashboardSummary.fromJson(jsonMap);

      expect(summary.timeRange, equals('last_7_days'));
      expect(summary.kpis.totalOpenTasks, equals(15));
      expect(summary.kpis.dueTodayTasks, equals(4));
      expect(summary.kpis.overdueTasks, equals(2));
      expect(summary.kpis.completedInRange, equals(8));
      expect(summary.kpis.createdInRange, equals(10));
      expect(summary.kpis.nearMaxAttempts, equals(3));
      expect(summary.kpis.unreadNotifications, equals(4));

      expect(summary.attention.urgentCount, equals(6));
      expect(summary.attention.todayCount, equals(7));

      expect(summary.statusDistribution.pending, equals(7));
      expect(summary.statusDistribution.total, equals(42));

      expect(summary.priorityDistribution.urgent, equals(3));
      expect(summary.priorityDistribution.total, equals(15));

      expect(summary.attemptPressure.zeroAttempts, equals(6));
      expect(summary.attemptPressure.maxReached, equals(1));

      expect(summary.workload.byAssignee.length, equals(2));
      expect(summary.workload.byAssignee[0].userName, equals('Alice Developer'));
      expect(summary.workload.byAssignee[1].userId, isNull);

      expect(summary.workload.byClient.length, equals(1));
      expect(summary.workload.byClient[0].clientName, equals('Acme Corp'));

      expect(summary.workload.byWorkflow.length, equals(1));
      expect(summary.workload.byWorkflow[0].workflowName, equals('Customer Onboarding'));

      expect(summary.scheduling.followUps.pending, equals(5));
      expect(summary.scheduling.reminders.dueToday, equals(3));

      expect(summary.trends.length, equals(2));
      expect(summary.trends[0].createdCount, equals(3));
      expect(summary.trends[1].completedCount, equals(3));
    });
  });

  group('Phase 16: DashboardService API integration', () {
    test('getDashboardSummary calls GET /api/v1/dashboard/summary with time_range query param', () async {
      late Uri capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        if (request.url.path == '/api/v1/dashboard/summary') {
          return http.Response(
            jsonEncode({
              'time_range': request.url.queryParameters['time_range'] ?? 'last_7_days',
              'range_start': '2026-09-22T00:00:00Z',
              'range_end': '2026-09-29T23:59:59Z',
              'kpis': {
                'total_open_tasks': 10,
                'due_today_tasks': 2,
                'overdue_tasks': 1,
                'upcoming_tasks': 3,
                'completed_tasks': 20,
                'completed_in_range': 5,
                'created_in_range': 6,
                'near_max_attempts': 1,
                'max_attempts_reached': 0,
                'pending_follow_ups': 2,
                'overdue_follow_ups': 0,
                'due_today_follow_ups': 1,
                'due_reminders': 2,
                'unread_notifications': 1,
              },
              'attention': {'urgent_count': 1, 'today_count': 3},
              'status_distribution': {'pending': 5, 'in_progress': 5, 'completed': 20, 'cancelled': 0},
              'priority_distribution': {'urgent': 1, 'high': 3, 'medium': 4, 'low': 2},
              'attempt_pressure': {'zero_attempts': 5, 'one_attempt': 3, 'near_max': 1, 'max_reached': 0},
              'workload': {'by_assignee': [], 'by_client': [], 'by_workflow': []},
              'scheduling': {
                'follow_ups': {'pending': 2, 'overdue': 0, 'due_today': 1, 'upcoming': 1, 'completed': 5},
                'reminders': {'pending': 3, 'due_today': 2, 'overdue': 0, 'upcoming': 1},
              },
              'trends': [],
              'recent_activities': [],
              'recent_notifications': [],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: TestTokenStorage());
      final service = DashboardService(apiClient: apiClient);

      final summary = await service.getDashboardSummary(timeRange: 'this_month');

      expect(capturedUri.path, equals('/api/v1/dashboard/summary'));
      expect(capturedUri.queryParameters['time_range'], equals('this_month'));
      expect(summary.kpis.totalOpenTasks, equals(10));
      expect(summary.kpis.completedInRange, equals(5));
      expect(summary.attention.urgentCount, equals(1));
    });
  });
}
