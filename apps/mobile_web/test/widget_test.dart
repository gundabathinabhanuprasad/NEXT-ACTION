import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/main.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/screens/auth/login_screen.dart';
import 'package:nextaction/screens/auth/register_screen.dart';
import 'package:nextaction/screens/home/home_screen.dart';
import 'package:nextaction/screens/tasks/task_create_screen.dart';
import 'package:nextaction/screens/tasks/task_detail_screen.dart';
import 'package:nextaction/screens/tasks/task_list_screen.dart';
import 'package:nextaction/services/auth/auth_service.dart';
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
  testWidgets('renders LoginScreen when unauthenticated', (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    final apiClient = ApiClient(
      httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
      tokenStorage: tokenStorage,
    );
    final authService = AuthService(apiClient: apiClient);
    final authProvider = AuthProvider(authService: authService);
    final taskService = TaskService(apiClient: apiClient);

    await authProvider.checkAuthStatus();

    await tester.pumpWidget(
      NextActionApp(
        authProvider: authProvider,
        taskService: taskService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NextAction'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('renders HomeScreen when authenticated', (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage('sample_valid_token');
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/me') {
        return http.Response(
          jsonEncode({
            'id': 'u123',
            'name': 'Test User',
            'email': 'tester@nextaction.local',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/tasks') {
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/follow-ups') {
        return http.Response(jsonEncode([]), 200);
      }
      if (request.url.path == '/api/v1/tasks/activity/recent') {
        return http.Response(jsonEncode([]), 200);
      }
      if (request.url.path == '/api/v1/clients') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 1}), 200);
      }
      if (request.url.path == '/api/v1/workflows') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 1}), 200);
      }
      if (request.url.path == '/api/v1/users') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 1}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
    final authService = AuthService(apiClient: apiClient);
    final authProvider = AuthProvider(authService: authService);
    final taskService = TaskService(apiClient: apiClient);

    await authProvider.checkAuthStatus();

    await tester.pumpWidget(
      NextActionApp(
        authProvider: authProvider,
        taskService: taskService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Test User', skipOffstage: false), findsOneWidget);
    expect(find.text('tester@nextaction.local', skipOffstage: false), findsOneWidget);
    expect(find.text('JWT AUTHENTICATED', skipOffstage: false), findsOneWidget);
  });

  testWidgets('HomeScreen renders complete NextAction Dashboard with KPI cards and sections', (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage('sample_valid_token');
    final now = DateTime.now();
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/me') {
        return http.Response(
          jsonEncode({
            'id': 'u123',
            'name': 'Bhanu Workspace',
            'email': 'bhanu@nextaction.local',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/tasks') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 't-overdue',
                'title': 'Overdue Strategy Review',
                'subject_line': 'Urgent Strategy',
                'status': 'in_progress',
                'priority': 'urgent',
                'due_date': now.subtract(const Duration(days: 2)).toIso8601String(),
                'attempt_count': 1,
                'max_attempts': 2,
                'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
                'updated_at': now.subtract(const Duration(days: 2)).toIso8601String(),
              },
              {
                'id': 't-today',
                'title': 'Client Due Today Action',
                'status': 'pending',
                'priority': 'high',
                'due_date': now.toIso8601String(),
                'attempt_count': 0,
                'max_attempts': 2,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
              },
              {
                'id': 't-nearmax',
                'title': 'Critical Attempt Task',
                'status': 'blocked',
                'priority': 'urgent',
                'attempt_count': 2,
                'max_attempts': 2,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
              }
            ],
            'total': 3,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/reminders') {
        return http.Response(
          jsonEncode([
            {
              'id': 'rem-101',
              'task_id': 't-today',
              'remind_at': now.add(const Duration(hours: 2)).toIso8601String(),
              'is_sent': false,
              'sent_at': null,
              'created_at': now.toIso8601String(),
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v1/follow-ups') {
        return http.Response(
          jsonEncode([
            {
              'id': 'fol-101',
              'task_id': 't-today',
              'scheduled_at': now.add(const Duration(days: 1)).toIso8601String(),
              'notes': 'Follow up with stakeholders',
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v1/tasks/activity/recent') {
        return http.Response(
          jsonEncode([
            {
              'id': 'act-1',
              'task_id': 't-today',
              'action': 'created',
              'reason': 'Initial workflow creation',
              'created_at': now.toIso8601String(),
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v1/clients') {
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/workflows') {
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/users') {
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
    final authService = AuthService(apiClient: apiClient);
    final authProvider = AuthProvider(authService: authService);
    final taskService = TaskService(apiClient: apiClient);

    await authProvider.checkAuthStatus();

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      NextActionApp(
        authProvider: authProvider,
        taskService: taskService,
      ),
    );
    await tester.pumpAndSettle();

    // Verify Dashboard sections
    expect(find.text("Today's Overview"), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Due Today'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Near Max Attempts'), findsOneWidget);

    // Verify task tiles rendered in dashboard
    expect(find.text('Client Due Today Action'), findsOneWidget);
    expect(find.text('Overdue Strategy Review'), findsOneWidget);

    // Verify follow-ups section
    expect(find.text('Pending Follow-ups'), findsOneWidget);
    expect(find.text('Follow up with stakeholders'), findsOneWidget);

    // Verify recent activity section
    expect(find.text('Recent Activity'), findsOneWidget);
    expect(find.text('Task created'), findsOneWidget);
  });

  testWidgets('can navigate from Login to Register screen', (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    final apiClient = ApiClient(
      httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
      tokenStorage: tokenStorage,
    );
    final authService = AuthService(apiClient: apiClient);
    final authProvider = AuthProvider(authService: authService);
    final taskService = TaskService(apiClient: apiClient);

    await authProvider.checkAuthStatus();

    await tester.pumpWidget(
      NextActionApp(
        authProvider: authProvider,
        taskService: taskService,
      ),
    );
    await tester.pumpAndSettle();

    // Tap Register text button
    final registerButton = find.text('Register');
    expect(registerButton, findsOneWidget);
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Get Started with NextAction'), findsOneWidget);
  });

  testWidgets('TaskListScreen renders search bar, filters, and task cards', (WidgetTester tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/v1/tasks') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'task-101',
                'title': 'Client Discovery Meeting',
                'subject_line': 'RE: Discovery notes',
                'status': 'pending',
                'priority': 'urgent',
                'due_date': '2026-10-01T15:00:00Z',
                'next_action_date': '2026-09-28T09:00:00Z',
                'attempt_count': 1,
                'max_attempts': 2,
                'created_at': '2026-09-27T10:00:00Z',
                'updated_at': '2026-09-27T10:00:00Z',
              }
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/users') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 100}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
    final taskService = TaskService(apiClient: apiClient);

    await tester.pumpWidget(
      MaterialApp(
        home: TaskListScreen(taskService: taskService),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Client Discovery Meeting'), findsOneWidget);
    expect(find.text('RE: Discovery notes'), findsOneWidget);
    expect(find.text('URGENT'), findsOneWidget);
    expect(find.text('Attempts: 1 / 2'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // Search bar
    expect(find.text('New Task'), findsOneWidget);
  });

  testWidgets('TaskCreateScreen validates required fields and submits', (WidgetTester tester) async {
    bool taskCreated = false;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/v1/tasks') {
        taskCreated = true;
        return http.Response(
          jsonEncode({
            'id': 'new-task-uuid',
            'title': 'New Test Task',
            'status': 'pending',
            'priority': 'medium',
            'attempt_count': 0,
            'max_attempts': 2,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          201,
        );
      }
      if (request.url.path == '/api/v1/clients') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 100}), 200);
      }
      if (request.url.path == '/api/v1/workflows') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 100}), 200);
      }
      if (request.url.path == '/api/v1/users') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 100}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
    final taskService = TaskService(apiClient: apiClient);

    await tester.pumpWidget(
      MaterialApp(
        home: TaskCreateScreen(taskService: taskService),
      ),
    );
    // Tap submit with empty title
    await tester.ensureVisible(find.text('Create Task'));
    await tester.tap(find.text('Create Task'));
    await tester.pumpAndSettle();
    expect(find.text('Task title is required'), findsOneWidget);
    expect(taskCreated, isFalse);

    // Fill title
    await tester.enterText(find.byType(TextFormField).first, 'New Test Task');
    await tester.ensureVisible(find.text('Create Task'));
    await tester.tap(find.text('Create Task'));
    await tester.pumpAndSettle();

    expect(taskCreated, isTrue);
  });

  testWidgets('TaskDetailScreen renders complete 10 sections and action triggers', (WidgetTester tester) async {
    final sampleTask = Task(
      id: 'task-abc-123',
      title: 'Detailed Task Spec',
      description: 'Full workflow specification review',
      subjectLine: 'RE: Spec details',
      priority: 'high',
      status: 'pending',
      attemptCount: 1,
      maxAttempts: 2,
      dueDate: DateTime.parse('2026-10-02T18:00:00Z'),
      nextActionDate: DateTime.parse('2026-09-29T10:00:00Z'),
      createdAt: DateTime.parse('2026-09-27T08:00:00Z'),
      updatedAt: DateTime.parse('2026-09-27T08:30:00Z'),
    );

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/v1/tasks/task-abc-123') {
        return http.Response(jsonEncode(sampleTask.toJson()), 200);
      }
      if (request.url.path == '/api/v1/tasks/task-abc-123/history') {
        return http.Response(
          jsonEncode([
            {
              'id': 'h1',
              'task_id': 'task-abc-123',
              'action': 'created',
              'created_at': '2026-09-27T08:00:00Z',
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v1/tasks/task-abc-123/reminders') {
        return http.Response(
          jsonEncode([
            {
              'id': 'rem-1',
              'task_id': 'task-abc-123',
              'remind_at': '2026-09-28T12:00:00Z',
              'message': 'Initial reminder alert',
              'is_sent': false,
              'created_at': '2026-09-27T08:00:00Z',
              'updated_at': '2026-09-27T08:00:00Z',
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v1/tasks/task-abc-123/follow-ups') {
        return http.Response(
          jsonEncode([
            {
              'id': 'fol-1',
              'task_id': 'task-abc-123',
              'scheduled_at': '2026-09-30T10:00:00Z',
              'notes': 'Check on customer contract',
              'created_at': '2026-09-27T08:00:00Z',
              'updated_at': '2026-09-27T08:00:00Z',
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v1/users') {
        return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 100}), 200);
      }
      if (request.url.path.startsWith('/api/v1/users/')) {
        return http.Response(
          jsonEncode({
            'id': 'u1',
            'name': 'User 1',
            'email': 'u1@test.com',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    final apiClient = ApiClient(httpClient: mockClient, tokenStorage: InMemoryTokenStorage('tok'));
    final taskService = TaskService(apiClient: apiClient);

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailScreen(
          taskId: sampleTask.id,
          initialTask: sampleTask,
          taskService: taskService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check sections
    expect(find.text('Task Information'), findsOneWidget);
    expect(find.text('Detailed Task Spec'), findsOneWidget);
    expect(find.text('Full workflow specification review'), findsOneWidget);
    expect(find.text('Lifecycle & Assignment'), findsOneWidget);
    expect(find.text('Dates & Scheduling'), findsOneWidget);
    expect(find.text('Work Attempts Workflow'), findsOneWidget);
    expect(find.text('Record Work Attempt'), findsOneWidget);
    expect(find.text('Authorized Override'), findsOneWidget);
    expect(find.text('Task Lifecycle Actions'), findsOneWidget);
    expect(find.text('Complete Task'), findsOneWidget);
    expect(find.text('Reminders (1)'), findsOneWidget);
    expect(find.text('Initial reminder alert'), findsOneWidget);
    expect(find.text('Follow-ups (1)'), findsOneWidget);
    expect(find.text('Check on customer contract'), findsOneWidget);
    expect(find.text('Audit History Timeline (1)'), findsOneWidget);
  });
}
