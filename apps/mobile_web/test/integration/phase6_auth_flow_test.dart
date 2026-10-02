import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
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

/// End-to-End Live Integration Verification against real FastAPI backend and PostgreSQL.
void main() {
  group('Phase 6 Live End-to-End Flow Verification', () {
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late TestTokenStorage tokenStorage;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'phase6_e2e_$testRunId@nextaction.local';
    const testPassword = 'Password123!';
    final testName = 'E2E User $testRunId';

    setUpAll(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      taskService = TaskService(apiClient: apiClient);
    });

    test('1. Register new user against real FastAPI & PostgreSQL', () async {
      final user = await authProvider.register(testName, testEmail, testPassword);
      expect(user, isNotNull);
      expect(user!.email, equals(testEmail));
      expect(user.name, equals(testName));
      expect(user.isActive, isTrue);
    });

    test('2. Login with credentials and receive JWT', () async {
      final success = await authProvider.login(testEmail, testPassword);
      expect(success, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(await tokenStorage.hasToken(), isTrue);
    });

    test('3. Verify /auth/me returns authoritative user profile', () async {
      final me = await authService.getCurrentUser();
      expect(me.email, equals(testEmail));
      expect(me.name, equals(testName));
      expect(authProvider.currentUser?.id, equals(me.id));
    });

    test('4. Task list loads real items from PostgreSQL', () async {
      final taskList = await taskService.getTasks(page: 1, pageSize: 10);
      expect(taskList.page, equals(1));
      expect(taskList.pageSize, equals(10));
      expect(taskList.items, isA<List<Task>>());
    });

    late String createdTaskId;

    test('5. Task creation succeeds and persists in PostgreSQL', () async {
      final request = TaskCreateRequest(
        title: 'Phase 6 Live Verification Task ($testRunId)',
        description: 'End-to-end integration test task executing against PostgreSQL',
        subjectLine: 'E2E Subject Line',
        priority: 'high',
        dueDate: DateTime.now().add(const Duration(days: 3)),
        maxAttempts: 2,
      );

      final task = await taskService.createTask(request);
      createdTaskId = task.id;

      expect(task.id, isNotEmpty);
      expect(task.title, equals(request.title));
      expect(task.attemptCount, equals(0));
      expect(task.maxAttempts, equals(2));
      expect(task.status, equals('pending'));
    });

    test('6. Task detail retrieves specific task by UUID', () async {
      final task = await taskService.getTask(createdTaskId);
      expect(task.id, equals(createdTaskId));
      expect(task.priority, equals('high'));
      expect(task.subjectLine, equals('E2E Subject Line'));
    });

    test('7. First attempt records successfully and increments attempt_count to 1', () async {
      final task = await taskService.recordAttempt(createdTaskId, notes: 'First test attempt');
      expect(task.attemptCount, equals(1));
      expect(task.maxAttempts, equals(2));
      expect(task.canAttemptNormally, isTrue);
    });

    test('8. Second attempt reaches max attempts (2/2) and third attempt rejected with 409', () async {
      final task2 = await taskService.recordAttempt(createdTaskId, notes: 'Second test attempt');
      expect(task2.attemptCount, equals(2));
      expect(task2.hasReachedMaxAttempts, isTrue);

      // Third normal attempt must be rejected by backend business rules
      try {
        await taskService.recordAttempt(createdTaskId, notes: 'Third unauthorized attempt');
        fail('Should have been rejected with 409 MAX_ATTEMPTS_REACHED');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(409));
        expect(e.errorCode, equals('MAX_ATTEMPTS_REACHED'));
      }
    });

    test('9. Authorized override records attempt 3 with justification', () async {
      final task3 = await taskService.recordOverrideAttempt(
        createdTaskId,
        reason: 'Authorized management override for live integration verification',
      );
      expect(task3.attemptCount, equals(3));
      expect(task3.maxAttempts, equals(2));

      // Verify audit history reflects the actions
      final history = await taskService.getTaskHistory(createdTaskId);
      expect(history.length, greaterThanOrEqualTo(4)); // Created, Attempt 1, Attempt 2, Override Attempt
      expect(history.any((h) => h.action == 'attempt_override' || h.action == 'override_attempt'), isTrue);
    });

    test('10. Logout clears token and invalidates session state', () async {
      await authProvider.logout();
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.currentUser, isNull);
      expect(await tokenStorage.hasToken(), isFalse);

      // Attempting protected API without token throws 401
      expect(
        () async => await taskService.getTasks(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('11. Login again re-establishes session and retrieves user data', () async {
      final loginSuccess = await authProvider.login(testEmail, testPassword);
      expect(loginSuccess, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUser?.email, equals(testEmail));

      final taskList = await taskService.getTasks();
      expect(taskList.items.any((t) => t.id == createdTaskId), isTrue);
    });
  });
}
