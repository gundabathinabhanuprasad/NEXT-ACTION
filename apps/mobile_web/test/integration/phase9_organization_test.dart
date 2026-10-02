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
import 'package:nextaction/models/history/task_history_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/screens/clients/client_detail_screen.dart';
import 'package:nextaction/screens/clients/clients_screen.dart';
import 'package:nextaction/screens/home/home_screen.dart';
import 'package:nextaction/screens/tasks/task_create_screen.dart';
import 'package:nextaction/screens/tasks/task_detail_screen.dart';
import 'package:nextaction/screens/tasks/task_list_screen.dart';
import 'package:nextaction/screens/workflows/workflow_detail_screen.dart';
import 'package:nextaction/screens/workflows/workflows_screen.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/task/task_service.dart';
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

// Fake implementations for fast, deterministic widget testing
class FakeClientService extends ClientService {
  final List<Client> clients;
  FakeClientService({required this.clients});

  @override
  Future<ClientListResponse> getClients({String? search, int page = 1, int pageSize = 100}) async {
    var filtered = clients;
    if (search != null && search.isNotEmpty) {
      filtered = clients.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();
    }
    return ClientListResponse(items: filtered, total: filtered.length);
  }

  @override
  Future<Client> getClient(String clientId) async {
    return clients.firstWhere((c) => c.id == clientId);
  }

  @override
  Future<Client> createClient(ClientCreateRequest request) async {
    final client = Client(
      id: 'client-new-${DateTime.now().millisecondsSinceEpoch}',
      name: request.name,
      company: request.company,
      email: request.email,
      phone: request.phone,
      notes: request.notes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    clients.add(client);
    return client;
  }

  @override
  Future<Client> updateClient(String clientId, ClientUpdateRequest request) async {
    final index = clients.indexWhere((c) => c.id == clientId);
    final old = clients[index];
    final updated = Client(
      id: old.id,
      name: request.name ?? old.name,
      company: request.company ?? old.company,
      email: request.email ?? old.email,
      phone: request.phone ?? old.phone,
      notes: request.notes ?? old.notes,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
    );
    clients[index] = updated;
    return updated;
  }
}

class FakeWorkflowService extends WorkflowService {
  final List<Workflow> workflows;
  FakeWorkflowService({required this.workflows});

  @override
  Future<WorkflowListResponse> getWorkflows({bool? isActive, int page = 1, int pageSize = 100}) async {
    var filtered = workflows;
    if (isActive != null) {
      filtered = workflows.where((w) => w.isActive == isActive).toList();
    }
    return WorkflowListResponse(items: filtered, total: filtered.length);
  }

  @override
  Future<Workflow> getWorkflow(String workflowId) async {
    return workflows.firstWhere((w) => w.id == workflowId);
  }

  @override
  Future<Workflow> createWorkflow(WorkflowCreateRequest request) async {
    final workflow = Workflow(
      id: 'wf-new-${DateTime.now().millisecondsSinceEpoch}',
      name: request.name,
      description: request.description,
      isActive: request.isActive,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    workflows.add(workflow);
    return workflow;
  }

  @override
  Future<Workflow> updateWorkflow(String workflowId, WorkflowUpdateRequest request) async {
    final index = workflows.indexWhere((w) => w.id == workflowId);
    final old = workflows[index];
    final updated = Workflow(
      id: old.id,
      name: request.name ?? old.name,
      description: request.description ?? old.description,
      isActive: request.isActive ?? old.isActive,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
    );
    workflows[index] = updated;
    return updated;
  }
}

class FakeTaskService extends TaskService {
  final List<Task> tasks;
  FakeTaskService({required this.tasks})
      : super(
          apiClient: ApiClient(
            httpClient: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'items': [],
                  'total': 0,
                  'page': 1,
                  'page_size': 100,
                }),
                200,
              ),
            ),
            tokenStorage: InMemoryTokenStorage('fake_token'),
          ),
        );

  @override
  Future<TaskListResponse> getTasks({
    String? search,
    String? status,
    String? priority,
    String? assignedUserId,
    bool? unassigned,
    String? clientId,
    String? workflowId,
    DateTime? dueDateBefore,
    DateTime? dueFrom,
    DateTime? dueTo,
    DateTime? nextActionBefore,
    DateTime? nextActionFrom,
    DateTime? nextActionTo,
    bool? overdue,
    bool? dueToday,
    bool? upcoming,
    bool? hasNextAction,
    bool? noNextAction,
    bool? nearMaxAttempts,
    String? sortBy,
    String? sortOrder,
    int page = 1,
    int pageSize = 20,
  }) async {
    var filtered = tasks;
    if (clientId != null) {
      filtered = filtered.where((t) => t.clientId == clientId).toList();
    }
    if (workflowId != null) {
      filtered = filtered.where((t) => t.workflowId == workflowId).toList();
    }
    return TaskListResponse(items: filtered, total: filtered.length, page: page, pageSize: pageSize);
  }

  @override
  Future<Task> getTask(String taskId) async {
    return tasks.firstWhere((t) => t.id == taskId);
  }

  @override
  Future<Task> createTask(TaskCreateRequest request) async {
    final task = Task(
      id: 't-new-${DateTime.now().millisecondsSinceEpoch}',
      title: request.title,
      description: request.description,
      subjectLine: request.subjectLine,
      clientId: request.clientId,
      workflowId: request.workflowId,
      assignedUserId: request.assignedUserId,
      status: 'pending',
      priority: request.priority,
      dueDate: request.dueDate,
      nextActionDate: request.nextActionDate,
      attemptCount: 0,
      maxAttempts: request.maxAttempts,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    tasks.add(task);
    return task;
  }

  @override
  Future<List<FollowUp>> getFollowUps({String? taskId, bool? isCompleted, int page = 1, int pageSize = 100}) async => [];
  @override
  Future<List<TaskHistory>> getRecentActivity({int limit = 20, String? action, String? actorId, String? taskId}) async => [];
  @override
  Future<List<TaskHistory>> getTaskHistory(
    String taskId, {
    String? action,
    String? actorId,
    String order = 'desc',
    int? page,
    int? pageSize,
  }) async => [];
  @override
  Future<List<Reminder>> getTaskReminders(String taskId) async => [];
  @override
  Future<List<FollowUp>> getTaskFollowUps(String taskId) async => [];
}

class FakeAuthProvider extends AuthProvider {
  FakeAuthProvider() : super(authService: null);

  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  User? get currentUser => User(
        id: 'user-1',
        email: 'test@nextaction.local',
        name: 'Test Officer',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}

void main() {
  late List<Client> sampleClients;
  late List<Workflow> sampleWorkflows;
  late List<Task> sampleTasks;
  late FakeClientService clientService;
  late FakeWorkflowService workflowService;
  late FakeTaskService taskService;

  setUp(() {
    sampleClients = [
      Client(
        id: 'client-1',
        name: 'Acme Global',
        company: 'Acme Corp',
        email: 'info@acmeglobal.com',
        phone: '+1 555 1234',
        notes: 'Priority enterprise client',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Client(
        id: 'client-2',
        name: 'Beta Labs',
        company: 'Beta Industries',
        email: 'support@betalabs.com',
        phone: '+1 555 5678',
        notes: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    sampleWorkflows = [
      Workflow(
        id: 'wf-1',
        name: 'Enterprise Onboarding',
        description: 'Standard 14-day pipeline for new clients',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Workflow(
        id: 'wf-2',
        name: 'Legacy Migration',
        description: 'Phased migration out of legacy system',
        isActive: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    sampleTasks = [
      Task(
        id: 'task-1',
        title: 'Draft Enterprise Blueprint',
        description: 'Define SLA and milestones',
        subjectLine: 'RE: Blueprint',
        clientId: 'client-1',
        workflowId: 'wf-1',
        assignedUserId: null,
        status: 'in_progress',
        priority: 'urgent',
        attemptCount: 1,
        maxAttempts: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Task(
        id: 'task-2',
        title: 'Review System Specs',
        description: null,
        subjectLine: null,
        clientId: 'client-2',
        workflowId: 'wf-1',
        assignedUserId: null,
        status: 'completed',
        priority: 'medium',
        attemptCount: 0,
        maxAttempts: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    clientService = FakeClientService(clients: sampleClients);
    workflowService = FakeWorkflowService(workflows: sampleWorkflows);
    taskService = FakeTaskService(tasks: sampleTasks);
  });

  group('Phase 9 Organization Integration Tests', () {
    testWidgets('1. ClientsScreen lists clients and supports search', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ClientsScreen(
            clientService: clientService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Acme Global'), findsOneWidget);
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Beta Labs'), findsOneWidget);

      // Test Search
      await tester.enterText(find.byType(TextField), 'Acme');
      await tester.pumpAndSettle();

      expect(find.text('Acme Global'), findsOneWidget);
      expect(find.text('Beta Labs'), findsNothing);
    });

    testWidgets('2. ClientDetailScreen displays client info and related tasks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ClientDetailScreen(
            clientId: 'client-1',
            clientService: clientService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Acme Global'), findsWidgets);
      expect(find.text('info@acmeglobal.com'), findsOneWidget);
      expect(find.text('Priority enterprise client'), findsOneWidget);
      expect(find.text('Draft Enterprise Blueprint'), findsOneWidget);
      expect(find.text('Total Tasks'), findsOneWidget);
    });

    testWidgets('3. WorkflowsScreen lists workflows and filters active/inactive', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkflowsScreen(
            workflowService: workflowService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Workflows'), findsOneWidget);
      expect(find.text('Enterprise Onboarding'), findsOneWidget);
      expect(find.text('Legacy Migration'), findsOneWidget);

      // Filter Active Only
      await tester.tap(find.text('Active Only'));
      await tester.pumpAndSettle();

      expect(find.text('Enterprise Onboarding'), findsOneWidget);
      expect(find.text('Legacy Migration'), findsNothing);
    });

    testWidgets('4. WorkflowDetailScreen displays workflow info and associated tasks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkflowDetailScreen(
            workflowId: 'wf-1',
            workflowService: workflowService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Enterprise Onboarding'), findsWidgets);
      expect(find.text('Standard 14-day pipeline for new clients'), findsOneWidget);
      expect(find.text('Draft Enterprise Blueprint'), findsOneWidget);
      expect(find.text('Review System Specs'), findsOneWidget);
    });

    testWidgets('5. TaskCreateScreen allows selecting Client and Workflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskCreateScreen(
            taskService: taskService,
            clientService: clientService,
            workflowService: workflowService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Task Title *'), findsOneWidget);
      expect(find.text('Client'), findsOneWidget);
      expect(find.text('Workflow'), findsOneWidget);

      // Fill in form
      await tester.enterText(find.byType(TextFormField).first, 'Organized Pipeline Task');
      await tester.ensureVisible(find.text('Create Task'));
      await tester.tap(find.text('Create Task'));
      await tester.pumpAndSettle();

      expect(taskService.tasks.any((t) => t.title == 'Organized Pipeline Task'), isTrue);
    });

    testWidgets('6. TaskDetailScreen shows Client & Workflow Organization section', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            taskId: 'task-1',
            taskService: taskService,
            clientService: clientService,
            workflowService: workflowService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Client & Workflow Organization'), findsOneWidget);
      expect(find.text('View Client'), findsOneWidget);
      expect(find.text('View Workflow'), findsOneWidget);
    });

    testWidgets('7. TaskListScreen supports client-based and workflow-based filtering', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskListScreen(
            taskService: taskService,
            initialClientId: 'client-1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Draft Enterprise Blueprint'), findsOneWidget);
      expect(find.text('Review System Specs'), findsNothing);
    });

    testWidgets('8. HomeScreen provides 4 navigation destinations & workspace cards', (tester) async {
      final authProvider = FakeAuthProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            authProvider: authProvider,
            taskService: taskService,
            clientService: clientService,
            workflowService: workflowService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigation Bar items
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Workflows'), findsOneWidget);

      // Organization Workspace Cards on Dashboard
      expect(find.text('Active Clients'), findsOneWidget);
      expect(find.text('Active Workflows'), findsOneWidget);

      // Switch to Clients Tab
      await tester.tap(find.text('Clients'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Global'), findsOneWidget);

      // Switch to Workflows Tab
      await tester.tap(find.text('Workflows'));
      await tester.pumpAndSettle();
      expect(find.text('Enterprise Onboarding'), findsOneWidget);
    });
  });
}
