import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/screens/reports/reports_screen.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/report/report_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/user/user_service.dart';
import 'package:nextaction/services/workflow/workflow_service.dart';

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
  late MockClient mockHttp;
  late ApiClient apiClient;
  late ReportService reportService;
  late TaskService taskService;
  late ClientService clientService;
  late WorkflowService workflowService;
  late UserService userService;

  setUp(() {
    mockHttp = MockClient((request) async {
      final path = request.url.path;

      if (path.contains('/reports/task-summary')) {
        return http.Response(
          jsonEncode({
            'total_tasks': 12,
            'open_tasks': 7,
            'completed_tasks': 4,
            'cancelled_tasks': 1,
            'overdue_tasks': 2,
            'due_today_tasks': 3,
            'upcoming_tasks': 2,
            'near_max_attempts': 2,
            'max_attempts_reached': 1,
            'status_breakdown': {'pending': 5, 'in_progress': 2, 'completed': 4, 'cancelled': 1},
            'priority_breakdown': {'urgent': 3, 'high': 4, 'medium': 3, 'low': 2},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/reports/tasks') && !path.contains('/export')) {
        return http.Response(
          jsonEncode({
            'total': 1,
            'page': 1,
            'page_size': 20,
            'items': [
              {
                'id': 'task-101',
                'title': 'High Priority Architecture Review',
                'subject_line': 'Arch Q4',
                'status': 'in_progress',
                'priority': 'urgent',
                'client_name': 'Alpha Corp',
                'workflow_name': 'Core Workflow',
                'assigned_user_name': 'Alice Engineer',
                'attempt_count': 1,
                'max_attempts': 2,
                'created_at': '2026-09-29T08:00:00Z',
                'updated_at': '2026-09-29T08:30:00Z',
                'due_date': '2026-10-02T12:00:00Z',
                'source': 'manual',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/reports/productivity')) {
        return http.Response(
          jsonEncode({
            'date_from': '2026-09-01T00:00:00Z',
            'date_to': '2026-09-02T23:59:59Z',
            'total_created': 10,
            'total_completed': 8,
            'total_overdue': 2,
            'overall_completion_rate': 80.0,
            'daily_trends': [
              {
                'date': '2026-09-01',
                'created_count': 5,
                'completed_count': 4,
                'overdue_count': 1,
                'completion_rate': 80.0,
              },
              {
                'date': '2026-09-02',
                'created_count': 5,
                'completed_count': 4,
                'overdue_count': 1,
                'completion_rate': 80.0,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/reports/workload') && !path.contains('/export')) {
        return http.Response(
          jsonEncode({
            'total_open_tasks': 5,
            'total_completed_tasks': 10,
            'total_overdue_tasks': 1,
            'total_tasks': 15,
            'by_assignee': [
              {
                'id': 'u1',
                'name': 'Bob Assignee',
                'open_tasks': 5,
                'completed_tasks': 10,
                'overdue_tasks': 1,
                'due_today_tasks': 2,
                'total_tasks': 15,
              }
            ],
            'by_client': [
              {
                'id': 'c1',
                'name': 'Alpha Client',
                'open_tasks': 5,
                'completed_tasks': 10,
                'overdue_tasks': 1,
                'due_today_tasks': 2,
                'total_tasks': 15,
              }
            ],
            'by_workflow': [
              {
                'id': 'w1',
                'name': 'Alpha Workflow',
                'open_tasks': 5,
                'completed_tasks': 10,
                'overdue_tasks': 1,
                'due_today_tasks': 2,
                'total_tasks': 15,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/reports/activity') && !path.contains('/export')) {
        return http.Response(
          jsonEncode({
            'total': 1,
            'page': 1,
            'page_size': 20,
            'action_counts': {'created': 1},
            'items': [
              {
                'id': 'act-1',
                'task_id': 'task-101',
                'task_title': 'High Priority Architecture Review',
                'action': 'created',
                'actor_name': 'Admin User',
                'created_at': '2026-09-29T08:00:00Z',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/reports/reminders-followups')) {
        return http.Response(
          jsonEncode({
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
                'id': 'r1',
                'task_id': 'task-101',
                'task_title': 'High Priority Architecture Review',
                'remind_at': '2026-09-29T10:00:00Z',
                'is_sent': false,
                'message': 'Review reminder',
                'created_at': '2026-09-28T10:00:00Z',
              }
            ],
            'follow_ups': [
              {
                'id': 'f1',
                'task_id': 'task-101',
                'task_title': 'High Priority Architecture Review',
                'scheduled_at': '2026-09-30T10:00:00Z',
                'is_completed': false,
                'notes': 'Follow up on architecture',
                'created_at': '2026-09-28T10:00:00Z',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/reports/export')) {
        return http.Response(
          'Task ID,Title,Status\ntask-101,High Priority Architecture Review,in_progress',
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      } else if (path.contains('/clients')) {
        return http.Response(
          jsonEncode({'items': [{'id': 'c1', 'name': 'Alpha Client', 'is_active': true, 'created_at': '2026-09-29T00:00:00Z'}], 'total': 1, 'page': 1, 'page_size': 100}),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/workflows')) {
        return http.Response(
          jsonEncode({'items': [{'id': 'w1', 'name': 'Alpha Workflow', 'is_active': true, 'created_at': '2026-09-29T00:00:00Z'}], 'total': 1, 'page': 1, 'page_size': 100}),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (path.contains('/users')) {
        return http.Response(
          jsonEncode({'items': [{'id': 'u1', 'name': 'Bob Assignee', 'email': 'bob@example.com', 'is_active': true, 'created_at': '2026-09-29T00:00:00Z'}], 'total': 1, 'page': 1, 'page_size': 100}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('{"detail": "Not found"}', 404);
    });

    apiClient = ApiClient(httpClient: mockHttp, tokenStorage: MockTokenStorage());
    reportService = ReportService(apiClient: apiClient);
    taskService = TaskService(apiClient: apiClient);
    clientService = ClientService(apiClient: apiClient);
    workflowService = WorkflowService(apiClient: apiClient);
    userService = UserService(apiClient: apiClient);
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ReportsScreen(
        reportService: reportService,
        taskService: taskService,
        clientService: clientService,
        workflowService: workflowService,
        userService: userService,
      ),
    );
  }

  testWidgets('ReportsScreen renders Header, Report Type Chips, and Task Summary KPIs', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Verify Title & AppBar actions
    expect(find.text('Reports & Insights'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.code_outlined), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    // Verify Report Type ChoiceChips
    expect(find.text('Task Summary Report'), findsOneWidget);
    expect(find.text('Task Detail Report'), findsOneWidget);
    expect(find.text('Productivity Report'), findsOneWidget);
    expect(find.text('Workload Report'), findsOneWidget);
    expect(find.text('Activity Audit Report'), findsOneWidget);
    expect(find.text('Scheduling Queues Report'), findsOneWidget);

    // Verify Task Summary KPIs
    expect(find.text('Total Tasks'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Open Workload'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('4'), findsWidgets);
    expect(find.text('Overdue Tasks'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('ReportsScreen switches to Task Detail Report and renders data table', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Tap Task Detail Report chip
    await tester.ensureVisible(find.text('Task Detail Report'));
    await tester.tap(find.text('Task Detail Report'));
    await tester.pumpAndSettle();

    // Verify task row details
    expect(find.text('High Priority Architecture Review'), findsOneWidget);
    expect(find.text('Alpha Corp'), findsOneWidget);
    expect(find.text('Core Workflow'), findsOneWidget);
    expect(find.text('Alice Engineer'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('ReportsScreen switches to Productivity Report and displays daily trends', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Tap Productivity Report chip
    await tester.ensureVisible(find.text('Productivity Report'));
    await tester.tap(find.text('Productivity Report'));
    await tester.pumpAndSettle();

    expect(find.text('Created in Range'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Completed in Range'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('80.0%'), findsWidgets);
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.text('2026-09-02'), findsOneWidget);
  });

  testWidgets('ReportsScreen switches to Workload Report and displays category tables', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Tap Workload Report chip
    await tester.ensureVisible(find.text('Workload Report'));
    await tester.tap(find.text('Workload Report'));
    await tester.pumpAndSettle();

    expect(find.text('Workload by Assignee'), findsOneWidget);
    expect(find.text('Workload by Client'), findsOneWidget);
    expect(find.text('Workload by Workflow'), findsOneWidget);
    expect(find.text('Bob Assignee'), findsOneWidget);
  });

  testWidgets('ReportsScreen triggers CSV export dialog and displays preview snippet', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Tap Export CSV icon
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    // Verify Export Dialog
    expect(find.text('Export CSV (Spreadsheet) Generated'), findsOneWidget);
    expect(find.textContaining('Task ID,Title,Status'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });
}
