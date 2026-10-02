import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/task/task_service.dart';

class TestTokenStorage implements TokenStorage {
  String? _token;

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
  group('Phase 8 Live End-to-End NextAction Dashboard & Productivity Workspace Verification', () {
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late TestTokenStorage tokenStorage;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'phase8_user_$testRunId@nextaction.local';
    const testPassword = 'Password123!';
    final testName = 'Phase 8 Lead $testRunId';
    late String createdTaskId;
    late String overdueTaskId;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      taskService = TaskService(apiClient: apiClient);

      // Register user
      final user = await authProvider.register(testName, testEmail, testPassword);
      expect(user, isNotNull);
    });

    test('1. Login with credentials and receive authenticated JWT session', () async {
      final success = await authProvider.login(testEmail, testPassword);
      expect(success, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(await tokenStorage.hasToken(), isTrue);
    });

    test('2. Dashboard initial data loads from PostgreSQL', () async {
      final initialTasks = await taskService.getTasks(page: 1, pageSize: 100);
      expect(initialTasks.items, isA<List<Task>>());

      final initialFollowUps = await taskService.getFollowUps(isCompleted: false);
      expect(initialFollowUps, isA<List<FollowUp>>());

      final initialActivities = await taskService.getRecentActivity(limit: 10);
      expect(initialActivities, isA<List>());
    });

    test('3. Create task scheduled for Today and verify dashboard reflects real task', () async {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day, 17, 0, 0);

      final task = await taskService.createTask(
        TaskCreateRequest(
          title: 'Phase 8 Client Strategy Review',
          description: 'Quarterly review with executive team',
          subjectLine: 'Strategy Q4',
          priority: 'urgent',
          dueDate: todayDate,
          maxAttempts: 2,
        ),
      );

      expect(task.id, isNotEmpty);
      expect(task.title, equals('Phase 8 Client Strategy Review'));
      expect(task.priority, equals('urgent'));
      expect(task.status, equals('pending'));
      expect(task.isDueToday, isTrue);
      createdTaskId = task.id;
    });

    test('4. Create Overdue task and verify real overdue categorization', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 3));

      final overdueTask = await taskService.createTask(
        TaskCreateRequest(
          title: 'Overdue Vendor Agreement SLA',
          priority: 'high',
          dueDate: pastDate,
          maxAttempts: 2,
        ),
      );

      expect(overdueTask.id, isNotEmpty);
      expect(overdueTask.isOverdue, isTrue);
      expect(overdueTask.isDueToday, isFalse);
      overdueTaskId = overdueTask.id;
    });

    test('5. Create Follow-up and verify pending follow-ups in dashboard', () async {
      final followUp = await taskService.createFollowUp(
        FollowUpCreateRequest(
          taskId: createdTaskId,
          scheduledAt: DateTime.now().add(const Duration(days: 2)),
          notes: 'Prepare executive deck follow-up',
        ),
      );

      expect(followUp.id, isNotEmpty);
      expect(followUp.isCompleted, isFalse);

      final pendingFollowUps = await taskService.getFollowUps(isCompleted: false);
      expect(pendingFollowUps.any((f) => f.id == followUp.id), isTrue);
    });

    test('6. Record attempt on created task and verify real attempt counter and activity log', () async {
      final task = await taskService.recordAttempt(createdTaskId, notes: 'Initiated presentation');
      expect(task.attemptCount, equals(1));
      expect(task.isApproachingMaxAttempts, isTrue);

      final recentActivities = await taskService.getRecentActivity(limit: 10);
      expect(recentActivities.any((a) => a.action == 'attempt' && a.taskId == createdTaskId), isTrue);
    });

    test('7. Modify status and priority and verify real distribution updates', () async {
      final updatedTask = await taskService.changeStatus(
        createdTaskId,
        status: 'in_progress',
        reason: 'Active sprint execution',
      );
      expect(updatedTask.status, equals('in_progress'));

      final allTasks = await taskService.getTasks(page: 1, pageSize: 100);
      final inProgressTasks = allTasks.items.where((t) => t.status == 'in_progress').toList();
      expect(inProgressTasks.any((t) => t.id == createdTaskId), isTrue);
    });

    test('8. Complete task and verify completed stats update in real PostgreSQL', () async {
      final completed = await taskService.completeTask(createdTaskId);
      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);

      final allTasks = await taskService.getTasks(page: 1, pageSize: 100);
      final completedList = allTasks.items.where((t) => t.isCompleted).toList();
      expect(completedList.any((t) => t.id == createdTaskId), isTrue);
    });

    test('9. Reopen task and verify status transition and audit history log', () async {
      final reopened = await taskService.reopenTask(
        createdTaskId,
        reason: 'Client requested amendments',
      );
      expect(reopened.isCompleted, isFalse);
      expect(reopened.status, equals('pending'));

      final history = await taskService.getTaskHistory(createdTaskId);
      expect(history.any((h) => h.action == 'reopened'), isTrue);
    });

    test('10. Logout clears JWT session', () async {
      await authProvider.logout();
      expect(authProvider.isAuthenticated, isFalse);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('11. Login again re-establishes session and reloads dashboard from PostgreSQL', () async {
      final success = await authProvider.login(testEmail, testPassword);
      expect(success, isTrue);
      expect(authProvider.isAuthenticated, isTrue);

      final tasks = await taskService.getTasks(page: 1, pageSize: 100);
      expect(tasks.items.any((t) => t.id == createdTaskId), isTrue);
      expect(tasks.items.any((t) => t.id == overdueTaskId), isTrue);

      final activities = await taskService.getRecentActivity(limit: 10);
      expect(activities.isNotEmpty, isTrue);
    });
  });
}
