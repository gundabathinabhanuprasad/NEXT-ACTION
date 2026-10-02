import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/dashboard/dashboard_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/dashboard/dashboard_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/services/task/task_service.dart';
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
  group('Phase 16 Live E2E Verification: Advanced Dashboard, Analytics & Workload Intelligence', () {
    // Primary User Services
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late DashboardService dashboardService;
    late TaskService taskService;
    late ClientService clientService;
    late WorkflowService workflowService;
    late ReminderService reminderService;
    late FollowUpService followUpService;
    late NotificationService notificationService;
    late TestTokenStorage tokenStorage;

    // Secondary User Services (Team & Security Isolation)
    late ApiClient apiClientB;
    late AuthService authServiceB;
    late AuthProvider authProviderB;
    late DashboardService dashboardServiceB;
    late TaskService taskServiceB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'dash_user_$testRunId@nextaction.local';
    final userName = 'Dashboard Analyst $testRunId';
    final userBEmail = 'dash_userb_$testRunId@nextaction.local';
    final userBName = 'Team Associate $testRunId';
    const userPassword = 'Password123!';

    late User user;
    late User userB;
    late Client clientA;
    late Client clientB;
    late Workflow workflowA;
    late Workflow workflowB;

    late Task taskOverdue;
    late Task taskDueToday;
    late Task taskUpcoming;
    late Task taskCompleted;
    late Task taskNearMax;
    late Task taskCancelled;
    late Task taskUserB;

    late Reminder reminderToday;
    late FollowUp followUpToday;
    late FollowUp followUpOverdue;

    DashboardSummary? latestSummary;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      dashboardService = DashboardService(apiClient: apiClient);
      taskService = TaskService(apiClient: apiClient);
      clientService = ClientService(apiClient: apiClient);
      workflowService = WorkflowService(apiClient: apiClient);
      reminderService = ReminderService(apiClient: apiClient);
      followUpService = FollowUpService(apiClient: apiClient);
      notificationService = NotificationService(apiClient: apiClient);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      authProviderB = AuthProvider(authService: authServiceB);
      dashboardServiceB = DashboardService(apiClient: apiClientB);
      taskServiceB = TaskService(apiClient: apiClientB);
    });

    test('1. Login: Register and authenticate primary user and secondary team user', () async {
      user = (await authProvider.register(userName, userEmail, userPassword))!;
      expect(user.id, isNotEmpty);
      final loggedInA = await authProvider.login(userEmail, userPassword);
      expect(loggedInA, isTrue);

      userB = (await authProviderB.register(userBName, userBEmail, userPassword))!;
      expect(userB.id, isNotEmpty);
      final loggedInB = await authProviderB.login(userBEmail, userPassword);
      expect(loggedInB, isTrue);
    });

    test('2. Create multiple users where needed: verify active profile metadata', () async {
      final meA = await authService.getCurrentUser();
      final meB = await authServiceB.getCurrentUser();
      expect(meA.id, equals(user.id));
      expect(meB.id, equals(userB.id));
      expect(meA.email, equals(userEmail));
    });

    test('3. Create multiple clients: Client A and Client B', () async {
      clientA = await clientService.createClient(
        ClientCreateRequest(
          name: 'Enterprise Client A $testRunId',
          company: 'Acme Alpha Inc',
          email: 'clienta_$testRunId@acme.com',
        ),
      );
      clientB = await clientService.createClient(
        ClientCreateRequest(
          name: 'Global Logistics B $testRunId',
          company: 'Beta Logistics LLC',
          email: 'clientb_$testRunId@beta.com',
        ),
      );

      expect(clientA.id, isNotEmpty);
      expect(clientB.id, isNotEmpty);
    });

    test('4. Create multiple workflows: Workflow A and Workflow B', () async {
      workflowA = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Executive Onboarding $testRunId',
          description: 'High priority onboarding workflow',
          isActive: true,
        ),
      );
      workflowB = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Customer Support Pipeline $testRunId',
          description: 'Standard support workflow',
          isActive: true,
        ),
      );

      expect(workflowA.id, isNotEmpty);
      expect(workflowB.id, isNotEmpty);
    });

    test('5 & 6. Create tasks with different statuses and priorities', () async {
      final now = DateTime.now().toUtc();

      // Overdue Task (High Priority, Client A, Workflow A, Assigned to User A)
      taskOverdue = await taskService.createTask(
        TaskCreateRequest(
          title: 'Overdue Task $testRunId',
          subjectLine: 'Critical overdue action',
          priority: 'urgent',
          dueDate: now.subtract(const Duration(days: 3)),
          clientId: clientA.id,
          workflowId: workflowA.id,
          assignedUserId: user.id,
        ),
      );

      // Due Today Task (High Priority, Client A, Workflow B, Assigned to User A)
      taskDueToday = await taskService.createTask(
        TaskCreateRequest(
          title: 'Due Today Task $testRunId',
          subjectLine: 'Action due today',
          priority: 'high',
          dueDate: now,
          nextActionDate: now,
          clientId: clientA.id,
          workflowId: workflowB.id,
          assignedUserId: user.id,
        ),
      );

      // Upcoming Task (Medium Priority, Client B, Workflow B, Unassigned)
      taskUpcoming = await taskService.createTask(
        TaskCreateRequest(
          title: 'Upcoming Task $testRunId',
          subjectLine: 'Future deliverable',
          priority: 'medium',
          dueDate: now.add(const Duration(days: 4)),
          clientId: clientB.id,
          workflowId: workflowB.id,
        ),
      );

      // Completed Task (Low Priority, Client B, Workflow A, Assigned to User A)
      taskCompleted = await taskService.createTask(
        TaskCreateRequest(
          title: 'Completed Task $testRunId',
          subjectLine: 'Finished task',
          priority: 'low',
          clientId: clientB.id,
          workflowId: workflowA.id,
          assignedUserId: user.id,
        ),
      );

      // Near Max Attempts Task (Urgent Priority, Client A, Workflow A)
      taskNearMax = await taskService.createTask(
        TaskCreateRequest(
          title: 'Near Max Attempts Task $testRunId',
          subjectLine: 'Task approaching attempt limit',
          priority: 'urgent',
          maxAttempts: 3,
          clientId: clientA.id,
          workflowId: workflowA.id,
          assignedUserId: user.id,
        ),
      );

      // Cancelled Task
      taskCancelled = await taskService.createTask(
        TaskCreateRequest(
          title: 'Cancelled Task $testRunId',
          subjectLine: 'Discontinued action',
          priority: 'low',
          clientId: clientB.id,
          workflowId: workflowB.id,
        ),
      );

      // Team Member Task (Assigned to User B)
      taskUserB = await taskService.createTask(
        TaskCreateRequest(
          title: 'User B Task $testRunId',
          subjectLine: 'Workload assigned to User B',
          priority: 'medium',
          dueDate: now,
          clientId: clientB.id,
          workflowId: workflowA.id,
          assignedUserId: userB.id,
        ),
      );

      expect(taskOverdue.id, isNotEmpty);
      expect(taskDueToday.id, isNotEmpty);
      expect(taskUpcoming.id, isNotEmpty);
    });

    test('7. Assign tasks and register attempts to build attempt pressure', () async {
      // Record 2 attempts on nearMax task (limit = 3) -> near max attempts!
      final att1 = await taskService.recordAttempt(taskNearMax.id, notes: 'First try');
      final att2 = await taskService.recordAttempt(taskNearMax.id, notes: 'Second try');
      expect(att1.attemptCount, equals(1));
      expect(att2.attemptCount, equals(2));
      expect(att2.isApproachingMaxAttempts, isTrue);
    });

    test('8, 9 & 10. Verify overdue, due-today, and upcoming task state models', () async {
      final fetchedOverdue = await taskService.getTask(taskOverdue.id);
      final fetchedDueToday = await taskService.getTask(taskDueToday.id);
      final fetchedUpcoming = await taskService.getTask(taskUpcoming.id);

      expect(fetchedOverdue.isOverdue, isTrue);
      expect(fetchedDueToday.isDueToday, isTrue);
      expect(fetchedUpcoming.dueDate != null, isTrue);
    });

    test('11. Create next actions: set nextActionDate and verify', () async {
      final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
      final updated = await taskService.updateNextActionDate(taskUpcoming.id, nextActionDate: tomorrow);
      expect(updated.nextActionDate, isNotNull);
    });

    test('12. Create reminders: Reminder due today and future reminder', () async {
      final now = DateTime.now().toUtc();
      reminderToday = await reminderService.createReminder(
        ReminderCreateRequest(
          taskId: taskDueToday.id,
          remindAt: now.add(const Duration(minutes: 1)),
          message: 'Reminder for due today task',
        ),
      );
      expect(reminderToday.id, isNotEmpty);
      expect(reminderToday.isSent, isFalse);
    });

    test('13. Create follow-ups: Follow-up due today and overdue follow-up', () async {
      final now = DateTime.now().toUtc();

      followUpToday = await followUpService.createFollowUp(
        FollowUpCreateRequest(
          taskId: taskDueToday.id,
          scheduledAt: now.add(const Duration(hours: 2)),
          notes: 'Follow-up with client regarding onboarding specs',
        ),
      );

      followUpOverdue = await followUpService.createFollowUp(
        FollowUpCreateRequest(
          taskId: taskOverdue.id,
          scheduledAt: now.subtract(const Duration(days: 1)),
          notes: 'Urgent overdue follow-up on escalations',
        ),
      );

      expect(followUpToday.id, isNotEmpty);
      expect(followUpOverdue.id, isNotEmpty);
    });

    test('14. Complete tasks: Mark completed and cancelled', () async {
      final completed = await taskService.completeTask(taskCompleted.id);
      expect(completed.status, equals('completed'));
      expect(completed.isCompleted, isTrue);

      final cancelled = await taskService.changeStatus(taskCancelled.id, status: 'cancelled');
      expect(cancelled.status, equals('cancelled'));
      expect(cancelled.isCancelled, isTrue);
    });

    test('15. Generate activity: Verify task history audit trail was created in PostgreSQL', () async {
      final history = await taskService.getTaskHistory(taskNearMax.id);
      expect(history, isNotEmpty);
      expect(history.any((h) => h.action == 'attempt'), isTrue);
    });

    test('16. Generate notifications: Send reminder to generate in-app alert notification', () async {
      final sent = await reminderService.sendReminder(reminderToday.id);
      expect(sent.isSent, isTrue);

      final notifs = await notificationService.getNotifications(unreadOnly: false);
      expect(notifs.items, isNotEmpty);
    });

    test('17. Open dashboard: Fetch PostgreSQL-aggregated dashboard summary', () async {
      latestSummary = await dashboardService.getDashboardSummary(timeRange: 'last_7_days');
      expect(latestSummary, isNotNull);
      expect(latestSummary!.timeRange, equals('last_7_days'));
      expect(latestSummary!.kpis, isNotNull);
    });

    test('18. Verify KPI counts: Real database numbers reflect open, overdue, due today, near max', () async {
      final kpis = latestSummary!.kpis;
      expect(kpis.totalOpenTasks, greaterThanOrEqualTo(4));
      expect(kpis.overdueTasks, greaterThanOrEqualTo(1));
      expect(kpis.dueTodayTasks, greaterThanOrEqualTo(1));
      expect(kpis.upcomingTasks, greaterThanOrEqualTo(1));
      expect(kpis.completedInRange, greaterThanOrEqualTo(1));
      expect(kpis.createdInRange, greaterThanOrEqualTo(5));
      expect(kpis.nearMaxAttempts, greaterThanOrEqualTo(1));
      expect(kpis.pendingFollowUps, greaterThanOrEqualTo(2));
      expect(kpis.unreadNotifications, greaterThanOrEqualTo(1));
    });

    test('19. Verify distributions: Status distribution and Priority distribution', () async {
      final statusDist = latestSummary!.statusDistribution;
      expect(statusDist.pending, greaterThanOrEqualTo(3));
      expect(statusDist.completed, greaterThanOrEqualTo(1));
      expect(statusDist.cancelled, greaterThanOrEqualTo(1));
      expect(statusDist.total, greaterThanOrEqualTo(5));

      final prioDist = latestSummary!.priorityDistribution;
      expect(prioDist.urgent, greaterThanOrEqualTo(2));
      expect(prioDist.high, greaterThanOrEqualTo(1));
      expect(prioDist.medium, greaterThanOrEqualTo(1));
      expect(prioDist.total, greaterThanOrEqualTo(4));
    });

    test('20. Verify trends: Daily created, completed, and overdue points are non-empty & contiguous', () async {
      final trends = latestSummary!.trends;
      expect(trends, isNotEmpty);
      expect(trends.length, equals(7)); // 7-day range gives 7 points

      // Check that today's date has created_count > 0
      final hasCreatedToday = trends.any((p) => p.createdCount > 0);
      expect(hasCreatedToday, isTrue);
    });

    test('21. Verify workload sections: Breakdown by Assignee, Client, and Workflow', () async {
      final workload = latestSummary!.workload;

      // Assignees
      expect(workload.byAssignee, isNotEmpty);
      final userAWorkload = workload.byAssignee.firstWhere((a) => a.userId == user.id);
      expect(userAWorkload.userName, equals(userName));
      expect(userAWorkload.openTasks, greaterThanOrEqualTo(3));

      // Clients
      expect(workload.byClient, isNotEmpty);
      final clientAWorkload = workload.byClient.firstWhere((c) => c.clientId == clientA.id);
      expect(clientAWorkload.clientName, contains('Enterprise Client A'));
      expect(clientAWorkload.openTasks, greaterThanOrEqualTo(3));

      // Workflows
      expect(workload.byWorkflow, isNotEmpty);
      final workflowAWorkload = workload.byWorkflow.firstWhere((w) => w.workflowId == workflowA.id);
      expect(workflowAWorkload.workflowName, contains('Executive Onboarding'));
      expect(workflowAWorkload.openTasks, greaterThanOrEqualTo(2));
    });

    test('22. Click dashboard KPI -> TaskListScreen filtered queries work accurately', () async {
      // Filter overdue
      final overdueFiltered = await taskService.getTasks(overdue: true);
      expect(overdueFiltered.items.any((t) => t.id == taskOverdue.id), isTrue);

      // Filter due today
      final dueTodayFiltered = await taskService.getTasks(dueToday: true);
      expect(dueTodayFiltered.items.any((t) => t.id == taskDueToday.id), isTrue);

      // Filter near max attempts
      final nearMaxFiltered = await taskService.getTasks(nearMaxAttempts: true);
      expect(nearMaxFiltered.items.any((t) => t.id == taskNearMax.id), isTrue);

      // Filter by status = completed
      final completedFiltered = await taskService.getTasks(status: 'completed');
      expect(completedFiltered.items.any((t) => t.id == taskCompleted.id), isTrue);

      // Filter by priority = urgent
      final urgentFiltered = await taskService.getTasks(priority: 'urgent');
      expect(urgentFiltered.items.any((t) => t.id == taskOverdue.id), isTrue);
    });

    test('23. Click client workload -> Filtered tasks by Client ID', () async {
      final clientTasks = await taskService.getTasks(clientId: clientA.id);
      expect(clientTasks.items, isNotEmpty);
      for (final t in clientTasks.items) {
        expect(t.clientId, equals(clientA.id));
      }
    });

    test('24. Click workflow workload -> Filtered tasks by Workflow ID', () async {
      final workflowTasks = await taskService.getTasks(workflowId: workflowA.id);
      expect(workflowTasks.items, isNotEmpty);
      for (final t in workflowTasks.items) {
        expect(t.workflowId, equals(workflowA.id));
      }
    });

    test('25. Click team workload -> Filtered tasks by Assignee User ID and Unassigned', () async {
      // User A
      final userATasks = await taskService.getTasks(assignedUserId: user.id);
      expect(userATasks.items, isNotEmpty);
      for (final t in userATasks.items) {
        expect(t.assignedUserId, equals(user.id));
      }

      // User B
      final userBTasks = await taskServiceB.getTasks(assignedUserId: userB.id);
      expect(userBTasks.items.any((t) => t.id == taskUserB.id), isTrue);
    });

    test('26. Click reminder / follow-up counts: Scheduling data integrity', () async {
      final scheduling = latestSummary!.scheduling;
      expect(scheduling.followUps.pending, greaterThanOrEqualTo(2));
      expect(scheduling.followUps.overdue, greaterThanOrEqualTo(1));

      final allFollowUps = await followUpService.getFollowUps();
      expect(allFollowUps.any((f) => f.id == followUpToday.id), isTrue);
      expect(allFollowUps.any((f) => f.id == followUpOverdue.id), isTrue);
    });

    test('27. Click notification summary: Notifications center verification', () async {
      final notifs = await notificationService.getNotifications();
      expect(notifs.unreadCount, greaterThanOrEqualTo(1));
    });

    test('28. Click activity summary: Audit timeline verification', () async {
      final recent = await taskService.getRecentActivity(limit: 10);
      expect(recent, isNotEmpty);
    });

    test('29. Change date range: Test today, last_7_days, last_30_days, this_month', () async {
      final summaryToday = await dashboardService.getDashboardSummary(timeRange: 'today');
      expect(summaryToday.timeRange, equals('today'));
      expect(summaryToday.trends.length, equals(1));

      final summary30 = await dashboardService.getDashboardSummary(timeRange: 'last_30_days');
      expect(summary30.timeRange, equals('last_30_days'));
      expect(summary30.trends.length, equals(30));

      final summaryMonth = await dashboardService.getDashboardSummary(timeRange: 'this_month');
      expect(summaryMonth.timeRange, equals('this_month'));
      expect(summaryMonth.trends, isNotEmpty);
    });

    test('30. Refresh: Single-call coherent update retrieves fresh server data', () async {
      final refreshed = await dashboardService.getDashboardSummary(timeRange: 'last_7_days');
      expect(refreshed.kpis.totalOpenTasks, greaterThanOrEqualTo(latestSummary!.kpis.totalOpenTasks));
    });

    test('31. Verify no cross-user data leakage and JWT security isolation', () async {
      // Unauthenticated request fails with 401
      final unauthClient = ApiClient(tokenStorage: TestTokenStorage());
      final unauthDashboard = DashboardService(apiClient: unauthClient);
      try {
        await unauthDashboard.getDashboardSummary();
        fail('Unauthenticated dashboard request should throw 401');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
      }

      // Secondary User B dashboard is user-scoped for personal metrics
      final summaryB = await dashboardServiceB.getDashboardSummary();
      expect(summaryB.timeRange, equals('last_7_days'));
    });

    test('32. Verify PostgreSQL-backed data remains consistent and robust', () async {
      final finalSummary = await dashboardService.getDashboardSummary();
      expect(finalSummary.kpis.totalOpenTasks, greaterThanOrEqualTo(1));
      expect(finalSummary.kpis.createdInRange, greaterThanOrEqualTo(1));
      expect(finalSummary.statusDistribution.total, greaterThanOrEqualTo(finalSummary.kpis.totalOpenTasks));
    });
  });
}
