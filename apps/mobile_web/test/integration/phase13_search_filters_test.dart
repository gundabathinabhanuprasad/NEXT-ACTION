import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/screens/tasks/task_list_screen.dart';
import 'package:nextaction/services/client/client_service.dart';
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
  group('Phase 13 — Advanced Search, Filters & Task Discovery Tests', () {
    late List<Task> fakeTasks;
    late List<Client> fakeClients;
    late List<Workflow> fakeWorkflows;
    late List<User> fakeUsers;
    late Map<String, dynamic> lastQueryParams;

    final testNow = DateTime.now();
    final todayDue = DateTime(testNow.year, testNow.month, testNow.day, 12, 0, 0);
    final overdueDue = testNow.subtract(const Duration(days: 3));
    final upcomingDue = testNow.add(const Duration(days: 4));

    setUp(() {
      lastQueryParams = {};

      fakeClients = [
        Client(
          id: 'client-1',
          name: 'Acme Corp',
          company: 'Acme Inc',
          email: 'info@acme.com',
          phone: '123-456',
          notes: 'Important client',
          createdAt: testNow,
          updatedAt: testNow,
        ),
        Client(
          id: 'client-2',
          name: 'Stark Industries',
          company: 'Stark Enterprises',
          email: 'tony@stark.com',
          phone: '999-888',
          createdAt: testNow,
          updatedAt: testNow,
        ),
      ];

      fakeWorkflows = [
        Workflow(
          id: 'wf-1',
          name: 'Client Onboarding',
          description: 'Onboarding new enterprise accounts',
          isActive: true,
          createdAt: testNow,
          updatedAt: testNow,
        ),
        Workflow(
          id: 'wf-2',
          name: 'Security Audit',
          description: 'Quarterly compliance and SOC2 auditing',
          isActive: true,
          createdAt: testNow,
          updatedAt: testNow,
        ),
      ];

      fakeUsers = [
        User(
          id: 'user-me',
          name: 'Bhanu Admin',
          email: 'bhanu@nextaction.local',
          isActive: true,
          createdAt: testNow,
          updatedAt: testNow,
        ),
        User(
          id: 'user-alice',
          name: 'Alice Developer',
          email: 'alice@nextaction.local',
          isActive: true,
          createdAt: testNow,
          updatedAt: testNow,
        ),
      ];

      fakeTasks = [
        Task(
          id: 'task-1',
          title: 'Review Acme Security Architecture',
          description: 'Deep dive into authentication and VPC configuration',
          subjectLine: 'RE: Security architecture proposal',
          clientId: 'client-1',
          workflowId: 'wf-2',
          assignedUserId: 'user-me',
          status: 'in_progress',
          priority: 'urgent',
          dueDate: overdueDue,
          nextActionDate: todayDue,
          attemptCount: 1,
          maxAttempts: 2,
          createdAt: testNow.subtract(const Duration(days: 5)),
          updatedAt: testNow.subtract(const Duration(days: 1)),
        ),
        Task(
          id: 'task-2',
          title: 'Prepare Stark Contract Onboarding',
          description: 'Draft MSA and schedule discovery kickoff',
          subjectLine: 'Contract terms v2',
          clientId: 'client-2',
          workflowId: 'wf-1',
          assignedUserId: 'user-alice',
          status: 'pending',
          priority: 'high',
          dueDate: todayDue,
          nextActionDate: null,
          attemptCount: 0,
          maxAttempts: 3,
          createdAt: testNow.subtract(const Duration(days: 2)),
          updatedAt: testNow.subtract(const Duration(days: 2)),
        ),
        Task(
          id: 'task-3',
          title: 'Unassigned Pipeline Migration',
          description: 'Migrate legacy workflow scripts',
          clientId: null,
          workflowId: 'wf-1',
          assignedUserId: null,
          status: 'pending',
          priority: 'low',
          dueDate: upcomingDue,
          nextActionDate: upcomingDue,
          attemptCount: 2,
          maxAttempts: 2,
          createdAt: testNow.subtract(const Duration(days: 1)),
          updatedAt: testNow.subtract(const Duration(days: 1)),
        ),
      ];
    });

    http.Client createMockHttpClient() {
      return MockClient((request) async {
        final uri = request.url;
        if (uri.path == '/api/v1/tasks') {
          lastQueryParams = Map<String, dynamic>.from(uri.queryParameters);

          var filtered = List<Task>.from(fakeTasks);

          if (uri.queryParameters.containsKey('search')) {
            final q = uri.queryParameters['search']!.toLowerCase();
            filtered = filtered.where((t) =>
                t.title.toLowerCase().contains(q) ||
                (t.description?.toLowerCase().contains(q) ?? false) ||
                (t.subjectLine?.toLowerCase().contains(q) ?? false)).toList();
          }

          if (uri.queryParameters.containsKey('status')) {
            filtered = filtered.where((t) => t.status == uri.queryParameters['status']).toList();
          }

          if (uri.queryParameters.containsKey('priority')) {
            filtered = filtered.where((t) => t.priority == uri.queryParameters['priority']).toList();
          }

          if (uri.queryParameters.containsKey('client_id')) {
            filtered = filtered.where((t) => t.clientId == uri.queryParameters['client_id']).toList();
          }

          if (uri.queryParameters.containsKey('workflow_id')) {
            filtered = filtered.where((t) => t.workflowId == uri.queryParameters['workflow_id']).toList();
          }

          if (uri.queryParameters.containsKey('assigned_user_id')) {
            filtered = filtered.where((t) => t.assignedUserId == uri.queryParameters['assigned_user_id']).toList();
          }

          if (uri.queryParameters['unassigned'] == 'true') {
            filtered = filtered.where((t) => t.assignedUserId == null).toList();
          }

          if (uri.queryParameters['overdue'] == 'true') {
            filtered = filtered.where((t) => t.isOverdue).toList();
          }

          if (uri.queryParameters['due_today'] == 'true') {
            filtered = filtered.where((t) => t.isDueToday).toList();
          }

          if (uri.queryParameters['no_next_action'] == 'true') {
            filtered = filtered.where((t) => t.nextActionDate == null).toList();
          }

          if (uri.queryParameters['near_max_attempts'] == 'true') {
            filtered = filtered.where((t) => t.isNearMaxAttempts).toList();
          }

          return http.Response(
            jsonEncode({
              'items': filtered.map((t) => t.toJson()).toList(),
              'total': filtered.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
          );
        }

        if (uri.path == '/api/v1/clients') {
          return http.Response(
            jsonEncode({
              'items': fakeClients.map((c) => c.toJson()).toList(),
              'total': fakeClients.length,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        if (uri.path == '/api/v1/workflows') {
          return http.Response(
            jsonEncode({
              'items': fakeWorkflows.map((w) => w.toJson()).toList(),
              'total': fakeWorkflows.length,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        if (uri.path == '/api/v1/users') {
          return http.Response(
            jsonEncode({
              'items': fakeUsers.map((u) => u.toJson()).toList(),
              'total': fakeUsers.length,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });
    }

    Widget createTestWidget({
      String? initialSearch,
      String? initialStatus,
      String? initialPriority,
      String? initialClientId,
      String? initialWorkflowId,
      String? initialAssignedUserId,
      bool? initialOverdue,
      bool? initialDueToday,
      TaskSmartFilter? initialSmartFilter,
    }) {
      final mockHttp = createMockHttpClient();
      final apiClient = ApiClient(httpClient: mockHttp, tokenStorage: InMemoryTokenStorage('test-jwt-token'));
      final taskService = TaskService(apiClient: apiClient);
      final clientService = ClientService(apiClient: apiClient);
      final workflowService = WorkflowService(apiClient: apiClient);
      final userService = UserService(apiClient: apiClient);

      return MaterialApp(
        home: TaskListScreen(
          taskService: taskService,
          clientService: clientService,
          workflowService: workflowService,
          userService: userService,
          currentUserId: 'user-me',
          initialSearch: initialSearch,
          initialStatus: initialStatus,
          initialPriority: initialPriority,
          initialClientId: initialClientId,
          initialWorkflowId: initialWorkflowId,
          initialAssignedUserId: initialAssignedUserId,
          initialOverdue: initialOverdue,
          initialDueToday: initialDueToday,
          initialSmartFilter: initialSmartFilter,
        ),
      );
    }

    testWidgets('1. Search bar debounces input and updates query parameter', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify all 3 tasks initial render
      expect(find.text('Review Acme Security Architecture'), findsOneWidget);
      expect(find.text('Prepare Stark Contract Onboarding'), findsOneWidget);
      expect(find.text('Unassigned Pipeline Migration'), findsOneWidget);

      // Type in search bar
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Security');
      // Wait for 300ms debounce
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(lastQueryParams['search'], equals('Security'));
      expect(find.text('Review Acme Security Architecture'), findsOneWidget);
      expect(find.text('Prepare Stark Contract Onboarding'), findsNothing);

      // Clear search with TextField clear button
      final clearButton = find.descendant(
        of: find.byType(TextField),
        matching: find.byIcon(Icons.clear),
      );
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(lastQueryParams['search'], isNull);
      expect(find.text('Prepare Stark Contract Onboarding'), findsOneWidget);
    });

    testWidgets('2. Quick presets filter tasks by Assigned to Me, Unassigned, Overdue, Near Max Attempts', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap 'Assigned to Me' preset
      await tester.tap(find.text('Assigned to Me'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['assigned_user_id'], equals('user-me'));
      expect(find.text('Review Acme Security Architecture'), findsOneWidget);
      expect(find.text('Prepare Stark Contract Onboarding'), findsNothing);

      // Tap 'Unassigned' preset
      await tester.tap(find.text('Unassigned'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['unassigned'], equals('true'));
      expect(find.text('Unassigned Pipeline Migration'), findsOneWidget);
      expect(find.text('Review Acme Security Architecture'), findsNothing);

      // Tap 'Overdue' preset
      await tester.tap(find.text('Overdue'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['overdue'], equals('true'));
      expect(find.text('Review Acme Security Architecture'), findsOneWidget);

      // Tap 'Near Max Attempts' preset
      await tester.tap(find.text('Near Max Attempts'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['near_max_attempts'], equals('true'));
      expect(find.text('Unassigned Pipeline Migration'), findsOneWidget);

      // Tap 'All' preset to reset
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['near_max_attempts'], isNull);
      expect(find.text('Review Acme Security Architecture'), findsOneWidget);
      expect(find.text('Prepare Stark Contract Onboarding'), findsOneWidget);
    });

    testWidgets('3. Active filter chips display with clear and Clear All button', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(initialStatus: 'in_progress', initialPriority: 'urgent'));
      await tester.pumpAndSettle();

      // Verify active filter chips are rendered
      expect(find.text('Status: IN_PROGRESS'), findsOneWidget);
      expect(find.text('Priority: URGENT'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);

      // Tap Clear All
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['status'], isNull);
      expect(lastQueryParams['priority'], isNull);
      expect(find.text('Clear All'), findsNothing);
    });

    testWidgets('4. Filter Bottom Sheet allows configuring multiple combined filters', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap Filter button
      final filterBtn = find.byIcon(Icons.tune);
      expect(filterBtn, findsOneWidget);
      await tester.tap(filterBtn);
      await tester.pumpAndSettle();

      // Check bottom sheet header
      expect(find.text('Advanced Task Filters'), findsOneWidget);

      // Select Status: IN PROGRESS
      await tester.tap(find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text('IN PROGRESS'),
      ));
      await tester.pumpAndSettle();

      // Select Priority: URGENT
      await tester.tap(find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text('URGENT'),
      ));
      await tester.pumpAndSettle();

      // Tap Apply Filters
      await tester.ensureVisible(find.text('Apply Filters'));
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(lastQueryParams['status'], equals('in_progress'));
      expect(lastQueryParams['priority'], equals('urgent'));
      expect(find.text('Review Acme Security Architecture'), findsOneWidget);
      expect(find.text('Prepare Stark Contract Onboarding'), findsNothing);
    });

    testWidgets('5. Task discovery summary bar shows accurate counts and pagination state', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Summary text
      expect(find.textContaining('Showing 1–3 of 3 tasks'), findsOneWidget);
    });
  });
}
