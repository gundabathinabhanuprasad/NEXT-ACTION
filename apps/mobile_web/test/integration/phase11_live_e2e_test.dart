import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/user/user_service.dart';
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
  group('Phase 11 Live End-to-End Reminders, Follow-ups & Action Scheduling (23 Steps)', () {
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late UserService userService;
    late ClientService clientService;
    late WorkflowService workflowService;
    late ReminderService reminderService;
    late FollowUpService followUpService;
    late TestTokenStorage tokenStorage;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'scheduler_$testRunId@nextaction.local';
    final userName = 'Scheduling Agent $testRunId';
    const userPassword = 'Password123!';

    late User authenticatedUser;
    late Client createdClient;
    late Workflow createdWorkflow;
    late Task createdTask;
    late Reminder createdReminder;
    late FollowUp createdFollowUp;

    final baseTime = DateTime.now().toUtc();
    final todayLocal = DateTime.now();

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      taskService = TaskService(apiClient: apiClient);
      userService = UserService(apiClient: apiClient);
      clientService = ClientService(apiClient: apiClient);
      workflowService = WorkflowService(apiClient: apiClient);
      reminderService = ReminderService(apiClient: apiClient);
      followUpService = FollowUpService(apiClient: apiClient);
    });

    test('1. Login: Register and authenticate user against PostgreSQL', () async {
      final user = await authProvider.register(userName, userEmail, userPassword);
      expect(user, isNotNull);
      expect(user!.email, equals(userEmail));
      authenticatedUser = user;

      final loginSuccess = await authProvider.login(userEmail, userPassword);
      expect(loginSuccess, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(await tokenStorage.hasToken(), isTrue);

      final me = await userService.getCurrentUser();
      expect(me.id, equals(authenticatedUser.id));

      // Create supporting client and workflow
      createdClient = await clientService.createClient(ClientCreateRequest(
        name: 'Enterprise Scheduling Client $testRunId',
        company: 'Scheduler Corp',
      ));
      expect(createdClient.id, isNotEmpty);

      createdWorkflow = await workflowService.createWorkflow(WorkflowCreateRequest(
        name: 'Action Scheduling Pipeline $testRunId',
        description: 'End-to-End scheduling test workflow',
      ));
      expect(createdWorkflow.id, isNotEmpty);
    });

    test('2. Open Next Actions: Query tasks with next action dates', () async {
      final response = await taskService.getTasks(hasNextAction: true);
      expect(response, isNotNull);
      expect(response.items, isA<List<Task>>());
    });

    test('3. Verify real tasks appear: Create base task and query list', () async {
      createdTask = await taskService.createTask(TaskCreateRequest(
        title: 'Phase 11 Production Scheduling Task $testRunId',
        description: 'Testing full lifecycle scheduling invariants',
        clientId: createdClient.id,
        workflowId: createdWorkflow.id,
        assignedUserId: authenticatedUser.id,
        priority: 'high',
        status: 'in_progress',
      ));
      expect(createdTask.id, isNotEmpty);
      expect(createdTask.attemptCount, equals(0));
      expect(createdTask.maxAttempts, equals(2));
      expect(createdTask.status, equals('in_progress'));
      expect(createdTask.nextActionDate, isNull);
    });

    test('4. Create a next action date on the task', () async {
      final scheduledNextAction = DateTime.utc(todayLocal.year, todayLocal.month, todayLocal.day, 14, 0, 0);
      final updated = await taskService.updateNextActionDate(
        createdTask.id,
        nextActionDate: scheduledNextAction,
      );
      expect(updated.id, equals(createdTask.id));
      expect(updated.nextActionDate, isNotNull);
      createdTask = updated;
    });

    test('5. Verify task appears in correct next action section', () async {
      final nextActionTasks = await taskService.getTasks(hasNextAction: true);
      final found = nextActionTasks.items.firstWhere((t) => t.id == createdTask.id);
      expect(found.id, equals(createdTask.id));
      expect(found.nextActionDate, isNotNull);
      expect(found.assignedUserId, equals(authenticatedUser.id));
    });

    test('6. Create reminder for task', () async {
      final remindTime = baseTime.add(const Duration(hours: 3));
      createdReminder = await reminderService.createReminder(ReminderCreateRequest(
        taskId: createdTask.id,
        remindAt: remindTime,
        message: 'Reminder: Verify production deliverables for $testRunId',
      ));
      expect(createdReminder.id, isNotEmpty);
      expect(createdReminder.taskId, equals(createdTask.id));
      expect(createdReminder.isSent, isFalse);
      expect(createdReminder.message, contains(testRunId.toString()));
    });

    test('7. Verify reminder appears in task reminders list', () async {
      final taskReminders = await reminderService.getTaskReminders(createdTask.id);
      expect(taskReminders.any((r) => r.id == createdReminder.id), isTrue);
      final found = taskReminders.firstWhere((r) => r.id == createdReminder.id);
      expect(found.message, equals(createdReminder.message));
      expect(found.isSent, isFalse);
    });

    test('8. Send reminder', () async {
      final sent = await reminderService.sendReminder(createdReminder.id);
      expect(sent.id, equals(createdReminder.id));
      expect(sent.isSent, isTrue);
      createdReminder = sent;
    });

    test('9. Verify reminder status in database', () async {
      final fetched = await reminderService.getReminder(createdReminder.id);
      expect(fetched.id, equals(createdReminder.id));
      expect(fetched.isSent, isTrue);
    });

    test('10. Verify attempt_count invariant after reminder creation and sending', () async {
      final refreshedTask = await taskService.getTask(createdTask.id);
      expect(refreshedTask.attemptCount, equals(0), reason: 'Reminder must NEVER increment attempt_count');
      expect(refreshedTask.maxAttempts, equals(2), reason: 'Reminder must NEVER change max_attempts');
      expect(refreshedTask.status, equals('in_progress'), reason: 'Reminder must NEVER change task status');
      createdTask = refreshedTask;
    });

    test('11. Create follow-up for task', () async {
      final scheduledFollowUp = baseTime.add(const Duration(days: 2));
      createdFollowUp = await followUpService.createFollowUp(FollowUpCreateRequest(
        taskId: createdTask.id,
        scheduledAt: scheduledFollowUp,
        notes: 'Follow up on architecture agreement with stakeholder',
      ));
      expect(createdFollowUp.id, isNotEmpty);
      expect(createdFollowUp.taskId, equals(createdTask.id));
      expect(createdFollowUp.isCompleted, isFalse);
      expect(createdFollowUp.notes, equals('Follow up on architecture agreement with stakeholder'));
    });

    test('12. Verify follow-up appears in task follow-ups list', () async {
      final list = await followUpService.getTaskFollowUps(createdTask.id);
      expect(list.any((f) => f.id == createdFollowUp.id), isTrue);
      final found = list.firstWhere((f) => f.id == createdFollowUp.id);
      expect(found.isCompleted, isFalse);
    });

    test('13. Complete follow-up with confirmation notes', () async {
      final completed = await followUpService.completeFollowUp(
        createdFollowUp.id,
        notes: 'Stakeholder meeting completed successfully; greenlit for rollout.',
      );
      expect(completed.id, equals(createdFollowUp.id));
      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect(completed.notes, contains('greenlit'));
      createdFollowUp = completed;
    });

    test('14. Verify follow-up completion in database', () async {
      final fetched = await followUpService.getFollowUp(createdFollowUp.id);
      expect(fetched.id, equals(createdFollowUp.id));
      expect(fetched.isCompleted, isTrue);
      expect(fetched.completedAt, isNotNull);
    });

    test('15. Verify task was not automatically completed and attempt_count was preserved', () async {
      final refreshedTask = await taskService.getTask(createdTask.id);
      expect(refreshedTask.status, equals('in_progress'), reason: 'Follow-up completion must NOT complete parent task');
      expect(refreshedTask.attemptCount, equals(0), reason: 'Follow-up operations must NEVER alter task attempt_count');
      expect(refreshedTask.maxAttempts, equals(2));
      createdTask = refreshedTask;
    });

    test('16. Open dashboard data', () async {
      final dashboardTasks = await taskService.getTasks(page: 1, pageSize: 100);
      expect(dashboardTasks.items.any((t) => t.id == createdTask.id), isTrue);
    });

    test('17. Verify scheduling KPIs on dashboard', () async {
      final allFollowUps = await followUpService.getFollowUps();
      final allReminders = await reminderService.getReminders();
      final nextActionTasks = await taskService.getTasks(hasNextAction: true);

      expect(allFollowUps.any((f) => f.id == createdFollowUp.id), isTrue);
      expect(allReminders.any((r) => r.id == createdReminder.id), isTrue);
      expect(nextActionTasks.items.any((t) => t.id == createdTask.id), isTrue);
    });

    test('18. Open Reminders center', () async {
      final allReminders = await reminderService.getReminders();
      expect(allReminders.isNotEmpty, isTrue);
      final sentReminders = await reminderService.getReminders(isSent: true);
      expect(sentReminders.any((r) => r.id == createdReminder.id), isTrue);
    });

    test('19. Open Follow-ups center', () async {
      final allFollowUps = await followUpService.getFollowUps();
      expect(allFollowUps.isNotEmpty, isTrue);
      final completedFollowUps = await followUpService.getFollowUps(isCompleted: true);
      expect(completedFollowUps.any((f) => f.id == createdFollowUp.id), isTrue);
    });

    test('20. Open task from reminder relationship', () async {
      final reminder = await reminderService.getReminder(createdReminder.id);
      final associatedTask = await taskService.getTask(reminder.taskId);
      expect(associatedTask.id, equals(createdTask.id));
      expect(associatedTask.title, equals(createdTask.title));
    });

    test('21. Open task from follow-up relationship', () async {
      final followUp = await followUpService.getFollowUp(createdFollowUp.id);
      final associatedTask = await taskService.getTask(followUp.taskId);
      expect(associatedTask.id, equals(createdTask.id));
      expect(associatedTask.title, equals(createdTask.title));
    });

    test('22. Refresh application with new client instance', () async {
      final freshApiClient = ApiClient(tokenStorage: tokenStorage);
      final freshTaskService = TaskService(apiClient: freshApiClient);
      final freshReminderService = ReminderService(apiClient: freshApiClient);
      final freshFollowUpService = FollowUpService(apiClient: freshApiClient);

      final task = await freshTaskService.getTask(createdTask.id);
      final reminders = await freshReminderService.getTaskReminders(createdTask.id);
      final followUps = await freshFollowUpService.getTaskFollowUps(createdTask.id);

      expect(task.id, equals(createdTask.id));
      expect(reminders.any((r) => r.id == createdReminder.id), isTrue);
      expect(followUps.any((f) => f.id == createdFollowUp.id), isTrue);
    });

    test('23. Verify all scheduling data persists accurately in PostgreSQL', () async {
      final task = await taskService.getTask(createdTask.id);
      expect(task.nextActionDate, isNotNull);
      expect(task.assignedUserId, equals(authenticatedUser.id));
      expect(task.attemptCount, equals(0));
      expect(task.status, equals('in_progress'));

      final reminder = await reminderService.getReminder(createdReminder.id);
      expect(reminder.isSent, isTrue);
      expect(reminder.message, contains(testRunId.toString()));

      final followUp = await followUpService.getFollowUp(createdFollowUp.id);
      expect(followUp.isCompleted, isTrue);
      expect(followUp.notes, contains('greenlit'));
    });
  });
}
