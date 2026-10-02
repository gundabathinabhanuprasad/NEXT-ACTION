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
import 'package:nextaction/screens/home/home_screen.dart';
import 'package:nextaction/screens/profile/profile_screen.dart';
import 'package:nextaction/screens/tasks/task_create_screen.dart';
import 'package:nextaction/screens/tasks/task_detail_screen.dart';
import 'package:nextaction/screens/tasks/task_list_screen.dart';
import 'package:nextaction/screens/team/team_member_detail_screen.dart';
import 'package:nextaction/screens/team/team_screen.dart';
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

// Fake implementations for fast, deterministic widget testing
class FakeUserService extends UserService {
  final List<User> users;
  User currentUser;

  FakeUserService({required this.users, required this.currentUser});

  @override
  Future<UserListResponse> getUsers({String? search, bool? isActive, int page = 1, int pageSize = 100}) async {
    var filtered = users;
    if (search != null && search.isNotEmpty) {
      filtered = filtered
          .where((u) =>
              u.name.toLowerCase().contains(search.toLowerCase()) ||
              u.email.toLowerCase().contains(search.toLowerCase()))
          .toList();
    }
    if (isActive != null) {
      filtered = filtered.where((u) => u.isActive == isActive).toList();
    }
    return UserListResponse(items: filtered, total: filtered.length, page: page, pageSize: pageSize);
  }

  @override
  Future<User> getUser(String userId) async {
    return users.firstWhere((u) => u.id == userId);
  }

  @override
  Future<User> getCurrentUser() async {
    return currentUser;
  }
}

class FakeClientService extends ClientService {
  final List<Client> clients;
  FakeClientService({required this.clients});

  @override
  Future<ClientListResponse> getClients({String? search, int page = 1, int pageSize = 100}) async {
    return ClientListResponse(items: clients, total: clients.length);
  }
}

class FakeWorkflowService extends WorkflowService {
  final List<Workflow> workflows;
  FakeWorkflowService({required this.workflows});

  @override
  Future<WorkflowListResponse> getWorkflows({bool? isActive, int page = 1, int pageSize = 100}) async {
    return WorkflowListResponse(items: workflows, total: workflows.length);
  }
}

class FakeTaskService extends TaskService {
  final List<Task> tasks;
  final List<TaskHistory> histories;

  FakeTaskService({required this.tasks, List<TaskHistory>? histories})
      : histories = histories ?? [],
        super(
          apiClient: ApiClient(
            httpClient: MockClient(
              (_) async => http.Response(
                jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 100}),
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
    if (assignedUserId != null) {
      filtered = filtered.where((t) => t.assignedUserId == assignedUserId).toList();
    }
    if (unassigned == true) {
      filtered = filtered.where((t) => t.assignedUserId == null).toList();
    }
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
  Future<Task> assignTask(String taskId, {String? assignedUserId}) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    final old = tasks[index];
    final updated = Task(
      id: old.id,
      title: old.title,
      description: old.description,
      subjectLine: old.subjectLine,
      clientId: old.clientId,
      workflowId: old.workflowId,
      assignedUserId: assignedUserId,
      status: old.status,
      priority: old.priority,
      dueDate: old.dueDate,
      nextActionDate: old.nextActionDate,
      attemptCount: old.attemptCount,
      maxAttempts: old.maxAttempts,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
    );
    tasks[index] = updated;

    histories.add(TaskHistory(
      id: 'h-${DateTime.now().millisecondsSinceEpoch}',
      taskId: taskId,
      action: 'assigned',
      oldValue: old.assignedUserId,
      newValue: assignedUserId,
      createdByUserId: 'u-current',
      createdAt: DateTime.now(),
    ));

    return updated;
  }

  @override
  Future<List<TaskHistory>> getTaskHistory(
    String taskId, {
    String? action,
    String? actorId,
    String order = 'desc',
    int? page,
    int? pageSize,
  }) async {
    var list = histories.where((h) => h.taskId == taskId).toList();
    if (action != null) {
      list = list.where((h) => h.action == action).toList();
    }
    return list;
  }

  @override
  Future<List<FollowUp>> getFollowUps({String? taskId, bool? isCompleted, int page = 1, int pageSize = 100}) async => [];
  @override
  Future<List<TaskHistory>> getRecentActivity({int limit = 20, String? action, String? actorId, String? taskId}) async => histories;
  @override
  Future<List<Reminder>> getTaskReminders(String taskId) async => [];
  @override
  Future<List<FollowUp>> getTaskFollowUps(String taskId) async => [];
}

class FakeAuthProvider extends AuthProvider {
  final User _currentUser;
  bool _isLoggedOut = false;

  FakeAuthProvider(this._currentUser) : super(authService: null);

  @override
  AuthStatus get status => _isLoggedOut ? AuthStatus.unauthenticated : AuthStatus.authenticated;

  @override
  User? get currentUser => _isLoggedOut ? null : _currentUser;

  @override
  Future<void> logout() async {
    _isLoggedOut = true;
    notifyListeners();
  }
}

void main() {
  group('Phase 10 User, Assignment & Team Workspace Integration Tests', () {
    late User userA;
    late User userB;
    late List<User> sampleUsers;
    late List<Task> sampleTasks;
    late FakeUserService userService;
    late FakeTaskService taskService;
    late FakeAuthProvider authProvider;

    setUp(() {
      userA = User(
        id: 'u-user-a',
        email: 'alice@nextaction.local',
        name: 'Alice Developer',
        isActive: true,
        createdAt: DateTime.parse('2026-09-01T10:00:00Z'),
        updatedAt: DateTime.parse('2026-09-20T10:00:00Z'),
      );

      userB = User(
        id: 'u-user-b',
        email: 'bob@nextaction.local',
        name: 'Bob Operator',
        isActive: true,
        createdAt: DateTime.parse('2026-09-05T12:00:00Z'),
        updatedAt: DateTime.parse('2026-09-25T12:00:00Z'),
      );

      sampleUsers = [userA, userB];

      sampleTasks = [
        Task(
          id: 'task-1',
          title: 'Alice Security Audit',
          description: 'Perform OAuth token audit',
          assignedUserId: userA.id,
          status: 'in_progress',
          priority: 'urgent',
          attemptCount: 1,
          maxAttempts: 3,
          createdAt: DateTime.parse('2026-09-27T08:00:00Z'),
          updatedAt: DateTime.parse('2026-09-27T08:00:00Z'),
        ),
        Task(
          id: 'task-2',
          title: 'Bob Deployment Pipeline',
          description: 'Setup CI/CD deployment checks',
          assignedUserId: userB.id,
          status: 'pending',
          priority: 'high',
          attemptCount: 0,
          maxAttempts: 2,
          createdAt: DateTime.parse('2026-09-27T09:00:00Z'),
          updatedAt: DateTime.parse('2026-09-27T09:00:00Z'),
        ),
        Task(
          id: 'task-3',
          title: 'Unassigned Backlog Item',
          description: 'Investigate slow database query',
          assignedUserId: null,
          status: 'pending',
          priority: 'low',
          attemptCount: 0,
          maxAttempts: 2,
          createdAt: DateTime.parse('2026-09-27T10:00:00Z'),
          updatedAt: DateTime.parse('2026-09-27T10:00:00Z'),
        ),
      ];

      userService = FakeUserService(users: sampleUsers, currentUser: userA);
      taskService = FakeTaskService(tasks: sampleTasks);
      authProvider = FakeAuthProvider(userA);
    });

    testWidgets('1. ProfileScreen displays authenticated user identity without password hash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authProvider: authProvider,
            userService: userService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Alice Developer'), findsOneWidget);
      expect(find.text('alice@nextaction.local'), findsOneWidget);
      expect(find.text('Active Account'), findsOneWidget);
      expect(find.text('u-user-a'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('View My Assigned Tasks'), findsOneWidget);
      // Verify password hash or sensitive internals are absent
      expect(find.textContaining('password_hash'), findsNothing);
      expect(find.textContaining('token'), findsNothing);
    });

    testWidgets('2. TeamScreen lists team members with search and active badges', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TeamScreen(
            userService: userService,
            taskService: taskService,
            currentUserId: userA.id,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Team Members'), findsOneWidget);
      expect(find.text('Alice Developer'), findsOneWidget);
      expect(find.text('Bob Operator'), findsOneWidget);
      expect(find.text('You'), findsOneWidget); // Current user chip

      // Test Search
      await tester.enterText(find.byType(TextField).first, 'Bob');
      await tester.pumpAndSettle();

      expect(find.text('Bob Operator'), findsOneWidget);
      expect(find.text('Alice Developer'), findsNothing);
    });

    testWidgets('3. TeamMemberDetailScreen displays workload metrics and deep link to assigned tasks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TeamMemberDetailScreen(
            userId: userB.id,
            initialUser: userB,
            userService: userService,
            taskService: taskService,
            currentUserId: userA.id,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Bob Operator'), findsWidgets);
      expect(find.text('bob@nextaction.local'), findsOneWidget);
      expect(find.text('Workload Statistics'), findsOneWidget);
      expect(find.text('Total Assigned'), findsOneWidget);
      expect(find.text('View Assigned Tasks (1)'), findsOneWidget);
    });

    testWidgets('4. TaskCreateScreen supports selecting real user assignee', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskCreateScreen(
            taskService: taskService,
            userService: userService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Assigned Team Member'), findsOneWidget);
      expect(find.text('Unassigned (No assignee)'), findsOneWidget);

      // Fill in form
      await tester.enterText(find.byType(TextFormField).first, 'Assigned Pipeline Task');
      await tester.ensureVisible(find.text('Create Task'));
      await tester.tap(find.text('Create Task'));
      await tester.pumpAndSettle();

      expect(taskService.tasks.any((t) => t.title == 'Assigned Pipeline Task'), isTrue);
    });

    testWidgets('5. TaskDetailScreen displays assignee and supports interactive reassignment', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            taskId: 'task-1',
            initialTask: sampleTasks.first,
            taskService: taskService,
            userService: userService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Lifecycle & Assignment'), findsOneWidget);
      expect(find.text('Assigned To'), findsOneWidget);
      expect(find.text('Alice Developer'), findsOneWidget);
      expect(find.text('alice@nextaction.local'), findsOneWidget);

      // Tap Reassign button
      await tester.ensureVisible(find.text('Reassign'));
      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();

      expect(find.text('Assign / Reassign Task'), findsOneWidget);
      expect(find.text('Assignee'), findsOneWidget);

      // Open Dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();

      expect(find.text('Bob Operator (bob@nextaction.local)').last, findsOneWidget);
      await tester.tap(find.text('Bob Operator (bob@nextaction.local)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Assignment'));
      await tester.pumpAndSettle();

      expect(taskService.tasks.firstWhere((t) => t.id == 'task-1').assignedUserId, equals(userB.id));
    });

    testWidgets('6. TaskListScreen filters by Assigned to Me and Unassigned', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskListScreen(
            taskService: taskService,
            userService: userService,
            currentUserId: userA.id,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially all tasks are shown
      expect(find.text('Alice Security Audit'), findsOneWidget);
      expect(find.text('Bob Deployment Pipeline'), findsOneWidget);
      expect(find.text('Unassigned Backlog Item'), findsOneWidget);

      // Tap Assigned to Me filter chip
      await tester.tap(find.text('Assigned to Me'));
      await tester.pumpAndSettle();

      expect(find.text('Alice Security Audit'), findsOneWidget);
      expect(find.text('Bob Deployment Pipeline'), findsNothing);
      expect(find.text('Unassigned Backlog Item'), findsNothing);

      // Tap Unassigned filter chip
      await tester.tap(find.text('Unassigned'));
      await tester.pumpAndSettle();

      expect(find.text('Unassigned Backlog Item'), findsOneWidget);
      expect(find.text('Alice Security Audit'), findsNothing);
    });

    testWidgets('7. HomeScreen provides 5 navigation tabs, Profile button, and Team dashboard metrics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            authProvider: authProvider,
            taskService: taskService,
            userService: userService,
            clientService: FakeClientService(clients: []),
            workflowService: FakeWorkflowService(workflows: []),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigation Bar items
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Workflows'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);

      // Workspace Cards on Dashboard
      expect(find.text('My Tasks'), findsOneWidget);
      expect(find.text('Unassigned Tasks'), findsOneWidget);
      expect(find.text('Team Members'), findsOneWidget);
    });
  });
}
