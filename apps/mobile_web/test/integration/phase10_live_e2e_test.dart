import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/user/user_service.dart';

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
  group('Phase 10 Live End-to-End Users, Assignment & Team Workspace Verification (24 Steps)', () {
    late ApiClient apiClientA;
    late AuthService authServiceA;
    late AuthProvider authProviderA;
    late TaskService taskServiceA;
    late UserService userServiceA;
    late TestTokenStorage tokenStorageA;

    late ApiClient apiClientB;
    late AuthService authServiceB;
    late AuthProvider authProviderB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userAEmail = 'user_a_$testRunId@nextaction.local';
    final userAName = 'User A $testRunId';
    const userAPassword = 'Password123!';

    final userBEmail = 'user_b_$testRunId@nextaction.local';
    final userBName = 'User B $testRunId';
    const userBPassword = 'Password123!';

    late User createdUserA;
    late User createdUserB;
    late String createdTaskId;
    late String unassignedTaskId;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorageA = TestTokenStorage();
      apiClientA = ApiClient(tokenStorage: tokenStorageA);
      authServiceA = AuthService(apiClient: apiClientA);
      authProviderA = AuthProvider(authService: authServiceA);
      taskServiceA = TaskService(apiClient: apiClientA);
      userServiceA = UserService(apiClient: apiClientA);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      authProviderB = AuthProvider(authService: authServiceB);
    });

    test('1. Register/login User A', () async {
      final user = await authProviderA.register(userAName, userAEmail, userAPassword);
      expect(user, isNotNull);
      expect(user!.email, equals(userAEmail));
      expect(user.name, equals(userAName));
      createdUserA = user;

      final success = await authProviderA.login(userAEmail, userAPassword);
      expect(success, isTrue);
      expect(authProviderA.isAuthenticated, isTrue);
      expect(await tokenStorageA.hasToken(), isTrue);
    });

    test('2. Load /auth/me as authoritative user identity source', () async {
      final currentUser = await userServiceA.getCurrentUser();
      expect(currentUser.id, equals(createdUserA.id));
      expect(currentUser.email, equals(userAEmail));
      expect(currentUser.name, equals(userAName));
      expect(currentUser.isActive, isTrue);
    });

    test('3. Load team users from real PostgreSQL', () async {
      final team = await userServiceA.getUsers(page: 1, pageSize: 100);
      expect(team.items, isNotEmpty);
      expect(team.total, isPositive);
    });

    test('4. Verify User A appears in team user list', () async {
      final team = await userServiceA.getUsers(search: userAName);
      expect(team.items.any((u) => u.id == createdUserA.id), isTrue);
      final foundUser = team.items.firstWhere((u) => u.id == createdUserA.id);
      expect(foundUser.email, equals(userAEmail));
      expect(foundUser.name, equals(userAName));
    });

    test('5. Verify password_hash is absent from all user API responses', () async {
      final rawResponse = await apiClientA.get('/users', requiresAuth: true) as Map<String, dynamic>;
      final rawItems = rawResponse['items'] as List<dynamic>;
      for (final item in rawItems) {
        final userMap = item as Map<String, dynamic>;
        expect(userMap.containsKey('password_hash'), isFalse);
        expect(userMap.containsKey('password'), isFalse);
        expect(userMap.containsKey('hashed_password'), isFalse);
      }
    });

    test('6. Create User B via registration and 7. Login User B in authenticated environment', () async {
      final userB = await authProviderB.register(userBName, userBEmail, userBPassword);
      expect(userB, isNotNull);
      expect(userB!.email, equals(userBEmail));
      expect(userB.name, equals(userBName));
      createdUserB = userB;

      final success = await authProviderB.login(userBEmail, userBPassword);
      expect(success, isTrue);
      expect(authProviderB.isAuthenticated, isTrue);
    });

    test('8. Create a task as User A and 9. Assign task to User B', () async {
      final task = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Cross-Team Assignment Task $testRunId',
          description: 'Security & architecture handover',
          assignedUserId: createdUserB.id,
          priority: 'high',
          maxAttempts: 3,
        ),
      );

      expect(task.id, isNotEmpty);
      expect(task.title, equals('Cross-Team Assignment Task $testRunId'));
      createdTaskId = task.id;

      // Also create an unassigned task for filter tests
      final unassigned = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Unassigned Team Task $testRunId',
          description: 'General workspace maintenance',
          priority: 'medium',
          maxAttempts: 2,
        ),
      );
      unassignedTaskId = unassigned.id;
    });

    test('10. Verify task assignee is User B', () async {
      final task = await taskServiceA.getTask(createdTaskId);
      expect(task.assignedUserId, equals(createdUserB.id));
    });

    test('11. Verify actor in task history identifies User A (not assignee)', () async {
      final history = await taskServiceA.getTaskHistory(createdTaskId);
      expect(history, isNotEmpty);
      final createLog = history.firstWhere((h) => h.action == 'created');
      expect(createLog.createdByUserId, equals(createdUserA.id));
    });

    test('12. Reassign task to another valid user (User A)', () async {
      final reassignedTask = await taskServiceA.assignTask(
        createdTaskId,
        assignedUserId: createdUserA.id,
      );
      expect(reassignedTask.assignedUserId, equals(createdUserA.id));
    });

    test('13. Verify history records the reassignment (Actor: User A, Old: User B, New: User A)', () async {
      final history = await taskServiceA.getTaskHistory(createdTaskId);
      final assignLogs = history.where((h) => h.action == 'reassigned').toList();
      expect(assignLogs, isNotEmpty);

      final latestAssign = assignLogs.first;
      expect(latestAssign.oldValue, equals(createdUserB.id));
      expect(latestAssign.newValue, equals(createdUserA.id));
      expect(latestAssign.createdByUserId, equals(createdUserA.id));
    });

    test('14. Open My Tasks and 15. Verify assigned tasks appear correctly', () async {
      final myTasks = await taskServiceA.getTasks(
        assignedUserId: createdUserA.id,
      );
      expect(myTasks.items.any((t) => t.id == createdTaskId), isTrue);
      expect(myTasks.items.any((t) => t.id == unassignedTaskId), isFalse);
    });

    test('16. Filter tasks by current user', () async {
      final filtered = await taskServiceA.getTasks(
        assignedUserId: createdUserA.id,
      );
      for (final t in filtered.items) {
        expect(t.assignedUserId, equals(createdUserA.id));
      }
    });

    test('17. Filter unassigned tasks', () async {
      final unassignedList = await taskServiceA.getTasks(
        unassigned: true,
      );
      expect(unassignedList.items.any((t) => t.id == unassignedTaskId), isTrue);
      for (final t in unassignedList.items) {
        expect(t.assignedUserId, isNull);
      }
    });

    test('18. Open task detail and 19. Verify assignee display', () async {
      final task = await taskServiceA.getTask(createdTaskId);
      expect(task.assignedUserId, equals(createdUserA.id));

      final assignee = await userServiceA.getUser(task.assignedUserId!);
      expect(assignee.id, equals(createdUserA.id));
      expect(assignee.name, equals(userAName));
      expect(assignee.email, equals(userAEmail));
    });

    test('20. Logout User A', () async {
      await authProviderA.logout();
      expect(authProviderA.isAuthenticated, isFalse);
      expect(await tokenStorageA.hasToken(), isFalse);
    });

    test('21. Verify protected user/team APIs reject unauthenticated requests', () async {
      expect(
        () async => await userServiceA.getUsers(),
        throwsA(isA<ApiException>()),
      );
      expect(
        () async => await userServiceA.getCurrentUser(),
        throwsA(isA<ApiException>()),
      );
    });

    test('22. Login again with User A credentials', () async {
      final success = await authProviderA.login(userAEmail, userAPassword);
      expect(success, isTrue);
      expect(authProviderA.isAuthenticated, isTrue);
    });

    test('23. Verify task assignment persists from PostgreSQL after re-login', () async {
      final task = await taskServiceA.getTask(createdTaskId);
      expect(task.assignedUserId, equals(createdUserA.id));
      expect(task.title, equals('Cross-Team Assignment Task $testRunId'));
    });

    test('24. Verify existing task workflows still work (record attempt & lifecycle transitions)', () async {
      // Record Attempt
      final taskAfterAttempt = await taskServiceA.recordAttempt(
        createdTaskId,
        notes: 'Testing attempt workflow with assignment',
      );
      expect(taskAfterAttempt.attemptCount, equals(1));

      // Change Priority
      final highTask = await taskServiceA.changePriority(createdTaskId, priority: 'urgent');
      expect(highTask.priority, equals('urgent'));

      // Complete Task
      final completed = await taskServiceA.completeTask(createdTaskId);
      expect(completed.isCompleted, isTrue);
      expect(completed.status, equals('completed'));

      // Reopen Task
      final reopened = await taskServiceA.reopenTask(createdTaskId, reason: 'Testing reopen after assignment');
      expect(reopened.status, equals('pending'));
      expect(reopened.assignedUserId, equals(createdUserA.id));
    });
  });
}
