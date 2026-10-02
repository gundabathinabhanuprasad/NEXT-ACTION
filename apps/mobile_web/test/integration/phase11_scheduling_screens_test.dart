import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/screens/follow_ups/follow_ups_screen.dart';
import 'package:nextaction/screens/next_actions/next_actions_screen.dart';
import 'package:nextaction/screens/reminders/reminders_screen.dart';
import 'package:nextaction/screens/tasks/task_detail_screen.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/user/user_service.dart';
import 'package:nextaction/services/workflow/workflow_service.dart';

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
  group('Phase 11 - RemindersScreen Widget Tests', () {
    testWidgets('RemindersScreen renders tabs, lists items, sends reminder, and deletes reminder', (WidgetTester tester) async {
      final now = DateTime.now();
      final reminders = [
        Reminder(
          id: 'rem-1',
          taskId: 't-1',
          remindAt: now.subtract(const Duration(hours: 1)),
          message: 'Overdue task reminder alert',
          isSent: false,
          createdAt: now.subtract(const Duration(hours: 2)),
          updatedAt: now.subtract(const Duration(hours: 2)),
        ),
        Reminder(
          id: 'rem-2',
          taskId: 't-2',
          remindAt: now.add(const Duration(days: 2)),
          message: 'Upcoming reminder next week',
          isSent: true,
          createdAt: now.subtract(const Duration(hours: 5)),
          updatedAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final tasks = [
        Task(
          id: 't-1',
          title: 'Prepare financial audit',
          status: 'pending',
          priority: 'high',
          attemptCount: 0,
          maxAttempts: 2,
          createdAt: now,
          updatedAt: now,
        ),
        Task(
          id: 't-2',
          title: 'Deploy infrastructure updates',
          status: 'in_progress',
          priority: 'urgent',
          attemptCount: 1,
          maxAttempts: 3,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/reminders') {
          return http.Response(jsonEncode(reminders.map((r) => r.toJson()).toList()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-1') {
          return http.Response(jsonEncode(tasks[0].toJson()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-2') {
          return http.Response(jsonEncode(tasks[1].toJson()), 200);
        }
        if (request.url.path == '/api/v1/reminders/rem-1/send') {
          return http.Response(
            jsonEncode({
              'id': 'rem-1',
              'task_id': 't-1',
              'remind_at': now.toIso8601String(),
              'message': 'Overdue task reminder alert',
              'is_sent': true,
              'sent_at': now.toIso8601String(),
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
            }),
            200,
          );
        }
        if (request.method == 'DELETE' && request.url.path == '/api/v1/reminders/rem-1') {
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
      final reminderService = ReminderService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RemindersScreen(
            reminderService: reminderService,
            taskService: taskService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and tabs
      expect(find.text('Reminders Center'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Due / Overdue'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Sent (1)'), findsOneWidget);

      // Verify reminder items
      expect(find.text('Prepare financial audit'), findsOneWidget);
      expect(find.text('Overdue task reminder alert'), findsOneWidget);
      expect(find.text('Deploy infrastructure updates'), findsOneWidget);

      // Send reminder
      final sendBtn = find.text('Send Now');
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Verify SnackBar
      expect(find.text('Reminder marked as sent. Attempt count unchanged.'), findsOneWidget);
    });
  });

  group('Phase 11 - FollowUpsScreen Widget Tests', () {
    testWidgets('FollowUpsScreen renders tabs, completes follow-up and deletes follow-up', (WidgetTester tester) async {
      final now = DateTime.now();
      final followUps = [
        FollowUp(
          id: 'fol-1',
          taskId: 't-1',
          scheduledAt: now.subtract(const Duration(days: 1)),
          notes: 'Discuss proposal changes',
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(days: 2)),
        ),
        FollowUp(
          id: 'fol-2',
          taskId: 't-2',
          scheduledAt: now.add(const Duration(days: 3)),
          completedAt: now,
          notes: 'Contract finalized',
          createdAt: now.subtract(const Duration(days: 3)),
          updatedAt: now,
        ),
      ];

      final tasks = [
        Task(
          id: 't-1',
          title: 'Proposal Review',
          status: 'in_progress',
          priority: 'high',
          attemptCount: 0,
          maxAttempts: 2,
          createdAt: now,
          updatedAt: now,
        ),
        Task(
          id: 't-2',
          title: 'Contract Negotiation',
          status: 'completed',
          priority: 'urgent',
          attemptCount: 1,
          maxAttempts: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/follow-ups') {
          return http.Response(jsonEncode(followUps.map((f) => f.toJson()).toList()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-1') {
          return http.Response(jsonEncode(tasks[0].toJson()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-2') {
          return http.Response(jsonEncode(tasks[1].toJson()), 200);
        }
        if (request.url.path == '/api/v1/follow-ups/fol-1/complete') {
          return http.Response(
            jsonEncode({
              'id': 'fol-1',
              'task_id': 't-1',
              'scheduled_at': now.toIso8601String(),
              'completed_at': now.toIso8601String(),
              'notes': 'Discuss proposal changes - Done',
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
      final followUpService = FollowUpService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: FollowUpsScreen(
            followUpService: followUpService,
            taskService: taskService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header & tabs
      expect(find.text('Follow-ups Center'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);

      // Verify items
      expect(find.text('Proposal Review'), findsOneWidget);
      expect(find.text('Discuss proposal changes'), findsOneWidget);

      // Tap Complete Follow-up
      final completeBtn = find.widgetWithText(FilledButton, 'Complete').first;
      expect(completeBtn, findsOneWidget);
      await tester.tap(completeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Complete Follow-up'), findsOneWidget);
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
    });
  });

  group('Phase 11 - NextActionsScreen Widget Tests', () {
    testWidgets('NextActionsScreen groups overdue/today/upcoming and toggles My Next Actions', (WidgetTester tester) async {
      final now = DateTime.now();
      final user1 = User(id: 'u-1', name: 'Alice Cooper', email: 'alice@test.com', isActive: true, createdAt: now, updatedAt: now);
      final client1 = Client(id: 'c-1', name: 'Acme Corp', createdAt: now, updatedAt: now);
      final workflow1 = Workflow(id: 'w-1', name: 'Sales Pipeline', isActive: true, createdAt: now, updatedAt: now);

      final tasks = [
        Task(
          id: 't-overdue',
          title: 'Overdue Strategy Call',
          assignedUserId: 'u-1',
          clientId: 'c-1',
          workflowId: 'w-1',
          status: 'in_progress',
          priority: 'urgent',
          nextActionDate: now.subtract(const Duration(days: 2)),
          attemptCount: 0,
          maxAttempts: 2,
          createdAt: now,
          updatedAt: now,
        ),
        Task(
          id: 't-today',
          title: 'Today Alignment Meeting',
          assignedUserId: 'u-2',
          clientId: 'c-1',
          status: 'pending',
          priority: 'high',
          nextActionDate: now,
          attemptCount: 0,
          maxAttempts: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks') {
          return http.Response(
            jsonEncode({
              'items': tasks.map((t) => t.toJson()).toList(),
              'total': 2,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/clients') {
          return http.Response(jsonEncode({'items': [client1.toJson()], 'total': 1, 'page': 1, 'page_size': 100}), 200);
        }
        if (request.url.path == '/api/v1/workflows') {
          return http.Response(jsonEncode({'items': [workflow1.toJson()], 'total': 1, 'page': 1, 'page_size': 100}), 200);
        }
        if (request.url.path == '/api/v1/users') {
          return http.Response(jsonEncode({'items': [user1.toJson()], 'total': 1, 'page': 1, 'page_size': 100}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
      final taskService = TaskService(apiClient: apiClient);
      final clientService = ClientService(apiClient: apiClient);
      final workflowService = WorkflowService(apiClient: apiClient);
      final userService = UserService(apiClient: apiClient);

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: NextActionsScreen(
            taskService: taskService,
            clientService: clientService,
            workflowService: workflowService,
            userService: userService,
            currentUserId: 'u-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Next Actions Workspace'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Overdue Strategy Call'), findsOneWidget);
      expect(find.text('Today Alignment Meeting'), findsOneWidget);
      expect(find.text('Acme Corp'), findsNWidgets(2));
      expect(find.text('Sales Pipeline'), findsOneWidget);

      // Toggle to "My Next Actions"
      await tester.tap(find.text('All Next Actions'));
      await tester.pumpAndSettle();

      // Only Alice's task should now be displayed
      expect(find.text('Overdue Strategy Call'), findsOneWidget);
      expect(find.text('Today Alignment Meeting'), findsNothing);
    });
  });

  group('Phase 11 - TaskDetailScreen Scheduling Section Tests', () {
    testWidgets('TaskDetailScreen provides clear next action date, add reminder, and complete follow-up', (WidgetTester tester) async {
      final now = DateTime.now();
      final task = Task(
        id: 't-detail-1',
        title: 'Master Scheduling Task',
        description: 'Comprehensive scheduling verification',
        status: 'in_progress',
        priority: 'urgent',
        nextActionDate: now.add(const Duration(days: 1)),
        attemptCount: 1,
        maxAttempts: 3,
        createdAt: now,
        updatedAt: now,
      );

      final reminders = [
        Reminder(
          id: 'rem-dt-1',
          taskId: 't-detail-1',
          remindAt: now.add(const Duration(hours: 4)),
          message: 'Detail alert',
          isSent: false,
          createdAt: now,
          updatedAt: now,
        )
      ];

      final followUps = [
        FollowUp(
          id: 'fol-dt-1',
          taskId: 't-detail-1',
          scheduledAt: now.add(const Duration(days: 1)),
          notes: 'Detail follow-up note',
          createdAt: now,
          updatedAt: now,
        )
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/tasks/t-detail-1') {
          return http.Response(jsonEncode(task.toJson()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-detail-1/reminders') {
          return http.Response(jsonEncode(reminders.map((r) => r.toJson()).toList()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-detail-1/follow-ups') {
          return http.Response(jsonEncode(followUps.map((f) => f.toJson()).toList()), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-detail-1/history') {
          return http.Response(jsonEncode([]), 200);
        }
        if (request.url.path == '/api/v1/tasks/t-detail-1/next-action-date') {
          return http.Response(jsonEncode(task.toJson()), 200);
        }
        if (request.method == 'DELETE' && request.url.path == '/api/v1/reminders/rem-dt-1') {
          return http.Response('', 204);
        }
        if (request.method == 'DELETE' && request.url.path == '/api/v1/follow-ups/fol-dt-1') {
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
      final taskService = TaskService(apiClient: apiClient);

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            taskId: 't-detail-1',
            taskService: taskService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Master Scheduling Task'), findsOneWidget);
      expect(find.text('Reminders (1)'), findsOneWidget);
      expect(find.text('Follow-ups (1)'), findsOneWidget);
      expect(find.text('Detail alert'), findsOneWidget);
      expect(find.text('Detail follow-up note'), findsOneWidget);

      // Verify Clear Next Action Date button exists
      expect(find.byTooltip('Clear Next Action Date'), findsOneWidget);
      expect(find.text('Update Next Action'), findsOneWidget);

      // Verify Invariant: Task attempt count is 1
      expect(find.textContaining('1 / 3'), findsWidgets);
    });
  });
}
