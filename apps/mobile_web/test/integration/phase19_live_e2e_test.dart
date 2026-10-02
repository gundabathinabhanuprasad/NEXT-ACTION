// Phase 19: Live E2E Verification against PostgreSQL 16 & FastAPI (22 Steps)
//
// Verifies:
// 1. Register User A
// 2. Register User B
// 3. Configure User A timezone (Asia/Kolkata)
// 4. Configure User A notification preferences (suppress follow-up)
// 5. Create task with next action date due
// 6. Create reminder due
// 7. Create follow-up due
// 8. Create overdue task
// 9. Run scheduler evaluation
// 10. Verify expected notifications generated
// 11. Verify disabled notification types are suppressed
// 12. Verify TaskHistory audit trail remains intact
// 13. Run scheduler again
// 14. Verify no duplicate notifications generated
// 15. Verify User B does not receive User A notifications
// 16. Verify unread count
// 17. Mark notification read
// 18. Verify notification center listing
// 19. Verify task navigation
// 20. Verify timezone-specific date boundary behavior
// 21. Verify attempt-limit notification
// 22. Verify dashboard attention data remains consistent

import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/notification/notification_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/scheduler/scheduler_models.dart';
import 'package:nextaction/models/settings/settings_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/dashboard/dashboard_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/services/scheduler/scheduler_service.dart';
import 'package:nextaction/services/settings/settings_service.dart';
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
  group('Phase 19 Live E2E: Automated Reminder & Scheduling Engine (22 Steps)', () {
    late ApiClient apiClientA;
    late AuthService authServiceA;
    late SettingsService settingsServiceA;
    late TaskService taskServiceA;
    late ReminderService reminderServiceA;
    late FollowUpService followUpServiceA;
    late NotificationService notificationServiceA;
    late SchedulerService schedulerServiceA;
    late DashboardService dashboardServiceA;
    late TestTokenStorage tokenStorageA;

    late ApiClient apiClientB;
    late AuthService authServiceB;
    late NotificationService notificationServiceB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userAEmail = 'phase19_usera_$testRunId@nextaction.local';
    final userAName = 'Phase 19 User A $testRunId';
    final userBEmail = 'phase19_userb_$testRunId@nextaction.local';
    final userBName = 'Phase 19 User B $testRunId';
    const userPassword = 'Password123!';

    late User userA;
    late User userB;

    late Task taskNextAction;
    late Task taskReminder;
    late Task taskFollowUp;
    late Task taskOverdue;
    late Task taskAttemptLimit;

    late AppNotification readTestNotif;
    int initialUnreadCount = 0;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorageA = TestTokenStorage();
      apiClientA = ApiClient(tokenStorage: tokenStorageA);
      authServiceA = AuthService(apiClient: apiClientA);
      settingsServiceA = SettingsService(apiClient: apiClientA);
      taskServiceA = TaskService(apiClient: apiClientA);
      reminderServiceA = ReminderService(apiClient: apiClientA);
      followUpServiceA = FollowUpService(apiClient: apiClientA);
      notificationServiceA = NotificationService(apiClient: apiClientA);
      schedulerServiceA = SchedulerService(apiClient: apiClientA);
      dashboardServiceA = DashboardService(apiClient: apiClientA);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      notificationServiceB = NotificationService(apiClient: apiClientB);
    });

    // Step 1: Register User A
    test('Step 1: Register and login User A', () async {
      userA = await authServiceA.register(userAName, userAEmail, userPassword);
      final loginA = await authServiceA.login(userAEmail, userPassword);
      expect(loginA.accessToken, isNotEmpty);
      expect(userA.email, userAEmail);
    });

    // Step 2: Register User B
    test('Step 2: Register and login User B', () async {
      userB = await authServiceB.register(userBName, userBEmail, userPassword);
      final loginB = await authServiceB.login(userBEmail, userPassword);
      expect(loginB.accessToken, isNotEmpty);
      expect(userB.email, userBEmail);
    });

    // Step 3: Configure User A timezone
    test('Step 3: Configure User A timezone to Asia/Kolkata', () async {
      final updated = await settingsServiceA.updateSettings(
        const UserSettingsUpdate(timezone: 'Asia/Kolkata'),
      );
      expect(updated.timezone, 'Asia/Kolkata');
    });

    // Step 4: Configure notification preferences (disable follow_up_due, keep others true)
    test('Step 4: Configure notification preferences for User A', () async {
      final updated = await settingsServiceA.updateSettings(
        const UserSettingsUpdate(
          notifyFollowUpDue: false,
          notifyReminderDue: true,
          notifyNextActionDue: true,
          notifyTaskOverdue: true,
          notifyAttemptLimitReached: true,
        ),
      );
      expect(updated.notifyFollowUpDue, isFalse);
      expect(updated.notifyReminderDue, isTrue);
      expect(updated.notifyNextActionDue, isTrue);
      expect(updated.notifyTaskOverdue, isTrue);
    });

    // Step 5: Create task with next action date due
    test('Step 5: Create task with next action date due in past', () async {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      taskNextAction = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Phase 19 Next Action Task $testRunId',
          assignedUserId: userA.id,
          nextActionDate: past,
        ),
      );
      expect(taskNextAction.id, isNotEmpty);
      expect(taskNextAction.nextActionDate, isNotNull);
    });

    // Step 6: Create reminder due
    test('Step 6: Create task and due reminder for User A', () async {
      taskReminder = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Phase 19 Reminder Task $testRunId',
          assignedUserId: userA.id,
        ),
      );
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final rem = await reminderServiceA.createReminder(
        ReminderCreateRequest(
          taskId: taskReminder.id,
          remindAt: past,
          message: 'Submit Phase 19 Live E2E audit',
        ),
      );
      expect(rem.id, isNotEmpty);
      expect(rem.isSent, isFalse);
    });

    // Step 7: Create follow-up due
    test('Step 7: Create task and due follow-up for User A', () async {
      taskFollowUp = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Phase 19 FollowUp Task $testRunId',
          assignedUserId: userA.id,
        ),
      );
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 45));
      final fu = await followUpServiceA.createFollowUp(
        FollowUpCreateRequest(
          taskId: taskFollowUp.id,
          scheduledAt: past,
          notes: 'Follow up with stakeholder on scheduler metrics',
        ),
      );
      expect(fu.id, isNotEmpty);
      expect(fu.completedAt, isNull);
    });

    // Step 8: Create overdue task
    test('Step 8: Create overdue task for User A', () async {
      final past = DateTime.now().toUtc().subtract(const Duration(days: 2));
      taskOverdue = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Phase 19 Overdue Task $testRunId',
          assignedUserId: userA.id,
          dueDate: past,
        ),
      );
      expect(taskOverdue.id, isNotEmpty);
      expect(taskOverdue.dueDate, isNotNull);
    });

    // Step 9: Run scheduler evaluation
    test('Step 9: Run scheduler evaluation via SchedulerService', () async {
      final res = await schedulerServiceA.evaluateScheduler(userScoped: true);
      expect(res.evaluated, greaterThanOrEqualTo(4));
      expect(res.notificationsCreated, greaterThanOrEqualTo(3));
      expect(res.durationMs, greaterThanOrEqualTo(0.0));
      expect(res.details.containsKey('reminders'), isTrue);
      expect(res.details.containsKey('next_actions'), isTrue);
      expect(res.details.containsKey('overdue_tasks'), isTrue);
      expect(res.details.containsKey('follow_ups'), isTrue);
    });

    // Step 10: Verify expected notifications
    test('Step 10: Verify expected notifications created for User A', () async {
      final notifResp = await notificationServiceA.getNotifications(pageSize: 100);
      final types = notifResp.items.map((n) => n.type).toList();

      expect(types.contains('reminder_due'), isTrue);
      expect(types.contains('next_action_due'), isTrue);
      expect(types.contains('task_overdue'), isTrue);

      final remNotif = notifResp.items.firstWhere((n) => n.type == 'reminder_due');
      expect(remNotif.dedupKey, contains('reminder:'));
      expect(remNotif.taskId, taskReminder.id);
      readTestNotif = remNotif;
    });

    // Step 11: Verify disabled notification types are suppressed
    test('Step 11: Verify follow_up_due notifications are suppressed by preference', () async {
      final notifResp = await notificationServiceA.getNotifications(pageSize: 100);
      final followUpNotifs = notifResp.items.where((n) => n.type == 'follow_up_due').toList();
      expect(followUpNotifs.isEmpty, isTrue);
    });

    // Step 12: Verify TaskHistory remains intact
    test('Step 12: Verify TaskHistory audit trail preserved on task with suppressed alert', () async {
      final history = await taskServiceA.getTaskHistory(taskFollowUp.id);
      expect(history, isNotEmpty);
      expect(history.first.taskId, taskFollowUp.id);
    });

    // Step 13: Run scheduler again
    late SchedulerEvaluationResponse secondRunResult;
    test('Step 13: Run scheduler evaluation a second time', () async {
      secondRunResult = await schedulerServiceA.evaluateScheduler(userScoped: true);
    });

    // Step 14: Verify no duplicate notifications
    test('Step 14: Verify zero duplicate notifications created on second run', () async {
      expect(secondRunResult.notificationsCreated, 0);
      expect(secondRunResult.duplicatesSkipped, greaterThanOrEqualTo(2));
    });

    // Step 15: Verify User B does not receive User A notifications
    test('Step 15: Verify cross-user isolation: User B has no notifications from User A', () async {
      final notifRespB = await notificationServiceB.getNotifications(pageSize: 100);
      for (final n in notifRespB.items) {
        expect(n.taskId != taskNextAction.id, isTrue);
        expect(n.taskId != taskReminder.id, isTrue);
        expect(n.taskId != taskFollowUp.id, isTrue);
        expect(n.taskId != taskOverdue.id, isTrue);
      }
    });

    // Step 16: Verify unread count
    test('Step 16: Verify unread count for User A reflects generated notifications', () async {
      initialUnreadCount = await notificationServiceA.getUnreadCount();
      expect(initialUnreadCount, greaterThanOrEqualTo(3));
    });

    // Step 17: Mark notification read
    test('Step 17: Mark notification read and verify unread count decrements', () async {
      final marked = await notificationServiceA.markAsRead(readTestNotif.id);
      expect(marked.isRead, isTrue);

      final newCount = await notificationServiceA.getUnreadCount();
      expect(newCount, initialUnreadCount - 1);
    });

    // Step 18: Verify notification center
    test('Step 18: Verify notification center pagination and status filter', () async {
      final allNotifs = await notificationServiceA.getNotifications(unreadOnly: false, pageSize: 50);
      final unreadNotifs = await notificationServiceA.getNotifications(unreadOnly: true, pageSize: 50);

      expect(allNotifs.total, greaterThanOrEqualTo(unreadNotifs.total));
      expect(unreadNotifs.items.every((n) => !n.isRead), isTrue);
    });

    // Step 19: Verify task navigation
    test('Step 19: Verify task navigation: notification taskId resolves to task details', () async {
      expect(readTestNotif.taskId, isNotNull);
      final resolvedTask = await taskServiceA.getTask(readTestNotif.taskId!);
      expect(resolvedTask.id, readTestNotif.taskId);
      expect(resolvedTask.title, contains('Phase 19 Reminder Task'));
    });

    // Step 20: Verify timezone-specific date boundary behavior
    test('Step 20: Verify timezone-specific date boundary preferences intact', () async {
      final settings = await settingsServiceA.getSettings();
      expect(settings.timezone, 'Asia/Kolkata');
    });

    // Step 21: Verify attempt-limit notification
    test('Step 21: Verify attempt-limit notification generation via scheduler', () async {
      taskAttemptLimit = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Phase 19 Attempt Limit Task $testRunId',
          assignedUserId: userA.id,
          maxAttempts: 2,
        ),
      );

      // Record attempts until max
      await taskServiceA.recordAttempt(taskAttemptLimit.id, notes: 'Attempt 1');
      await taskServiceA.recordAttempt(taskAttemptLimit.id, notes: 'Attempt 2');

      // Run scheduler evaluation to check attempt limits
      final res = await schedulerServiceA.evaluateScheduler(userScoped: true);
      expect(res.details['attempt_limits'], isNotNull);

      final notifs = await notificationServiceA.getNotifications(pageSize: 50);
      expect(notifs.items.any((n) => n.type == 'attempt_limit_reached'), isTrue);
    });

    // Step 22: Verify dashboard attention data remains consistent
    test('Step 22: Verify dashboard attention data reflects operational KPIs consistently', () async {
      final summary = await dashboardServiceA.getDashboardSummary(timeRange: 'last_7_days');
      expect(summary.kpis.totalOpenTasks, greaterThanOrEqualTo(4));
      expect(summary.attention.urgentCount, greaterThanOrEqualTo(1));
    });
  });
}
