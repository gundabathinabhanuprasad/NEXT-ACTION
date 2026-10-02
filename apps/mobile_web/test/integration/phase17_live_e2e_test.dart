import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/report/report_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/services/report/report_service.dart';
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
  group('Phase 17 Live E2E Verification: Reports, Exports & Management Insights (30 Steps)', () {
    // Primary User Services
    late ApiClient apiClient;
    late AuthService authService;
    late ReportService reportService;
    late TaskService taskService;
    late ClientService clientService;
    late WorkflowService workflowService;
    late ReminderService reminderService;
    late FollowUpService followUpService;
    late TestTokenStorage tokenStorage;

    // Secondary User Services (Team & Security Isolation)
    late ApiClient apiClientB;
    late AuthService authServiceB;
    late ReportService reportServiceB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'report_admin_$testRunId@nextaction.local';
    final userName = 'Report Admin $testRunId';
    final userBEmail = 'report_userb_$testRunId@nextaction.local';
    final userBName = 'Report Staff $testRunId';
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

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      reportService = ReportService(apiClient: apiClient);
      taskService = TaskService(apiClient: apiClient);
      clientService = ClientService(apiClient: apiClient);
      workflowService = WorkflowService(apiClient: apiClient);
      reminderService = ReminderService(apiClient: apiClient);
      followUpService = FollowUpService(apiClient: apiClient);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      reportServiceB = ReportService(apiClient: apiClientB);
    });

    // -------------------------------------------------------------------------
    // 1. Authentication & User Provisioning
    // -------------------------------------------------------------------------
    test('1. Register and Authenticate Primary User', () async {
      user = await authService.register(
        userName,
        userEmail,
        userPassword,
      );
      expect(user.id, isNotEmpty);

      final tokenResponse = await authService.login(
        userEmail,
        userPassword,
      );
      expect(tokenResponse.accessToken, isNotEmpty);
    });

    test('2. Register and Authenticate Secondary User', () async {
      userB = await authServiceB.register(
        userBName,
        userBEmail,
        userPassword,
      );
      expect(userB.id, isNotEmpty);

      final tokenResponseB = await authServiceB.login(
        userBEmail,
        userPassword,
      );
      expect(tokenResponseB.accessToken, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // 2. Organization Domain Setup (Clients & Workflows)
    // -------------------------------------------------------------------------
    test('3. Create Representative Clients in PostgreSQL', () async {
      clientA = await clientService.createClient(
        ClientCreateRequest(
          name: 'Apex Global Financial $testRunId',
          notes: 'Enterprise Tier Client for Reports Testing',
        ),
      );
      expect(clientA.name, contains('Apex Global Financial'));

      clientB = await clientService.createClient(
        ClientCreateRequest(
          name: 'Beacon Systems $testRunId',
          notes: 'Mid-Market Client',
        ),
      );
      expect(clientB.name, contains('Beacon Systems'));
    });

    test('4. Create Representative Workflows in PostgreSQL', () async {
      workflowA = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Executive Reporting Workflow $testRunId',
          description: 'End-to-end report testing pipeline',
        ),
      );
      expect(workflowA.name, contains('Executive Reporting Workflow'));

      workflowB = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Customer Support Dispatch $testRunId',
          description: 'Operations workflow',
        ),
      );
      expect(workflowB.name, contains('Customer Support Dispatch'));
    });

    // -------------------------------------------------------------------------
    // 3. Operational Tasks, History, Reminders & Follow-ups Creation
    // -------------------------------------------------------------------------
    test('5. Create Diverse Set of Tasks with Varied States & Priorities', () async {
      final now = DateTime.now().toUtc();
      final todayStart = DateTime.utc(now.year, now.month, now.day);

      // Task 1: Overdue Urgent under Client A, Workflow A, User A
      taskOverdue = await taskService.createTask(
        TaskCreateRequest(
          title: 'Overdue Urgent Audit $testRunId',
          subjectLine: 'Audit 2026',
          description: 'Special characters: "quotes" & unicode 🚀',
          priority: 'urgent',
          status: 'pending',
          dueDate: todayStart.subtract(const Duration(days: 2)),
          clientId: clientA.id,
          workflowId: workflowA.id,
          assignedUserId: user.id,
          maxAttempts: 2,
        ),
      );
      expect(taskOverdue.priority, 'urgent');

      // Task 2: Due Today High under Client A, Workflow A, User A
      taskDueToday = await taskService.createTask(
        TaskCreateRequest(
          title: 'Review Client SLA Agreement $testRunId',
          subjectLine: 'SLA Review',
          priority: 'high',
          status: 'in_progress',
          dueDate: todayStart.add(const Duration(hours: 23)),
          nextActionDate: todayStart.add(const Duration(hours: 21)),
          clientId: clientA.id,
          workflowId: workflowA.id,
          assignedUserId: user.id,
          maxAttempts: 3,
        ),
      );
      expect(taskDueToday.status, 'in_progress');

      // Task 3: Upcoming Medium under Client B, Workflow B, User B
      taskUpcoming = await taskService.createTask(
        TaskCreateRequest(
          title: 'Quarterly Infrastructure Upgrade $testRunId',
          priority: 'medium',
          status: 'pending',
          dueDate: todayStart.add(const Duration(days: 5)),
          clientId: clientB.id,
          workflowId: workflowB.id,
          assignedUserId: userB.id,
          maxAttempts: 2,
        ),
      );
      expect(taskUpcoming.priority, 'medium');

      // Task 4: Completed Low under Client B, Workflow B, User B
      final taskTemp = await taskService.createTask(
        TaskCreateRequest(
          title: 'Finalize Deployment Checklist $testRunId',
          priority: 'low',
          status: 'in_progress',
          dueDate: todayStart.subtract(const Duration(days: 1)),
          clientId: clientB.id,
          workflowId: workflowB.id,
          assignedUserId: userB.id,
          maxAttempts: 2,
        ),
      );
      taskCompleted = await taskService.completeTask(taskTemp.id);
      expect(taskCompleted.status, 'completed');

      // Task 5: Near Max Attempts
      final taskNearMaxTemp = await taskService.createTask(
        TaskCreateRequest(
          title: 'High Retry Operation $testRunId',
          priority: 'urgent',
          status: 'in_progress',
          dueDate: todayStart.add(const Duration(days: 2)),
          clientId: clientA.id,
          workflowId: workflowA.id,
          assignedUserId: user.id,
          maxAttempts: 2,
        ),
      );
      taskNearMax = await taskService.recordAttempt(taskNearMaxTemp.id, notes: 'Attempt 1 failed');
      expect(taskNearMax.attemptCount, 1);
    });

    test('6. Create Reminders and Follow-ups for Task Linkages', () async {
      final now = DateTime.now().toUtc();

      await reminderService.createReminder(
        ReminderCreateRequest(
          taskId: taskOverdue.id,
          remindAt: now.subtract(const Duration(hours: 1)),
          message: 'Reminder for overdue audit $testRunId',
        ),
      );

      await followUpService.createFollowUp(
        FollowUpCreateRequest(
          taskId: taskOverdue.id,
          scheduledAt: now.subtract(const Duration(days: 1)),
          notes: 'Follow up on audit findings $testRunId',
        ),
      );
    });

    // -------------------------------------------------------------------------
    // 4. Report 1: Task Summary Report
    // -------------------------------------------------------------------------
    test('7. Generate Task Summary Report with Server-side Aggregation', () async {
      final summary = await reportService.getTaskSummaryReport(
        filters: ReportFilters(clientId: clientA.id),
      );

      expect(summary.totalTasks, 3); // taskOverdue, taskDueToday, taskNearMax
      expect(summary.openTasks, 3);
      expect(summary.completedTasks, 0);
      expect(summary.overdueTasks, 1);
      expect(summary.dueTodayTasks, 1);
      expect(summary.nearMaxAttempts, 1); // taskNearMax (1/2)

      expect(summary.statusBreakdown.pending, 1);
      expect(summary.statusBreakdown.inProgress, 2);
      expect(summary.priorityBreakdown.urgent, 2);
      expect(summary.priorityBreakdown.high, 1);
    });

    // -------------------------------------------------------------------------
    // 5. Report 2: Task Detail Report
    // -------------------------------------------------------------------------
    test('8. Generate Task Detail Report with Filtering and Relations', () async {
      final detail = await reportService.getTaskDetailReport(
        filters: ReportFilters(clientId: clientA.id),
        page: 1,
        pageSize: 10,
        sortBy: 'created_at',
        sortOrder: 'desc',
      );

      expect(detail.total, 3);
      expect(detail.items.length, 3);

      final firstItem = detail.items.first;
      expect(firstItem.clientName, contains('Apex Global Financial'));
      expect(firstItem.workflowName, contains('Executive Reporting Workflow'));
      expect(firstItem.assignedUserName, userName);
    });

    test('9. Filter Task Detail Report by Status and Priority', () async {
      final completedDetail = await reportService.getTaskDetailReport(
        filters: ReportFilters(clientId: clientB.id, status: 'completed'),
      );
      expect(completedDetail.total, 1);
      expect(completedDetail.items.first.title, contains('Finalize Deployment Checklist'));

      final urgentDetail = await reportService.getTaskDetailReport(
        filters: ReportFilters(clientId: clientA.id, priority: 'urgent'),
      );
      expect(urgentDetail.total, 2);
    });

    // -------------------------------------------------------------------------
    // 6. Report 3: Productivity Report
    // -------------------------------------------------------------------------
    test('10. Generate Productivity Report with Zero-Filled Daily Trends', () async {
      final now = DateTime.now().toUtc();
      final from = now.subtract(const Duration(days: 6));
      final to = now;

      final prod = await reportService.getProductivityReport(
        dateFrom: from,
        dateTo: to,
        filters: ReportFilters(clientId: clientB.id),
      );

      expect(prod.totalCreated, 2); // taskUpcoming, taskCompleted
      expect(prod.totalCompleted, 1); // taskCompleted
      expect(prod.overallCompletionRate, 50.0);
      expect(prod.dailyTrends.length, 7); // Exactly 7 calendar days preserved
    });

    // -------------------------------------------------------------------------
    // 7. Report 4: Workload Report
    // -------------------------------------------------------------------------
    test('11. Generate Workload Report Across Assignees, Clients, and Workflows', () async {
      final wl = await reportService.getWorkloadReport();

      expect(wl.byAssignee, isNotEmpty);
      expect(wl.byClient, isNotEmpty);
      expect(wl.byWorkflow, isNotEmpty);

      final userAItem = wl.byAssignee.firstWhere((a) => a.id == user.id);
      expect(userAItem.openTasks, 3); // taskOverdue, taskDueToday, taskNearMax

      final userBItem = wl.byAssignee.firstWhere((b) => b.id == userB.id);
      expect(userBItem.openTasks, 1);
      expect(userBItem.completedTasks, 1);

      final clientAItem = wl.byClient.firstWhere((c) => c.id == clientA.id);
      expect(clientAItem.openTasks, 3);
      expect(clientAItem.totalTasks, 3);
    });

    // -------------------------------------------------------------------------
    // 8. Report 5: Activity / Audit Report
    // -------------------------------------------------------------------------
    test('12. Generate Activity Audit Report with Action Taxonomy Counts', () async {
      final act = await reportService.getActivityReport(
        taskId: taskNearMax.id,
      );

      expect(act.total, greaterThanOrEqualTo(2)); // created, attempt
      expect(act.items.any((i) => i.action == 'attempt'), isTrue);
      expect(act.actionCounts, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // 9. Report 6: Scheduling Queues Report
    // -------------------------------------------------------------------------
    test('13. Generate Scheduling Queues Report for Reminders & Follow-ups', () async {
      final sched = await reportService.getRemindersFollowupsReport(
        filters: ReportFilters(clientId: clientA.id),
      );

      expect(sched.summary.remindersTotal, greaterThanOrEqualTo(1));
      expect(sched.summary.followUpsTotal, greaterThanOrEqualTo(1));
      expect(sched.reminders, isNotEmpty);
      expect(sched.followUps, isNotEmpty);
      expect(sched.reminders.first.taskTitle, contains('Overdue Urgent Audit'));
    });

    // -------------------------------------------------------------------------
    // 10. Report Exports: CSV & JSON
    // -------------------------------------------------------------------------
    test('14. Export Task Detail Report as CSV and Validate Content', () async {
      final csvText = await reportService.exportReport(
        reportType: ReportType.taskDetail,
        format: ExportFormat.csv,
        filters: ReportFilters(clientId: clientA.id),
      );

      expect(csvText, contains('Task ID,Title,Subject Line,Status,Priority'));
      expect(csvText, contains('Overdue Urgent Audit'));
      expect(csvText, contains('🚀')); // Unicode preservation
      expect(csvText, contains('""quotes""'));
      expect(csvText, contains('Special characters'));
      expect(csvText, isNot(contains('password')));
      expect(csvText, isNot(contains('secret')));
    });

    test('15. Export Task Detail Report as JSON and Validate Schema', () async {
      final jsonText = await reportService.exportReport(
        reportType: ReportType.taskDetail,
        format: ExportFormat.json,
        filters: ReportFilters(clientId: clientA.id),
      );

      expect(jsonText, contains('"report_type": "task_detail"'));
      expect(jsonText, contains('"generated_at"'));
      expect(jsonText, contains('"items"'));
      expect(jsonText, contains('Apex Global Financial'));
    });

    test('16. Export Productivity Report as CSV', () async {
      final csvText = await reportService.exportReport(
        reportType: ReportType.productivity,
        format: ExportFormat.csv,
        filters: ReportFilters(clientId: clientB.id),
      );

      expect(csvText, contains('Productivity Summary'));
      expect(csvText, contains('Date,Created Tasks,Completed Tasks'));
    });

    test('17. Export Workload Report as CSV', () async {
      final csvText = await reportService.exportReport(
        reportType: ReportType.workload,
        format: ExportFormat.csv,
      );

      expect(csvText, contains('WORKLOAD BY ASSIGNEE'));
      expect(csvText, contains('WORKLOAD BY CLIENT'));
      expect(csvText, contains('WORKLOAD BY WORKFLOW'));
    });

    // -------------------------------------------------------------------------
    // 11. Validations & Security Boundary Tests
    // -------------------------------------------------------------------------
    test('18. Verify Invalid Date Range is Rejected with 422', () async {
      final from = DateTime.utc(2026, 12, 31);
      final to = DateTime.utc(2026, 1, 1);

      expect(
        () async => await reportService.getTaskDetailReport(
          filters: ReportFilters(dateFrom: from, dateTo: to),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422)),
      );
    });

    test('19. Verify Unauthenticated Report Request is Rejected with 401', () async {
      final unauthClient = ApiClient(tokenStorage: TestTokenStorage());
      final unauthReportService = ReportService(apiClient: unauthClient);

      expect(
        () async => await unauthReportService.getTaskSummaryReport(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('20. Verify Secondary User Access and State Isolation', () async {
      final summaryB = await reportServiceB.getTaskSummaryReport(
        filters: ReportFilters(assignedUserId: userB.id),
      );
      expect(summaryB.totalTasks, 2); // taskUpcoming, taskCompleted
      expect(summaryB.openTasks, 1);
      expect(summaryB.completedTasks, 1);
    });
  });
}
