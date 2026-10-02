import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/history/task_history_models.dart';
import 'package:nextaction/models/recurring/recurring_task_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/template/task_template_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/recurring/recurring_task_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/template/task_template_service.dart';

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
  group('Phase 15 Live End-to-End Task History, Audit Log & Activity Experience (25 Steps)', () {
    // Primary User Services
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late ClientService clientService;
    late NotificationService notificationService;
    late TaskTemplateService templateService;
    late RecurringTaskService recurringService;
    late TestTokenStorage tokenStorage;

    // Secondary User Services (Cross-user validation)
    late ApiClient apiClientB;
    late AuthService authServiceB;
    late AuthProvider authProviderB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'history_user_$testRunId@nextaction.local';
    final userName = 'History Tester $testRunId';
    final userBEmail = 'history_userb_$testRunId@nextaction.local';
    final userBName = 'History User B $testRunId';
    const userPassword = 'Password123!';

    late User user;
    late User userB;
    late Client client;
    late Task mainTask;
    late TaskTemplate template;
    late Task taskFromTemplate;
    late RecurringTask recurringConfig;
    late Task generatedRecurringTask;
    late List<TaskHistory> fullTimeline;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      taskService = TaskService(apiClient: apiClient);
      clientService = ClientService(apiClient: apiClient);
      notificationService = NotificationService(apiClient: apiClient);
      templateService = TaskTemplateService(apiClient: apiClient);
      recurringService = RecurringTaskService(apiClient: apiClient);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      authProviderB = AuthProvider(authService: authServiceB);
    });

    test('1. Login: Register and authenticate primary user and secondary user', () async {
      user = (await authProvider.register(userName, userEmail, userPassword))!;
      expect(user.id, isNotEmpty);
      final loggedInA = await authProvider.login(userEmail, userPassword);
      expect(loggedInA, isTrue);

      userB = (await authProviderB.register(userBName, userBEmail, userPassword))!;
      expect(userB.id, isNotEmpty);
      final loggedInB = await authProviderB.login(userBEmail, userPassword);
      expect(loggedInB, isTrue);
    });

    test('2. Create a task', () async {
      client = await clientService.createClient(
        ClientCreateRequest(
          name: 'History Client $testRunId',
          email: 'contact@client-$testRunId.local',
        ),
      );

      mainTask = await taskService.createTask(
        TaskCreateRequest(
          title: 'Audit Trail Root Task $testRunId',
          subjectLine: 'Initial subject line',
          priority: 'medium',
          dueDate: DateTime.now().add(const Duration(days: 3)),
          clientId: client.id,
          maxAttempts: 3,
        ),
      );

      expect(mainTask.id, isNotEmpty);
      expect(mainTask.title, equals('Audit Trail Root Task $testRunId'));
      expect(mainTask.status, equals('pending'));
      expect(mainTask.priority, equals('medium'));
    });

    test('3. Assign task', () async {
      mainTask = await taskService.assignTask(mainTask.id, assignedUserId: user.id);
      expect(mainTask.assignedUserId, equals(user.id));
    });

    test('4. Change priority', () async {
      mainTask = await taskService.changePriority(mainTask.id, priority: 'high');
      expect(mainTask.priority, equals('high'));
    });

    test('5. Change status', () async {
      mainTask = await taskService.changeStatus(mainTask.id, status: 'in_progress');
      expect(mainTask.status, equals('in_progress'));
    });

    test('6. Record attempt', () async {
      mainTask = await taskService.recordAttempt(mainTask.id);
      expect(mainTask.attemptCount, equals(1));
    });

    test('7. Postpone task with reason', () async {
      final postponeDate = DateTime.now().add(const Duration(days: 7));
      mainTask = await taskService.postponeTask(
        mainTask.id,
        newDueDate: postponeDate,
        reason: 'Waiting for client confirmation on Phase 15 requirements',
      );
      expect(mainTask.dueDate, isNotNull);
    });

    test('8. Set next action', () async {
      final nextActionDate = DateTime.now().add(const Duration(days: 2));
      mainTask = await taskService.updateNextActionDate(mainTask.id, nextActionDate: nextActionDate);
      expect(mainTask.nextActionDate, isNotNull);
    });

    test('9. Complete task', () async {
      mainTask = await taskService.completeTask(mainTask.id);
      expect(mainTask.isCompleted, isTrue);
      expect(mainTask.status, equals('completed'));
    });

    test('10. Reopen task with reason', () async {
      mainTask = await taskService.reopenTask(
        mainTask.id,
        reason: 'Client provided additional feedback notes',
      );
      expect(mainTask.isCompleted, isFalse);
      expect(mainTask.status, equals('pending'));
    });

    test('11. Create task from template', () async {
      template = await templateService.createTemplate(
        name: 'Review Template $testRunId',
        priority: 'high',
        clientId: client.id,
      );

      taskFromTemplate = await templateService.createTaskFromTemplate(
        templateId: template.id,
        title: 'Created From Template Task $testRunId',
      );

      expect(taskFromTemplate.templateId, equals(template.id));
      expect(taskFromTemplate.isFromTemplate, isTrue);
    });

    test('12. Generate recurring task', () async {
      final pastStart = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      recurringConfig = await recurringService.createRecurringTask(
        name: 'Recurring Audit Test $testRunId',
        templateId: template.id,
        recurrenceType: 'daily',
        interval: 1,
        startDate: pastStart,
      );

      final evalResult = await recurringService.evaluateRecurringTasks(maxEvaluations: 50);
      expect(evalResult.tasksCreated, greaterThanOrEqualTo(1));

      final tasks = await taskService.getTasks(pageSize: 100);
      generatedRecurringTask = tasks.items.firstWhere(
        (t) => t.recurringTaskId == recurringConfig.id,
      );
      expect(generatedRecurringTask.recurringTaskId, equals(recurringConfig.id));
      expect(generatedRecurringTask.isFromRecurrence, isTrue);
    });

    test('13. Open Task Detail / Retrieve task history timeline', () async {
      fullTimeline = await taskService.getTaskHistory(mainTask.id);
      expect(fullTimeline, isNotEmpty);
      expect(fullTimeline.length, greaterThanOrEqualTo(8));
    });

    test('14. Verify timeline contains expected actions', () async {
      final actions = fullTimeline.map((h) => h.action).toSet();
      expect(actions, contains('created'));
      expect(actions, contains('reassigned'));
      expect(actions, contains('priority_changed'));
      expect(actions, contains('status_changed'));
      expect(actions, contains('attempt'));
      expect(actions, contains('postponed'));
      expect(actions, contains('next_action_date_changed'));
      expect(actions, contains('completed'));
      expect(actions, contains('reopened'));
    });

    test('15. Verify actor names', () async {
      for (final item in fullTimeline) {
        expect(item.displayActor, isNotEmpty);
        expect(item.displayActor, equals(userName));
        expect(item.actorEmail, equals(userEmail));
      }
    });

    test('16. Verify timestamps', () async {
      for (final item in fullTimeline) {
        expect(item.createdAt, isNotNull);
        expect(item.createdAt.isBefore(DateTime.now().add(const Duration(minutes: 5))), isTrue);
      }
    });

    test('17. Verify reasons', () async {
      final postponeEvent = fullTimeline.firstWhere((h) => h.action == 'postponed');
      expect(postponeEvent.reason, equals('Waiting for client confirmation on Phase 15 requirements'));

      final reopenEvent = fullTimeline.firstWhere((h) => h.action == 'reopened');
      expect(reopenEvent.reason, equals('Client provided additional feedback notes'));
    });

    test('18. Verify old/new values', () async {
      final priorityEvent = fullTimeline.firstWhere((h) => h.action == 'priority_changed');
      expect(priorityEvent.oldValue, equals('medium'));
      expect(priorityEvent.newValue, equals('high'));
      expect(priorityEvent.formattedAction, equals('Priority changed: MEDIUM → HIGH'));

      final statusEvent = fullTimeline.firstWhere((h) => h.action == 'status_changed');
      expect(statusEvent.oldValue, equals('pending'));
      expect(statusEvent.newValue, equals('in_progress'));
      expect(statusEvent.formattedAction, equals('Status changed: PENDING → IN PROGRESS'));
    });

    test('19. Verify source traceability', () async {
      // Template task history
      final templateTaskHistory = await taskService.getTaskHistory(taskFromTemplate.id);
      expect(templateTaskHistory, isNotEmpty);
      final templateCreatedEvent = templateTaskHistory.firstWhere((h) => h.action == 'created_from_template');
      expect(templateCreatedEvent.formattedAction, equals('Created from template'));
      expect(templateCreatedEvent.actionCategory, equals('creation'));

      // Recurring task history
      final recurringTaskHistory = await taskService.getTaskHistory(generatedRecurringTask.id);
      expect(recurringTaskHistory, isNotEmpty);
      final recurrenceCreatedEvent = recurringTaskHistory.firstWhere((h) => h.action == 'generated_from_recurrence');
      expect(recurrenceCreatedEvent.formattedAction, equals('Generated by recurrence schedule'));
      expect(recurrenceCreatedEvent.actionCategory, equals('creation'));
    });

    test('20. Verify history pagination', () async {
      final page1 = await taskService.getTaskHistory(mainTask.id, page: 1, pageSize: 3);
      final page2 = await taskService.getTaskHistory(mainTask.id, page: 2, pageSize: 3);

      expect(page1.length, equals(3));
      expect(page2.length, equals(3));
      expect(page1.first.id, isNot(equals(page2.first.id)));
    });

    test('21. Verify history filtering', () async {
      final statusOnly = await taskService.getTaskHistory(mainTask.id, action: 'status_changed');
      expect(statusOnly, isNotEmpty);
      for (final h in statusOnly) {
        expect(h.action, equals('status_changed'));
      }

      final postponedOnly = await taskService.getTaskHistory(mainTask.id, action: 'postponed');
      expect(postponedOnly.length, equals(1));
      expect(postponedOnly.first.action, equals('postponed'));
    });

    test('22. Verify unauthorized user cannot access history', () async {
      final unauthenticatedClient = ApiClient(tokenStorage: TestTokenStorage());
      final unauthTaskService = TaskService(apiClient: unauthenticatedClient);

      try {
        await unauthTaskService.getTaskHistory(mainTask.id);
        fail('Unauthenticated access to history should throw ApiException (401)');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
      }

      try {
        await taskService.getTaskHistory('00000000-0000-0000-0000-000000000000');
        fail('Access to non-existent task history should throw ApiException (404)');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(404));
      }
    });

    test('23. Verify refresh preserves history', () async {
      final refreshed = await taskService.getTaskHistory(mainTask.id);
      expect(refreshed.length, equals(fullTimeline.length));
      expect(refreshed.map((h) => h.id).toList(), equals(fullTimeline.map((h) => h.id).toList()));
    });

    test('24. Verify existing Notifications remain functional', () async {
      final notifications = await notificationService.getNotifications(unreadOnly: false);
      expect(notifications.total, greaterThanOrEqualTo(0));
    });

    test('25. Verify existing Search/Filters remain functional and Global Activity endpoint works', () async {
      // 1. Task search
      final searchResults = await taskService.getTasks(search: 'Audit Trail Root Task $testRunId');
      expect(searchResults.items, isNotEmpty);
      expect(searchResults.items.first.id, equals(mainTask.id));

      // 2. Global Activity endpoint
      final activityFeed = await taskService.getActivity(pageSize: 20);
      expect(activityFeed.items, isNotEmpty);
      expect(activityFeed.total, greaterThanOrEqualTo(fullTimeline.length));

      // 3. Global Activity search filter
      final taskActivity = await taskService.getActivity(taskId: mainTask.id);
      expect(taskActivity.items, isNotEmpty);
      for (final item in taskActivity.items) {
        expect(item.taskId, equals(mainTask.id));
      }
    });
  });
}
