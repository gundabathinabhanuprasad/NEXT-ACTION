import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
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
  group('Phase 7 Live End-to-End Task Management Workflow Verification', () {
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late TestTokenStorage tokenStorage;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'phase7_user_$testRunId@nextaction.local';
    const testPassword = 'Password123!';
    final testName = 'Phase 7 User $testRunId';
    late String createdTaskId;
    late DateTime originalDueDate;

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

    test('1. Login with credentials and receive JWT', () async {
      final success = await authProvider.login(testEmail, testPassword);
      expect(success, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(await tokenStorage.hasToken(), isTrue);
    });

    test('2. Load task list from real PostgreSQL', () async {
      final taskList = await taskService.getTasks();
      expect(taskList.items, isA<List<Task>>());
    });

    test('3. Create task in PostgreSQL', () async {
      originalDueDate = DateTime.now().add(const Duration(days: 3));
      final request = TaskCreateRequest(
        title: 'Phase 7 Complete Workflow Task ($testRunId)',
        description: 'End-to-end task testing all 25 workflow steps against PostgreSQL',
        subjectLine: 'Phase 7 Spec Workflow',
        priority: 'medium',
        dueDate: originalDueDate,
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

    test('4. Open and retrieve task details by UUID', () async {
      final task = await taskService.getTask(createdTaskId);
      expect(task.id, equals(createdTaskId));
      expect(task.title, contains('Phase 7 Complete Workflow Task'));
      expect(task.subjectLine, equals('Phase 7 Spec Workflow'));
    });

    test('5. Record 1st normal work attempt (count -> 1)', () async {
      final task = await taskService.recordAttempt(createdTaskId, notes: '1st outreach call');
      expect(task.attemptCount, equals(1));
      expect(task.maxAttempts, equals(2));
      expect(task.canAttemptNormally, isTrue);
    });

    test('6. Record 2nd normal work attempt (count -> 2, reaches max)', () async {
      final task = await taskService.recordAttempt(createdTaskId, notes: '2nd outreach call');
      expect(task.attemptCount, equals(2));
      expect(task.hasReachedMaxAttempts, isTrue);
      expect(task.canAttemptNormally, isFalse);
    });

    test('7. Attempt 3rd normal attempt and 8. Verify backend returns 409 MAX_ATTEMPTS_REACHED', () async {
      try {
        await taskService.recordAttempt(createdTaskId, notes: 'Unauthorized 3rd call');
        fail('Should have been rejected with 409 MAX_ATTEMPTS_REACHED');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(409));
        expect(e.errorCode, equals('MAX_ATTEMPTS_REACHED'));
      }
    });

    test('9. Perform authorized override with justification reason and 10. Verify count increases to 3', () async {
      final task = await taskService.recordOverrideAttempt(
        createdTaskId,
        reason: 'Authorized escalation: client requested additional executive outreach',
      );
      expect(task.attemptCount, equals(3));
      expect(task.maxAttempts, equals(2));
    });

    test('11. Postpone task with reason and 12. Verify due date changes', () async {
      final newDueDate = DateTime.now().add(const Duration(days: 7));
      final task = await taskService.postponeTask(
        createdTaskId,
        newDueDate: newDueDate,
        reason: 'Client traveling until next Monday',
      );
      expect(task.dueDate, isNotNull);
      expect(task.dueDate!.day, equals(newDueDate.day));
    });

    test('13. Verify history records postponement and preserves original date', () async {
      final history = await taskService.getTaskHistory(createdTaskId);
      final postponeHist = history.firstWhere((h) => h.action == 'postponed');
      expect(postponeHist.reason, equals('Client traveling until next Monday'));
      expect(postponeHist.oldValue, isNotNull);
      expect(postponeHist.newValue, isNotNull);
    });

    test('14. Change next action date', () async {
      final nextAction = DateTime.now().add(const Duration(days: 2));
      final task = await taskService.updateNextActionDate(
        createdTaskId,
        nextActionDate: nextAction,
      );
      expect(task.nextActionDate, isNotNull);
    });

    test('15. Create reminder and 16. Verify reminder does NOT change attempt count (remains 3)', () async {
      final remindAt = DateTime.now().add(const Duration(hours: 4));
      final reminder = await taskService.createReminder(
        ReminderCreateRequest(
          taskId: createdTaskId,
          remindAt: remindAt,
          message: 'Review client SLA terms',
        ),
      );
      expect(reminder.id, isNotEmpty);
      expect(reminder.isSent, isFalse);

      final task = await taskService.getTask(createdTaskId);
      expect(task.attemptCount, equals(3)); // INVARIANT PRESERVED!

      // Send reminder and verify invariant still holds
      final sent = await taskService.sendReminder(reminder.id);
      expect(sent.isSent, isTrue);

      final taskAfterSend = await taskService.getTask(createdTaskId);
      expect(taskAfterSend.attemptCount, equals(3)); // INVARIANT PRESERVED!
    });

    test('17. Create follow-up and complete follow-up', () async {
      final followUp = await taskService.createFollowUp(
        FollowUpCreateRequest(
          taskId: createdTaskId,
          scheduledAt: DateTime.now().add(const Duration(days: 4)),
          notes: 'Schedule quarterly review follow-up',
        ),
      );
      expect(followUp.id, isNotEmpty);
      expect(followUp.isCompleted, isFalse);

      final completedFollowUp = await taskService.completeFollowUp(
        followUp.id,
        notes: 'Review meeting confirmed',
      );
      expect(completedFollowUp.isCompleted, isTrue);
    });

    test('18. Change priority to URGENT', () async {
      final task = await taskService.changePriority(
        createdTaskId,
        priority: 'urgent',
        reason: 'SLA milestone approaching',
      );
      expect(task.priority, equals('urgent'));
    });

    test('19. Change status to IN_PROGRESS', () async {
      final task = await taskService.changeStatus(
        createdTaskId,
        status: 'in_progress',
        reason: 'Commencing discovery phase',
      );
      expect(task.status, equals('in_progress'));
    });

    test('20. Complete task and 21. Verify completed state & completed_at', () async {
      final task = await taskService.completeTask(createdTaskId);
      expect(task.isCompleted, isTrue);
      expect(task.status, equals('completed'));
      expect(task.completedAt, isNotNull);

      // Verify cannot complete twice
      try {
        await taskService.completeTask(createdTaskId);
        fail('Should reject duplicate completion with 409');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(409));
        expect(e.errorCode, equals('TASK_ALREADY_COMPLETED'));
      }
    });

    test('22. Reopen task with mandatory reason', () async {
      final task = await taskService.reopenTask(
        createdTaskId,
        reason: 'Client requested scope amendment',
      );
      expect(task.isCompleted, isFalse);
      expect(task.status, equals('pending'));
    });

    test('23. Verify complete chronological history in PostgreSQL', () async {
      final history = await taskService.getTaskHistory(createdTaskId);
      final actions = history.map((h) => h.action).toList();

      expect(actions, contains('created'));
      expect(actions, contains('attempt'));
      expect(actions, contains('attempt_override'));
      expect(actions, contains('postponed'));
      expect(actions, contains('completed'));
      expect(actions, contains('reopened'));
      expect(actions, contains('priority_changed'));
    });

    test('24. Refresh application / re-fetch and 25. Verify state persists from PostgreSQL', () async {
      final task = await taskService.getTask(createdTaskId);
      expect(task.id, equals(createdTaskId));
      expect(task.priority, equals('urgent'));
      expect(task.status, equals('pending'));
      expect(task.attemptCount, equals(3));
      expect(task.maxAttempts, equals(2));

      final reminders = await taskService.getTaskReminders(createdTaskId);
      expect(reminders.length, greaterThanOrEqualTo(1));

      final followUps = await taskService.getTaskFollowUps(createdTaskId);
      expect(followUps.length, greaterThanOrEqualTo(1));
    });
  });
}
