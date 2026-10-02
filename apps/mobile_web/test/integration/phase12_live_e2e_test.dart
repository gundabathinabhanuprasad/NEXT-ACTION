import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/notification/notification_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
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
  group('Phase 12 Live End-to-End Notifications, Alerts & Smart Attention System (21 Steps)', () {
    // Services for User A
    late ApiClient apiClientA;
    late AuthService authServiceA;
    late AuthProvider authProviderA;
    late TaskService taskServiceA;
    late UserService userServiceA;
    late ClientService clientServiceA;
    late WorkflowService workflowServiceA;
    late ReminderService reminderServiceA;
    late FollowUpService followUpServiceA;
    late NotificationService notificationServiceA;
    late TestTokenStorage tokenStorageA;

    // Services for User B
    late ApiClient apiClientB;
    late AuthService authServiceB;
    late AuthProvider authProviderB;
    late TaskService taskServiceB;
    late UserService userServiceB;
    late NotificationService notificationServiceB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userAEmail = 'usera_$testRunId@nextaction.local';
    final userAName = 'User Alpha $testRunId';
    final userBEmail = 'userb_$testRunId@nextaction.local';
    final userBName = 'User Beta $testRunId';
    const userPassword = 'Password123!';

    late User userA;
    late User userB;
    late Client createdClient;
    late Workflow createdWorkflow;
    late Task assignedTask;
    late AppNotification userBAssignNotification;
    late Task dueTask;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorageA = TestTokenStorage();
      apiClientA = ApiClient(tokenStorage: tokenStorageA);
      authServiceA = AuthService(apiClient: apiClientA);
      authProviderA = AuthProvider(authService: authServiceA);
      taskServiceA = TaskService(apiClient: apiClientA);
      userServiceA = UserService(apiClient: apiClientA);
      clientServiceA = ClientService(apiClient: apiClientA);
      workflowServiceA = WorkflowService(apiClient: apiClientA);
      reminderServiceA = ReminderService(apiClient: apiClientA);
      followUpServiceA = FollowUpService(apiClient: apiClientA);
      notificationServiceA = NotificationService(apiClient: apiClientA);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      authProviderB = AuthProvider(authService: authServiceB);
      taskServiceB = TaskService(apiClient: apiClientB);
      userServiceB = UserService(apiClient: apiClientB);
      notificationServiceB = NotificationService(apiClient: apiClientB);
    });

    test('1. Login User A: Register and authenticate User A', () async {
      final registered = await authProviderA.register(userAName, userAEmail, userPassword);
      expect(registered, isNotNull);
      userA = registered!;

      final loggedIn = await authProviderA.login(userAEmail, userPassword);
      expect(loggedIn, isTrue);
      expect(authProviderA.isAuthenticated, isTrue);

      final me = await userServiceA.getCurrentUser();
      expect(me.id, equals(userA.id));

      // Setup supporting client and workflow
      createdClient = await clientServiceA.createClient(ClientCreateRequest(
        name: 'Notification Test Client $testRunId',
        company: 'Alert Corp',
      ));
      expect(createdClient.id, isNotEmpty);

      createdWorkflow = await workflowServiceA.createWorkflow(WorkflowCreateRequest(
        name: 'Notification Pipeline $testRunId',
        description: 'Testing live notification events',
      ));
      expect(createdWorkflow.id, isNotEmpty);
    });

    test('2. Create/identify User B: Register and authenticate User B', () async {
      final registered = await authProviderB.register(userBName, userBEmail, userPassword);
      expect(registered, isNotNull);
      userB = registered!;

      final loggedIn = await authProviderB.login(userBEmail, userPassword);
      expect(loggedIn, isTrue);
      expect(authProviderB.isAuthenticated, isTrue);

      final meB = await userServiceB.getCurrentUser();
      expect(meB.id, equals(userB.id));
    });

    test('3. Assign a task to User B: User A creates and assigns a task to User B', () async {
      assignedTask = await taskServiceA.createTask(TaskCreateRequest(
        title: 'Phase 12 Critical Task $testRunId',
        description: 'Assigned from User A to User B',
        priority: 'high',
        assignedUserId: userB.id,
        clientId: createdClient.id,
        workflowId: createdWorkflow.id,
      ));
      expect(assignedTask.id, isNotEmpty);
      expect(assignedTask.assignedUserId, equals(userB.id));
    });

    test('4. Verify User B receives an in-app notification', () async {
      final notifsB = await notificationServiceB.getNotifications();
      expect(notifsB.items, isNotEmpty);

      final assignNotif = notifsB.items.firstWhere(
        (n) => n.taskId == assignedTask.id && n.type == 'task_assigned',
        orElse: () => throw Exception('Assignment notification not found for User B'),
      );
      expect(assignNotif.isRead, isFalse);
      expect(assignNotif.userId, equals(userB.id));
      expect(assignNotif.title, contains('Task Assigned'));
      userBAssignNotification = assignNotif;
    });

    test('5. Verify User A does not see User B\'s private notification', () async {
      final notifsA = await notificationServiceA.getNotifications();
      final leakedNotif = notifsA.items.where((n) => n.id == userBAssignNotification.id);
      expect(leakedNotif, isEmpty);

      // Verify User A cannot fetch User B's notification by ID (IDOR prevention)
      expect(
        () async => await notificationServiceA.getNotification(userBAssignNotification.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('6. Open notification center: User B lists notifications and inspects summary', () async {
      final notifsList = await notificationServiceB.getNotifications(pageSize: 20);
      expect(notifsList.total, greaterThanOrEqualTo(1));
      expect(notifsList.unreadCount, greaterThanOrEqualTo(1));
    });

    test('7. Verify unread badge: Unread count matches pending alerts', () async {
      final unread = await notificationServiceB.getUnreadCount();
      expect(unread, greaterThanOrEqualTo(1));
    });

    test('8. Open notification: User B reads specific notification details', () async {
      final detail = await notificationServiceB.getNotification(userBAssignNotification.id);
      expect(detail.id, equals(userBAssignNotification.id));
      expect(detail.taskId, equals(assignedTask.id));
      expect(detail.message, contains(assignedTask.title));
    });

    test('9. Verify related task opens: Task is retrievable via task service', () async {
      final task = await taskServiceB.getTask(userBAssignNotification.taskId!);
      expect(task.id, equals(assignedTask.id));
      expect(task.title, equals(assignedTask.title));
    });

    test('10. Verify notification becomes read where appropriate', () async {
      final updated = await notificationServiceB.markAsRead(userBAssignNotification.id);
      expect(updated.isRead, isTrue);
      expect(updated.readAt, isNotNull);

      final unreadAfter = await notificationServiceB.getUnreadCount();
      expect(unreadAfter, equals(0));
    });

    late Task userATask;

    test('11. Create reminder: User A creates a task and past-due reminder for background evaluation', () async {
      userATask = await taskServiceA.createTask(TaskCreateRequest(
        title: 'User A Scheduling Task $testRunId',
        description: 'Testing reminders and follow-ups for User A',
        assignedUserId: userA.id,
        clientId: createdClient.id,
        workflowId: createdWorkflow.id,
      ));
      expect(userATask.id, isNotEmpty);

      final pastDueTime = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      final reminder = await reminderServiceA.createReminder(
        ReminderCreateRequest(
          taskId: userATask.id,
          remindAt: pastDueTime,
          message: 'Review architecture spec immediately',
        ),
      );
      expect(reminder.id, isNotEmpty);
    });

    test('12. Trigger/check due notification: Evaluate generates reminder notification', () async {
      final evalResult = await notificationServiceA.evaluateNotifications();
      expect(evalResult.createdCount, greaterThanOrEqualTo(1));

      final notifsA = await notificationServiceA.getNotifications();
      final reminderNotif = notifsA.items.firstWhere(
        (n) => n.type == 'reminder_due' && n.taskId == userATask.id,
        orElse: () => throw Exception('Reminder due notification not generated'),
      );
      expect(reminderNotif.isRead, isFalse);
      expect(reminderNotif.title, contains('Reminder'));
    });

    test('13. Create follow-up: User A creates a past-due follow-up', () async {
      final pastDueTime = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final followUp = await followUpServiceA.createFollowUp(
        FollowUpCreateRequest(
          taskId: userATask.id,
          scheduledAt: pastDueTime,
          notes: 'Follow up with lead architect Jane',
        ),
      );
      expect(followUp.id, isNotEmpty);
    });

    test('14. Trigger/check due notification: Evaluate generates follow-up notification', () async {
      final evalResult = await notificationServiceA.evaluateNotifications();
      expect(evalResult.createdCount, greaterThanOrEqualTo(1));

      final notifsA = await notificationServiceA.getNotifications();
      final followUpNotif = notifsA.items.firstWhere(
        (n) => n.type == 'follow_up_due' && n.taskId == userATask.id,
        orElse: () => throw Exception('Follow-up due notification not generated'),
      );
      expect(followUpNotif.isRead, isFalse);
      expect(followUpNotif.title, contains('Follow-up Due'));
    });

    test('15. Create next action & overdue task for User A', () async {
      final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
      dueTask = await taskServiceA.createTask(TaskCreateRequest(
        title: 'Overdue Milestone Task $testRunId',
        description: 'Task with next action and due date yesterday',
        assignedUserId: userA.id,
        dueDate: yesterday,
        nextActionDate: yesterday,
        clientId: createdClient.id,
        workflowId: createdWorkflow.id,
      ));
      expect(dueTask.id, isNotEmpty);
    });

    test('16. Trigger/check due notification: Evaluate generates next action and overdue alerts', () async {
      final evalResult = await notificationServiceA.evaluateNotifications();
      expect(evalResult.createdCount, greaterThanOrEqualTo(2));

      final notifsA = await notificationServiceA.getNotifications();
      final nextActionNotif = notifsA.items.firstWhere(
        (n) => n.type == 'next_action_due' && n.taskId == dueTask.id,
        orElse: () => throw Exception('Next action due notification not generated'),
      );
      expect(nextActionNotif.isRead, isFalse);

      final overdueNotif = notifsA.items.firstWhere(
        (n) => n.type == 'task_overdue' && n.taskId == dueTask.id,
        orElse: () => throw Exception('Task overdue notification not generated'),
      );
      expect(overdueNotif.isRead, isFalse);
    });

    test('17. Verify duplicate prevention: Second evaluate run produces 0 new notifications', () async {
      final evalResultSecond = await notificationServiceA.evaluateNotifications();
      expect(evalResultSecond.createdCount, equals(0));
    });

    test('18. Mark all notifications read: User A clears all unread notifications', () async {
      final unreadBefore = await notificationServiceA.getUnreadCount();
      expect(unreadBefore, greaterThan(0));

      final remainingUnread = await notificationServiceA.markAllAsRead();
      expect(remainingUnread, equals(0));
    });

    test('19. Verify unread count becomes zero', () async {
      final unreadAfter = await notificationServiceA.getUnreadCount();
      expect(unreadAfter, equals(0));

      final unreadList = await notificationServiceA.getNotifications(unreadOnly: true);
      expect(unreadList.items, isEmpty);
      expect(unreadList.unreadCount, equals(0));
    });

    test('20. Refresh application: Query all notifications with pagination and filters', () async {
      final allNotifs = await notificationServiceA.getNotifications(pageSize: 50);
      expect(allNotifs.total, greaterThanOrEqualTo(4));
      for (final n in allNotifs.items) {
        expect(n.isRead, isTrue);
      }
    });

    test('21. Verify notification state persists from PostgreSQL', () async {
      // Re-create a fresh ApiClient/NotificationService to ensure no client-side caching
      final freshClient = ApiClient(tokenStorage: tokenStorageA);
      final freshNotificationService = NotificationService(apiClient: freshClient);

      final freshList = await freshNotificationService.getNotifications();
      expect(freshList.total, greaterThanOrEqualTo(4));
      expect(freshList.unreadCount, equals(0));
      expect(freshList.items.every((n) => n.isRead), isTrue);
    });
  });
}
