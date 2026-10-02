import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/report/report_models.dart';
import 'package:nextaction/services/report/report_service.dart';

class MockTokenStorage implements TokenStorage {
  String? _token = 'mock_jwt_token';
  @override
  Future<String?> getToken() async => _token;
  @override
  Future<void> saveToken(String token) async => _token = token;
  @override
  Future<void> deleteToken() async => _token = null;
  @override
  Future<bool> hasToken() async => _token != null;
}

void main() {
  group('Phase 17: Report Models & Enums Tests', () {
    test('ReportType enum serialization and lookup', () {
      expect(ReportType.taskSummary.apiValue, 'task_summary');
      expect(ReportType.taskDetail.apiValue, 'task_detail');
      expect(ReportType.productivity.apiValue, 'productivity');
      expect(ReportType.workload.apiValue, 'workload');
      expect(ReportType.activity.apiValue, 'activity');
      expect(ReportType.remindersFollowups.apiValue, 'reminders_followups');

      expect(ReportType.fromApiValue('task_summary'), ReportType.taskSummary);
      expect(ReportType.fromApiValue('workload'), ReportType.workload);
      expect(ReportType.fromApiValue('unknown_val'), ReportType.taskSummary);
    });

    test('ExportFormat enum serialization', () {
      expect(ExportFormat.csv.apiValue, 'csv');
      expect(ExportFormat.json.apiValue, 'json');
    });

    test('ReportFilters toQueryParams query string formatting', () {
      final from = DateTime.utc(2026, 9, 1);
      final to = DateTime.utc(2026, 9, 30);
      final filters = ReportFilters(
        dateFrom: from,
        dateTo: to,
        status: 'pending',
        priority: 'urgent',
        clientId: 'client-123',
        workflowId: 'workflow-456',
        assignedUserId: 'user-789',
        unassigned: true,
        overdue: true,
        dueToday: true,
        search: 'migration',
        source: 'manual',
      );

      final params = filters.toQueryParams();
      expect(params['date_from'], from.toIso8601String());
      expect(params['date_to'], to.toIso8601String());
      expect(params['status'], 'pending');
      expect(params['priority'], 'urgent');
      expect(params['client_id'], 'client-123');
      expect(params['workflow_id'], 'workflow-456');
      expect(params['assigned_user_id'], 'user-789');
      expect(params['unassigned'], 'true');
      expect(params['overdue'], 'true');
      expect(params['due_today'], 'true');
      expect(params['search'], 'migration');
      expect(params['source'], 'manual');
    });

    test('TaskSummaryReport parses from backend JSON correctly', () {
      final jsonMap = {
        'total_tasks': 10,
        'open_tasks': 6,
        'completed_tasks': 3,
        'cancelled_tasks': 1,
        'overdue_tasks': 2,
        'due_today_tasks': 1,
        'upcoming_tasks': 3,
        'near_max_attempts': 2,
        'max_attempts_reached': 1,
        'status_breakdown': {
          'pending': 4,
          'in_progress': 2,
          'completed': 3,
          'cancelled': 1,
        },
        'priority_breakdown': {
          'urgent': 2,
          'high': 3,
          'medium': 4,
          'low': 1,
        },
      };

      final report = TaskSummaryReport.fromJson(jsonMap);
      expect(report.totalTasks, 10);
      expect(report.openTasks, 6);
      expect(report.completedTasks, 3);
      expect(report.cancelledTasks, 1);
      expect(report.overdueTasks, 2);
      expect(report.statusBreakdown.pending, 4);
      expect(report.statusBreakdown.completed, 3);
      expect(report.priorityBreakdown.urgent, 2);
      expect(report.priorityBreakdown.low, 1);
    });

    test('TaskDetailReportResponse parses paginated items', () {
      final jsonMap = {
        'total': 1,
        'page': 1,
        'page_size': 20,
        'items': [
          {
            'id': 'task-1',
            'title': 'Server Migration',
            'subject_line': 'Infra Q3',
            'description': 'Migrate PostgreSQL',
            'status': 'in_progress',
            'priority': 'urgent',
            'client_id': 'c1',
            'client_name': 'Acme Corp',
            'workflow_id': 'w1',
            'workflow_name': 'DevOps Pipeline',
            'assigned_user_id': 'u1',
            'assigned_user_name': 'Alice Engineer',
            'assigned_user_email': 'alice@example.com',
            'due_date': '2026-10-01T12:00:00Z',
            'next_action_date': '2026-09-30T10:00:00Z',
            'attempt_count': 1,
            'max_attempts': 3,
            'created_at': '2026-09-20T08:00:00Z',
            'updated_at': '2026-09-25T09:00:00Z',
            'completed_at': null,
            'source': 'manual',
          }
        ],
      };

      final response = TaskDetailReportResponse.fromJson(jsonMap);
      expect(response.total, 1);
      expect(response.items.length, 1);
      final item = response.items.first;
      expect(item.title, 'Server Migration');
      expect(item.clientName, 'Acme Corp');
      expect(item.workflowName, 'DevOps Pipeline');
      expect(item.assignedUserName, 'Alice Engineer');
      expect(item.status, 'in_progress');
      expect(item.priority, 'urgent');
      expect(item.attemptCount, 1);
      expect(item.maxAttempts, 3);
    });

    test('ProductivityReportResponse parses daily trends with zero preservation', () {
      final jsonMap = {
        'date_from': '2026-09-01T00:00:00Z',
        'date_to': '2026-09-03T23:59:59Z',
        'total_created': 5,
        'total_completed': 4,
        'total_overdue': 1,
        'overall_completion_rate': 80.0,
        'daily_trends': [
          {
            'date': '2026-09-01',
            'created_count': 2,
            'completed_count': 1,
            'overdue_count': 0,
            'completion_rate': 50.0,
          },
          {
            'date': '2026-09-02',
            'created_count': 0,
            'completed_count': 0,
            'overdue_count': 0,
            'completion_rate': 0.0,
          },
          {
            'date': '2026-09-03',
            'created_count': 3,
            'completed_count': 3,
            'overdue_count': 1,
            'completion_rate': 100.0,
          },
        ],
      };

      final prod = ProductivityReportResponse.fromJson(jsonMap);
      expect(prod.totalCreated, 5);
      expect(prod.totalCompleted, 4);
      expect(prod.overallCompletionRate, 80.0);
      expect(prod.dailyTrends.length, 3);
      expect(prod.dailyTrends[1].date, '2026-09-02');
      expect(prod.dailyTrends[1].createdCount, 0); // zero day preserved
    });

    test('WorkloadReportResponse parses multi-dimensional categories', () {
      final jsonMap = {
        'total_open_tasks': 8,
        'total_completed_tasks': 12,
        'total_overdue_tasks': 2,
        'total_tasks': 20,
        'by_assignee': [
          {
            'id': 'u1',
            'name': 'Bob Admin',
            'email': 'bob@example.com',
            'open_tasks': 5,
            'completed_tasks': 10,
            'overdue_tasks': 1,
            'due_today_tasks': 2,
            'total_tasks': 15,
          },
          {
            'id': null,
            'name': 'Unassigned',
            'open_tasks': 3,
            'completed_tasks': 2,
            'overdue_tasks': 1,
            'due_today_tasks': 0,
            'total_tasks': 5,
          }
        ],
        'by_client': [
          {
            'id': 'c1',
            'name': 'Alpha Corp',
            'open_tasks': 4,
            'completed_tasks': 6,
            'overdue_tasks': 1,
            'due_today_tasks': 1,
            'total_tasks': 10,
          }
        ],
        'by_workflow': [
          {
            'id': 'w1',
            'name': 'Onboarding',
            'open_tasks': 4,
            'completed_tasks': 6,
            'overdue_tasks': 1,
            'due_today_tasks': 1,
            'total_tasks': 10,
          }
        ],
      };

      final wl = WorkloadReportResponse.fromJson(jsonMap);
      expect(wl.totalOpenTasks, 8);
      expect(wl.byAssignee.length, 2);
      expect(wl.byAssignee[0].name, 'Bob Admin');
      expect(wl.byAssignee[1].name, 'Unassigned');
      expect(wl.byClient.length, 1);
      expect(wl.byWorkflow.length, 1);
    });

    test('ActivityReportResponse parses action counts and entries', () {
      final jsonMap = {
        'total': 2,
        'page': 1,
        'page_size': 20,
        'action_counts': {'created': 1, 'attempt': 1},
        'items': [
          {
            'id': 'act-1',
            'task_id': 'task-1',
            'task_title': 'Audit Task',
            'action': 'created',
            'actor_id': 'user-1',
            'actor_name': 'Super User',
            'actor_email': 'super@example.com',
            'old_value': null,
            'new_value': '{"title": "Audit Task"}',
            'reason': null,
            'created_at': '2026-09-29T08:00:00Z',
          },
        ],
      };

      final act = ActivityReportResponse.fromJson(jsonMap);
      expect(act.total, 2);
      expect(act.actionCounts['created'], 1);
      expect(act.items.first.action, 'created');
      expect(act.items.first.actorName, 'Super User');
    });

    test('ReminderFollowUpReportResponse parses scheduling queues', () {
      final jsonMap = {
        'summary': {
          'reminders_due': 1,
          'reminders_sent': 2,
          'reminders_pending': 3,
          'reminders_total': 6,
          'follow_ups_overdue': 1,
          'follow_ups_today': 1,
          'follow_ups_upcoming': 2,
          'follow_ups_completed': 4,
          'follow_ups_pending': 4,
          'follow_ups_total': 8,
        },
        'reminders': [
          {
            'id': 'rem-1',
            'task_id': 't1',
            'task_title': 'Review Policy',
            'remind_at': '2026-09-29T10:00:00Z',
            'is_sent': false,
            'message': 'Check renewal',
            'created_at': '2026-09-28T10:00:00Z',
          }
        ],
        'follow_ups': [
          {
            'id': 'fu-1',
            'task_id': 't1',
            'task_title': 'Review Policy',
            'scheduled_at': '2026-09-30T10:00:00Z',
            'completed_at': null,
            'notes': 'Follow up on terms',
            'is_completed': false,
            'created_at': '2026-09-28T10:00:00Z',
          }
        ],
      };

      final sched = ReminderFollowUpReportResponse.fromJson(jsonMap);
      expect(sched.summary.remindersTotal, 6);
      expect(sched.summary.followUpsTotal, 8);
      expect(sched.reminders.length, 1);
      expect(sched.reminders.first.message, 'Check renewal');
      expect(sched.followUps.length, 1);
      expect(sched.followUps.first.isCompleted, false);
    });
  });

  group('Phase 17: ReportService REST Integration Tests', () {
    test('getTaskSummaryReport queries /reports/task-summary', () async {
      final mockHttp = MockClient((request) async {
        expect(request.url.path, '/api/v1/reports/task-summary');
        expect(request.url.queryParameters['status'], 'pending');
        expect(request.headers['Authorization'], 'Bearer mock_jwt_token');

        final payload = {
          'total_tasks': 5,
          'open_tasks': 5,
          'completed_tasks': 0,
          'cancelled_tasks': 0,
          'overdue_tasks': 1,
          'due_today_tasks': 1,
          'upcoming_tasks': 3,
          'near_max_attempts': 1,
          'max_attempts_reached': 0,
          'status_breakdown': {'pending': 5, 'in_progress': 0, 'completed': 0, 'cancelled': 0},
          'priority_breakdown': {'urgent': 1, 'high': 2, 'medium': 2, 'low': 0},
        };

        return http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json'});
      });

      final apiClient = ApiClient(httpClient: mockHttp, tokenStorage: MockTokenStorage());
      final service = ReportService(apiClient: apiClient);

      final summary = await service.getTaskSummaryReport(filters: const ReportFilters(status: 'pending'));
      expect(summary.totalTasks, 5);
      expect(summary.openTasks, 5);
      expect(summary.overdueTasks, 1);
    });

    test('getTaskDetailReport queries /reports/tasks with pagination', () async {
      final mockHttp = MockClient((request) async {
        expect(request.url.path, '/api/v1/reports/tasks');
        expect(request.url.queryParameters['page'], '2');
        expect(request.url.queryParameters['page_size'], '10');

        final payload = {
          'total': 25,
          'page': 2,
          'page_size': 10,
          'items': [],
        };
        return http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json'});
      });

      final apiClient = ApiClient(httpClient: mockHttp, tokenStorage: MockTokenStorage());
      final service = ReportService(apiClient: apiClient);

      final detail = await service.getTaskDetailReport(page: 2, pageSize: 10);
      expect(detail.total, 25);
      expect(detail.page, 2);
    });

    test('exportReport queries /reports/export and returns raw string', () async {
      final mockHttp = MockClient((request) async {
        expect(request.url.path, '/api/v1/reports/export');
        expect(request.url.queryParameters['report_type'], 'task_detail');
        expect(request.url.queryParameters['format'], 'csv');

        return http.Response(
          'Task ID,Title,Status\n1,Migration,pending',
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(httpClient: mockHttp, tokenStorage: MockTokenStorage());
      final service = ReportService(apiClient: apiClient);

      final csvData = await service.exportReport(
        reportType: ReportType.taskDetail,
        format: ExportFormat.csv,
      );

      expect(csvData, contains('Task ID,Title,Status'));
      expect(csvData, contains('Migration'));
    });
  });
}
