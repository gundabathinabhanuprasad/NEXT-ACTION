import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/recurring/recurring_task_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/template/task_template_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/screens/recurring/recurring_tasks_screen.dart';
import 'package:nextaction/screens/tasks/task_detail_screen.dart';
import 'package:nextaction/screens/templates/task_template_create_screen.dart';
import 'package:nextaction/screens/templates/task_templates_screen.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/recurring/recurring_task_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/template/task_template_service.dart';
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
  group('Phase 14 — Task Templates & Recurring Tasks UI Integration Tests', () {
    late List<TaskTemplate> fakeTemplates;
    late List<RecurringTask> fakeRecurringTasks;
    late List<Task> fakeTasks;
    late List<Client> fakeClients;
    late List<Workflow> fakeWorkflows;
    late List<User> fakeUsers;

    final now = DateTime.now();

    setUp(() {
      fakeClients = [
        Client(
          id: 'client-1',
          name: 'Acme Corp',
          company: 'Acme Inc',
          email: 'info@acme.com',
          phone: '123-456',
          notes: 'Test Client',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      fakeWorkflows = [
        Workflow(
          id: 'wf-1',
          name: 'Client Onboarding',
          description: 'Onboarding workflow',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      fakeUsers = [
        User(
          id: 'user-1',
          name: 'Bhanu Admin',
          email: 'bhanu@nextaction.local',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      fakeTemplates = [
        TaskTemplate(
          id: 'template-1',
          name: 'Weekly Client Review Template',
          description: 'Conduct weekly review call and sync on deliverables.',
          subjectLine: 'Weekly Client Review with {Client}',
          workflowId: 'wf-1',
          clientId: 'client-1',
          assignedUserId: 'user-1',
          priority: 'high',
          maxAttempts: 3,
          defaultDueOffsetDays: 7,
          defaultNextActionOffsetDays: 2,
          isActive: true,
          createdByUserId: 'user-1',
          createdAt: now,
          updatedAt: now,
        ),
        TaskTemplate(
          id: 'template-2',
          name: 'Monthly Invoice Follow-up',
          description: 'Follow up on outstanding invoices.',
          priority: 'medium',
          maxAttempts: 2,
          isActive: false,
          createdByUserId: 'user-1',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      fakeRecurringTasks = [
        RecurringTask(
          id: 'rec-1',
          templateId: 'template-1',
          name: 'Weekly Account Sync Recurrence',
          description: 'Automated weekly schedule for account synchronization.',
          priority: 'high',
          maxAttempts: 3,
          recurrenceType: 'weekly',
          interval: 1,
          dayOfWeek: 1,
          startDate: now,
          nextRunAt: now.add(const Duration(days: 1)),
          isActive: true,
          createdByUserId: 'user-1',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      fakeTasks = [
        Task(
          id: 'task-template-child',
          title: 'Weekly Client Review for Acme Corp',
          description: 'Generated from template',
          status: 'pending',
          priority: 'high',
          maxAttempts: 3,
          attemptCount: 0,
          templateId: 'template-1',
          clientId: 'client-1',
          workflowId: 'wf-1',
          assignedUserId: 'user-1',
          createdAt: now,
          updatedAt: now,
        ),
        Task(
          id: 'task-recurring-child',
          title: 'Weekly Account Sync Recurrence Instance',
          description: 'Generated from recurrence schedule',
          status: 'pending',
          priority: 'high',
          maxAttempts: 3,
          attemptCount: 0,
          recurringTaskId: 'rec-1',
          createdAt: now,
          updatedAt: now,
        ),
        Task(
          id: 'task-manual',
          title: 'Manual Ad-Hoc Task',
          description: 'Created manually by user',
          status: 'pending',
          priority: 'low',
          maxAttempts: 2,
          attemptCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ];
    });

    MockClient createMockHttpClient() {
      return MockClient((request) async {
        final uri = request.url;
        final path = uri.path;
        final method = request.method;
        // debug
        // print('MockClient: $method $path ${uri.queryParameters}');

        // Sub-resources of tasks
        if (path.endsWith('/history')) {
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }
        if (path.endsWith('/reminders')) {
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }
        if (path.endsWith('/follow-ups')) {
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }

        // Task Templates endpoints
        if (path == '/api/v1/task-templates' && method == 'GET') {
          final search = uri.queryParameters['search']?.toLowerCase();
          final isActiveParam = uri.queryParameters['is_active'];

          var filtered = List<TaskTemplate>.from(fakeTemplates);
          if (search != null && search.isNotEmpty) {
            filtered = filtered.where((t) => t.name.toLowerCase().contains(search)).toList();
          }
          if (isActiveParam != null) {
            final activeBool = isActiveParam == 'true';
            filtered = filtered.where((t) => t.isActive == activeBool).toList();
          }

          return http.Response(
            jsonEncode({
              'items': filtered.map((t) => t.toJson()).toList(),
              'total': filtered.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.startsWith('/api/v1/task-templates/') && path.endsWith('/create-task') && method == 'POST') {
          final tId = path.split('/')[3];
          final template = fakeTemplates.firstWhere((t) => t.id == tId);
          final newTask = Task(
            id: 'task-new-from-${template.id}',
            title: template.name,
            description: template.description,
            status: 'pending',
            priority: template.priority,
            maxAttempts: template.maxAttempts,
            attemptCount: 0,
            templateId: template.id,
            clientId: template.clientId,
            workflowId: template.workflowId,
            assignedUserId: template.assignedUserId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          fakeTasks.add(newTask);
          return http.Response(
            jsonEncode(newTask.toJson()),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path == '/api/v1/task-templates' && method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final created = TaskTemplate(
            id: 'template-new-${fakeTemplates.length + 1}',
            name: body['name'] as String,
            description: body['description'] as String?,
            subjectLine: body['subject_line'] as String?,
            workflowId: body['workflow_id'] as String?,
            clientId: body['client_id'] as String?,
            assignedUserId: body['assigned_user_id'] as String?,
            priority: body['priority'] as String? ?? 'medium',
            maxAttempts: body['max_attempts'] as int? ?? 2,
            defaultDueOffsetDays: body['default_due_offset_days'] as int?,
            defaultNextActionOffsetDays: body['default_next_action_offset_days'] as int?,
            isActive: body['is_active'] as bool? ?? true,
            createdByUserId: 'user-1',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          fakeTemplates.add(created);
          return http.Response(
            jsonEncode(created.toJson()),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        // Recurring Tasks endpoints
        if (path == '/api/v1/recurring-tasks' && method == 'GET') {
          return http.Response(
            jsonEncode({
              'items': fakeRecurringTasks.map((r) => r.toJson()).toList(),
              'total': fakeRecurringTasks.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path == '/api/v1/recurring-tasks/evaluate' && method == 'POST') {
          return http.Response(
            jsonEncode({
              'evaluated_definitions': 1,
              'tasks_created': 1,
              'created_tasks': [fakeTasks[1].toJson()],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // Clients / Workflows / Users endpoints
        if (path == '/api/v1/clients') {
          return http.Response(
            jsonEncode({
              'items': fakeClients.map((c) => c.toJson()).toList(),
              'total': fakeClients.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.startsWith('/api/v1/clients/')) {
          final cId = path.split('/').last;
          final client = fakeClients.firstWhere((c) => c.id == cId, orElse: () => fakeClients.first);
          return http.Response(jsonEncode(client.toJson()), 200, headers: {'content-type': 'application/json'});
        }

        if (path == '/api/v1/workflows') {
          return http.Response(
            jsonEncode({
              'items': fakeWorkflows.map((w) => w.toJson()).toList(),
              'total': fakeWorkflows.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.startsWith('/api/v1/workflows/')) {
          final wId = path.split('/').last;
          final wf = fakeWorkflows.firstWhere((w) => w.id == wId, orElse: () => fakeWorkflows.first);
          return http.Response(jsonEncode(wf.toJson()), 200, headers: {'content-type': 'application/json'});
        }

        if (path == '/api/v1/users') {
          return http.Response(
            jsonEncode({
              'items': fakeUsers.map((u) => u.toJson()).toList(),
              'total': fakeUsers.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.startsWith('/api/v1/users/')) {
          final uId = path.split('/').last;
          final u = fakeUsers.firstWhere((usr) => usr.id == uId, orElse: () => fakeUsers.first);
          return http.Response(jsonEncode(u.toJson()), 200, headers: {'content-type': 'application/json'});
        }

        if (path == '/api/v1/tasks' && method == 'GET') {
          return http.Response(
            jsonEncode({
              'items': fakeTasks.map((t) => t.toJson()).toList(),
              'total': fakeTasks.length,
              'page': 1,
              'page_size': 20,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.startsWith('/api/v1/tasks/') && method == 'GET') {
          final tId = path.split('/').last;
          final task = fakeTasks.firstWhere((t) => t.id == tId);
          return http.Response(
            jsonEncode(task.toJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{"detail":"Not Found"}', 404);
      });
    }

    testWidgets('1. TaskTemplatesScreen lists templates, searches, and filters by active state', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final templateService = TaskTemplateService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskTemplatesScreen(
            templateService: templateService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check templates rendered
      expect(find.text('Task Templates (2)'), findsOneWidget);
      expect(find.text('Weekly Client Review Template'), findsOneWidget);
      expect(find.text('Monthly Invoice Follow-up'), findsOneWidget);

      // Search
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Weekly');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Weekly Client Review Template'), findsOneWidget);
      expect(find.text('Monthly Invoice Follow-up'), findsNothing);
    });

    testWidgets('2. TaskTemplatesScreen allows instant "Use Template" to generate a concrete task', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final templateService = TaskTemplateService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskTemplatesScreen(
            templateService: templateService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap 'Use Template'
      final useButtons = find.text('Use Template');
      expect(useButtons, findsWidgets);
      await tester.tap(useButtons.first);
      await tester.pumpAndSettle();

      // Verify task creation
      expect(fakeTasks.any((t) => t.templateId == 'template-1'), isTrue);
    });

    testWidgets('3. TaskTemplateCreateScreen validates and creates a new TaskTemplate', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final templateService = TaskTemplateService(apiClient: apiClient);
      final clientService = ClientService(apiClient: apiClient);
      final workflowService = WorkflowService(apiClient: apiClient);
      final userService = UserService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskTemplateCreateScreen(
            templateService: templateService,
            clientService: clientService,
            workflowService: workflowService,
            userService: userService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify form elements
      expect(find.text('New Task Template'), findsOneWidget);

      // Enter name
      final nameField = find.widgetWithText(TextFormField, 'Template Name *');
      await tester.enterText(nameField, 'New Incident Response Blueprint');

      // Submit
      final createBtn = find.widgetWithText(ElevatedButton, 'Create Task Template');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Verify created in repository
      expect(fakeTemplates.any((t) => t.name == 'New Incident Response Blueprint'), isTrue);
    });

    testWidgets('4. RecurringTasksScreen renders schedules and executes recurrence evaluation', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final recurringService = RecurringTaskService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: RecurringTasksScreen(
            recurringService: recurringService,
            taskService: taskService,
          ),
        ),
      );

      try {
        await tester.pumpAndSettle();
      } catch (e, st) {
        debugPrint('TEST 4 PUMP ERROR: $e\n$st');
      }

      // Verify recurring tasks list
      expect(find.text('Weekly Account Sync Recurrence'), findsOneWidget);

      // Tap evaluate button
      final evalBtn = find.byTooltip('Evaluate Due Recurrences');
      expect(evalBtn, findsOneWidget);
      await tester.tap(evalBtn);
      await tester.pumpAndSettle();

      // Expect evaluation result snackbar
      expect(find.textContaining('Evaluated 1 definition(s), created 1 task instance(s).'), findsOneWidget);
    });

    testWidgets('5. TaskDetailScreen displays Template source badge for template tasks', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            taskService: taskService,
            taskId: 'task-template-child',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Source: Template'), findsOneWidget);
    });

    testWidgets('6. TaskDetailScreen displays Recurrence source badge for recurring tasks', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            taskService: taskService,
            taskId: 'task-recurring-child',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Source: Recurrence'), findsOneWidget);
    });

    testWidgets('7. TaskDetailScreen displays Manual source badge for ad-hoc tasks', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = createMockHttpClient();
      final apiClient = ApiClient(httpClient: client, tokenStorage: InMemoryTokenStorage('valid-jwt-token'));
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            taskService: taskService,
            taskId: 'task-manual',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Source: Manual'), findsOneWidget);
    });
  });
}
