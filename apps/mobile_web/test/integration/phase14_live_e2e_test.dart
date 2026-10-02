import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/notification/notification_models.dart';
import 'package:nextaction/models/recurring/recurring_task_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/template/task_template_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/recurring/recurring_task_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/template/task_template_service.dart';
import 'package:nextaction/services/workflow/workflow_service.dart';

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
  group('Phase 14 Live End-to-End Task Templates, Recurring Tasks & Workflow Automation (22 Steps)', () {
    // Primary User Services
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late ClientService clientService;
    late WorkflowService workflowService;
    late NotificationService notificationService;
    late TaskTemplateService templateService;
    late RecurringTaskService recurringService;
    late TestTokenStorage tokenStorage;

    // Secondary User Services (Cross-user validation)
    late ApiClient apiClientB;
    late AuthService authServiceB;
    late AuthProvider authProviderB;
    late TaskTemplateService templateServiceB;
    late RecurringTaskService recurringServiceB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'template_user_$testRunId@nextaction.local';
    final userName = 'Template Admin $testRunId';
    final userBEmail = 'template_userb_$testRunId@nextaction.local';
    final userBName = 'Template User B $testRunId';
    const userPassword = 'Password123!';

    late User user;
    late User userB;
    late Client client;
    late Workflow workflow;
    late TaskTemplate template;
    late Task taskFromTemplate;
    late RecurringTask dailyRecurrence;
    late Task generatedRecurringTask;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      taskService = TaskService(apiClient: apiClient);
      clientService = ClientService(apiClient: apiClient);
      workflowService = WorkflowService(apiClient: apiClient);
      notificationService = NotificationService(apiClient: apiClient);
      templateService = TaskTemplateService(apiClient: apiClient);
      recurringService = RecurringTaskService(apiClient: apiClient);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      authProviderB = AuthProvider(authService: authServiceB);
      templateServiceB = TaskTemplateService(apiClient: apiClientB);
      recurringServiceB = RecurringTaskService(apiClient: apiClientB);
    });

    test('1. Login: Register and authenticate primary user and secondary user', () async {
      user = (await authProvider.register(userName, userEmail, userPassword))!;
      expect(user.id, isNotEmpty);
      final loggedInA = await authProvider.login(userEmail, userPassword);
      expect(loggedInA, isTrue);
      expect(authProvider.isAuthenticated, isTrue);

      userB = (await authProviderB.register(userBName, userBEmail, userPassword))!;
      expect(userB.id, isNotEmpty);
      final loggedInB = await authProviderB.login(userBEmail, userPassword);
      expect(loggedInB, isTrue);
      expect(authProviderB.isAuthenticated, isTrue);
    });

    test('2. Create client/workflow/user data where needed', () async {
      client = await clientService.createClient(
        ClientCreateRequest(
          name: 'Globex Corp $testRunId',
          company: 'Globex Industries',
          email: 'globex_$testRunId@example.com',
        ),
      );
      expect(client.id, isNotEmpty);

      workflow = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Security Audit Pipeline $testRunId',
          description: 'Recurring enterprise compliance audit',
        ),
      );
      expect(workflow.id, isNotEmpty);
    });

    test('3. Create task template with offset days and default associations', () async {
      template = await templateService.createTemplate(
        name: 'Weekly Client Review Template $testRunId',
        description: 'Conduct weekly review call and sync on deliverables.',
        subjectLine: 'Weekly Client Review with Globex',
        workflowId: workflow.id,
        clientId: client.id,
        assignedUserId: user.id,
        priority: 'high',
        maxAttempts: 3,
        defaultDueOffsetDays: 7,
        defaultNextActionOffsetDays: 2,
        isActive: true,
      );

      expect(template.id, isNotEmpty);
      expect(template.name, contains('Weekly Client Review Template'));
      expect(template.priority, 'high');
      expect(template.maxAttempts, 3);
      expect(template.defaultDueOffsetDays, 7);
      expect(template.defaultNextActionOffsetDays, 2);
    });

    test('4. View template: Retrieve single template and verify in list', () async {
      final fetched = await templateService.getTemplate(template.id);
      expect(fetched.id, template.id);
      expect(fetched.name, template.name);

      final listResponse = await templateService.getTemplates(search: template.name);
      expect(listResponse.items.any((t) => t.id == template.id), isTrue);
      expect(listResponse.total, greaterThanOrEqualTo(1));
    });

    test('5. Edit template: Update properties and verify changes', () async {
      final updated = await templateService.updateTemplate(
        templateId: template.id,
        name: 'Updated Weekly Client Review Template $testRunId',
        priority: 'urgent',
      );

      expect(updated.name, contains('Updated Weekly Client Review Template'));
      expect(updated.priority, 'urgent');
      template = updated;
    });

    test('6. Create task from template: Instantiate concrete task with offsets and overrides', () async {
      taskFromTemplate = await templateService.createTaskFromTemplate(
        templateId: template.id,
        title: 'Concrete Review Instance for Globex $testRunId',
      );

      expect(taskFromTemplate.id, isNotEmpty);
      expect(taskFromTemplate.title, contains('Concrete Review Instance'));
      expect(taskFromTemplate.priority, 'urgent'); // inherited from updated template
      expect(taskFromTemplate.maxAttempts, 3);
      expect(taskFromTemplate.templateId, template.id);
      expect(taskFromTemplate.clientId, client.id);
      expect(taskFromTemplate.workflowId, workflow.id);
    });

    test('7. Verify generated task: Exists in task repository with proper status', () async {
      final fetchedTask = await taskService.getTask(taskFromTemplate.id);
      expect(fetchedTask.id, taskFromTemplate.id);
      expect(fetchedTask.status, 'pending');
      expect(fetchedTask.attemptCount, 0);
      expect(fetchedTask.dueDate, isNotNull); // Computed from defaultDueOffsetDays
      expect(fetchedTask.nextActionDate, isNotNull); // Computed from defaultNextActionOffsetDays
    });

    test('8. Verify task history: Contains creation audit log noting template instantiation', () async {
      final history = await taskService.getTaskHistory(taskFromTemplate.id);
      expect(history, isNotEmpty);
      expect(history.any((h) => h.action == 'created' || h.action == 'created_from_template'), isTrue);
    });

    test('9. Verify template source: templateId is persisted and traceable', () async {
      final fetchedTask = await taskService.getTask(taskFromTemplate.id);
      expect(fetchedTask.templateId, template.id);
      expect(fetchedTask.isFromTemplate, isTrue);
      expect(fetchedTask.recurringTaskId, isNull);
    });

    test('10. Create daily recurrence: Schedule starting today or in past for immediate due trigger', () async {
      final pastStart = DateTime.now().toUtc().subtract(const Duration(hours: 1));

      dailyRecurrence = await recurringService.createRecurringTask(
        name: 'Daily Invoice Follow-up Schedule $testRunId',
        description: 'Daily recurring sweeps for billing',
        startDate: pastStart,
        templateId: template.id,
        clientId: client.id,
        workflowId: workflow.id,
        assignedUserId: user.id,
        priority: 'medium',
        maxAttempts: 2,
        recurrenceType: 'daily',
        interval: 1,
        dueOffsetDays: 1,
        nextActionOffsetDays: 1,
        isActive: true,
      );

      expect(dailyRecurrence.id, isNotEmpty);
      expect(dailyRecurrence.recurrenceType, 'daily');
      expect(dailyRecurrence.interval, 1);
      expect(dailyRecurrence.nextRunAt.isBefore(DateTime.now().toUtc().add(const Duration(seconds: 5))), isTrue);
    });

    test('11. Evaluate recurrence: Execute controlled bounded batch evaluation', () async {
      final evalResult = await recurringService.evaluateRecurringTasks(maxEvaluations: 50);
      expect(evalResult.evaluatedDefinitions, greaterThanOrEqualTo(1));
      expect(evalResult.tasksCreated, greaterThanOrEqualTo(1));
      expect(evalResult.createdTasks, isNotEmpty);

      generatedRecurringTask = evalResult.createdTasks.firstWhere(
        (t) => t.recurringTaskId == dailyRecurrence.id,
      );
      expect(generatedRecurringTask.id, isNotEmpty);
    });

    test('12. Verify exactly one task generated: Matches the evaluated recurrence definition', () async {
      final task = await taskService.getTask(generatedRecurringTask.id);
      expect(task.recurringTaskId, dailyRecurrence.id);
      expect(task.title, contains('Daily Invoice Follow-up Schedule'));
    });

    test('13. Evaluate again immediately: Test duplicate prevention idempotency', () async {
      final secondEval = await recurringService.evaluateRecurringTasks(maxEvaluations: 50);
      // Since next_run_at advanced to tomorrow, 0 new tasks should be created for this recurrence
      final newlyCreatedForRec = secondEval.createdTasks.where(
        (t) => t.recurringTaskId == dailyRecurrence.id,
      );
      expect(newlyCreatedForRec, isEmpty);
    });

    test('14. Verify no duplicate: Check task count for this recurring task', () async {
      final allTasks = await taskService.getTasks(pageSize: 100);
      final matchingTasks = allTasks.items.where((t) => t.recurringTaskId == dailyRecurrence.id).toList();
      expect(matchingTasks.length, 1);
    });

    test('15. Advance/trigger another occurrence: Update next_run_at into past and evaluate', () async {
      // Simulate passage of time by setting next_run_at to past
      final pastNextRun = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      await recurringService.updateRecurringTask(
        recurringTaskId: dailyRecurrence.id,
        nextRunAt: pastNextRun,
      );

      // Now evaluate again
      final advanceEval = await recurringService.evaluateRecurringTasks(maxEvaluations: 50);
      expect(advanceEval.tasksCreated, greaterThanOrEqualTo(1));
    });

    test('16. Verify next task generated: Exactly 2 task instances now exist', () async {
      final allTasks = await taskService.getTasks(pageSize: 100);
      final matchingTasks = allTasks.items.where((t) => t.recurringTaskId == dailyRecurrence.id).toList();
      expect(matchingTasks.length, 2);
    });

    test('17. Verify source traceability: Both tasks have recurringTaskId and audit logs', () async {
      final allTasks = await taskService.getTasks(pageSize: 100);
      final matchingTasks = allTasks.items.where((t) => t.recurringTaskId == dailyRecurrence.id).toList();
      for (final t in matchingTasks) {
        expect(t.recurringTaskId, dailyRecurrence.id);
        expect(t.isFromRecurrence, isTrue);

        final hist = await taskService.getTaskHistory(t.id);
        expect(hist.any((h) => h.action == 'created' || h.action == 'generated_from_recurrence'), isTrue);
      }
    });

    test('18. Verify assignment notification where applicable', () async {
      final notifs = await notificationService.getNotifications();
      expect(notifs.items, isA<List<AppNotification>>());
    });

    test('19. Verify existing reminders/follow-ups still work on generated tasks', () async {
      final remDate = DateTime.now().toUtc().add(const Duration(hours: 3));
      final rem = await taskService.createReminder(
        ReminderCreateRequest(
          taskId: taskFromTemplate.id,
          remindAt: remDate,
          message: 'Template reminder test',
        ),
      );
      expect(rem.id, isNotEmpty);
      expect(rem.taskId, taskFromTemplate.id);

      final fuDate = DateTime.now().toUtc().add(const Duration(days: 1));
      final fu = await taskService.createFollowUp(
        FollowUpCreateRequest(
          taskId: taskFromTemplate.id,
          scheduledAt: fuDate,
          notes: 'Check in on template-created task',
        ),
      );
      expect(fu.id, isNotEmpty);
      expect(fu.taskId, taskFromTemplate.id);
    });

    test('20. Verify search/filter still finds generated tasks by keyword', () async {
      final searchResult = await taskService.getTasks(
        search: 'Concrete Review Instance',
      );
      expect(searchResult.items.any((t) => t.id == taskFromTemplate.id), isTrue);
    });

    test('21. Verify unauthorized user cannot access or modify another user\'s template or recurrence', () async {
      // User B tries to update User A's template -> must fail with 403 or 404
      expect(
        () => templateServiceB.updateTemplate(
          templateId: template.id,
          name: 'Hacked Template Name',
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode == 403 || e.statusCode == 404,
          'status code',
          true,
        )),
      );

      // User B tries to delete User A's template -> must fail
      expect(
        () => templateServiceB.deleteTemplate(template.id),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode == 403 || e.statusCode == 404,
          'status code',
          true,
        )),
      );

      // User B tries to update User A's recurring task -> must fail with 403 or 404
      expect(
        () => recurringServiceB.updateRecurringTask(
          recurringTaskId: dailyRecurrence.id,
          name: 'Hacked Recurring Task Name',
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode == 403 || e.statusCode == 404,
          'status code',
          true,
        )),
      );

      // User B tries to delete User A's recurring task -> must fail
      expect(
        () => recurringServiceB.deleteRecurringTask(dailyRecurrence.id),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode == 403 || e.statusCode == 404,
          'status code',
          true,
        )),
      );
    });

    test('22. Verify existing task functionality remains intact (state machine, attempts, complete)', () async {
      // Transition taskFromTemplate to in_progress
      final inProgress = await taskService.changeStatus(
        taskFromTemplate.id,
        status: 'in_progress',
      );
      expect(inProgress.status, 'in_progress');

      // Record attempt
      final attempted = await taskService.recordAttempt(
        taskFromTemplate.id,
        notes: 'Live test attempt on template task',
      );
      expect(attempted.attemptCount, 1);

      // Complete task
      final completed = await taskService.completeTask(taskFromTemplate.id);
      expect(completed.status, 'completed');
      expect(completed.isCompleted, isTrue);
    });
  });
}
