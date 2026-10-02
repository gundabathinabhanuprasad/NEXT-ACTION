import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
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
  group('Phase 13 Live End-to-End Advanced Search, Filters & Task Discovery (25 Steps)', () {
    // Services for Primary User
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late UserService userService;
    late ClientService clientService;
    late WorkflowService workflowService;
    late TestTokenStorage tokenStorage;

    // Services for Secondary User (Cross-user validation)
    late ApiClient apiClientB;
    late AuthService authServiceB;
    late AuthProvider authProviderB;
    late TaskService taskServiceB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'search_user_$testRunId@nextaction.local';
    final userName = 'Search Admin $testRunId';
    final userBEmail = 'search_userb_$testRunId@nextaction.local';
    final userBName = 'Search User B $testRunId';
    const userPassword = 'Password123!';

    late User user;
    late User userB;
    late Client clientAlpha;
    late Client clientBeta;
    late Workflow workflowSales;
    late Workflow workflowAudit;

    late Task taskOverdueUrgent;
    late Task taskDueTodayHigh;
    late Task taskUpcomingLow;
    late Task taskNearMax;
    late Task taskNoNextAction;

    final nowUtc = DateTime.now().toUtc();
    final todayDue = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 12, 0, 0);
    final overdueDue = nowUtc.subtract(const Duration(days: 3));
    final upcomingDue = nowUtc.add(const Duration(days: 5));

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

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      authProviderB = AuthProvider(authService: authServiceB);
      taskServiceB = TaskService(apiClient: apiClientB);
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

    test('2. Create Supporting Entities & Diverse Task Corpus', () async {
      // Create Clients
      clientAlpha = await clientService.createClient(
        ClientCreateRequest(
          name: 'Alpha Quantum Ltd $testRunId',
          company: 'Quantum Tech Corp',
          email: 'alpha_$testRunId@quantum.com',
        ),
      );
      clientBeta = await clientService.createClient(
        ClientCreateRequest(
          name: 'Beta Solar Systems $testRunId',
          company: 'Solar Energy Holdings',
          email: 'beta_$testRunId@solar.com',
        ),
      );

      // Create Workflows
      workflowSales = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Enterprise Sales Funnel $testRunId',
          description: 'Lead discovery and deal closure pipeline',
        ),
      );
      workflowAudit = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Cybersecurity Audit $testRunId',
          description: 'Vulnerability assessments and SOC2 compliance',
        ),
      );

      // 1. Task: Overdue, Urgent, Alpha Client, Audit Workflow, Assigned to User
      taskOverdueUrgent = await taskService.createTask(
        TaskCreateRequest(
          title: 'Cryptographic Security Review $testRunId',
          description: 'Perform quantum cipher analysis on key infrastructure',
          subjectLine: 'Alpha SOC2 Compliance Audit Report',
          status: 'in_progress',
          priority: 'urgent',
          clientId: clientAlpha.id,
          workflowId: workflowAudit.id,
          assignedUserId: user.id,
          dueDate: overdueDue,
          nextActionDate: todayDue,
        ),
      );

      // 2. Task: Due Today, High Priority, Beta Client, Sales Workflow, Assigned to User B
      taskDueTodayHigh = await taskService.createTask(
        TaskCreateRequest(
          title: 'Solar Panel Contract Finalization $testRunId',
          description: 'Finalize master services agreement for solar installation',
          subjectLine: 'Beta Solar Contract Terms v4',
          status: 'pending',
          priority: 'high',
          clientId: clientBeta.id,
          workflowId: workflowSales.id,
          assignedUserId: userB.id,
          dueDate: todayDue,
          nextActionDate: todayDue,
        ),
      );

      // 3. Task: Upcoming, Low Priority, Unassigned, Sales Workflow
      taskUpcomingLow = await taskService.createTask(
        TaskCreateRequest(
          title: 'Marketing Webinar Lead Distribution $testRunId',
          description: 'Distribute inbound demo requests to sales representatives',
          subjectLine: 'Webinar Leads Q4 Batch',
          status: 'pending',
          priority: 'low',
          clientId: null,
          workflowId: workflowSales.id,
          assignedUserId: null,
          dueDate: upcomingDue,
          nextActionDate: upcomingDue,
        ),
      );

      // 4. Task: Near Max Attempts (attempt 2 of 2)
      taskNearMax = await taskService.createTask(
        TaskCreateRequest(
          title: 'Database Failover Resilience Simulation $testRunId',
          description: 'Test automated read-replica recovery under partition',
          subjectLine: 'Disaster Recovery Runbook Step 3',
          status: 'in_progress',
          priority: 'medium',
          maxAttempts: 2,
          assignedUserId: user.id,
        ),
      );
      // Record 2 attempts
      await taskService.recordAttempt(taskNearMax.id, notes: 'Attempt 1 failed network check');
      await taskService.recordAttempt(taskNearMax.id, notes: 'Attempt 2 partition failed');

      // 5. Task: No Next Action Date scheduled
      taskNoNextAction = await taskService.createTask(
        TaskCreateRequest(
          title: 'Documentation Archival Indexing $testRunId',
          description: 'Archive legacy markdown specs to cold storage',
          subjectLine: 'Archival spec manifest',
          status: 'completed',
          priority: 'low',
          assignedUserId: user.id,
        ),
      );

      expect(taskOverdueUrgent.id, isNotEmpty);
      expect(taskDueTodayHigh.id, isNotEmpty);
      expect(taskUpcomingLow.id, isNotEmpty);
      expect(taskNearMax.id, isNotEmpty);
      expect(taskNoNextAction.id, isNotEmpty);
    });

    test('3. Search by title: Finds task matching unique title keyword', () async {
      final res = await taskService.getTasks(search: 'Cryptographic');
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(res.items.any((t) => t.id == taskDueTodayHigh.id), isFalse);
    });

    test('4. Search by subject line: Finds task matching subject line keywords', () async {
      final res = await taskService.getTasks(search: 'SOC2 Compliance Audit');
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
    });

    test('5. Search by description: Case-insensitive match on description text', () async {
      final res = await taskService.getTasks(search: 'quantum cipher analysis');
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
    });

    test('6. Filter by client: Matches tasks associated with clientAlpha', () async {
      final res = await taskService.getTasks(clientId: clientAlpha.id);
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(res.items.any((t) => t.id == taskDueTodayHigh.id), isFalse);
    });

    test('7. Filter by workflow: Matches tasks in workflowSales', () async {
      final res = await taskService.getTasks(workflowId: workflowSales.id);
      expect(res.items.any((t) => t.id == taskDueTodayHigh.id), isTrue);
      expect(res.items.any((t) => t.id == taskUpcomingLow.id), isTrue);
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isFalse);
    });

    test('8. Filter by assignment: Assigned to User and Unassigned', () async {
      // Assigned to User A
      final resUserA = await taskService.getTasks(assignedUserId: user.id);
      expect(resUserA.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(resUserA.items.any((t) => t.id == taskUpcomingLow.id), isFalse);

      // Unassigned
      final resUnassigned = await taskService.getTasks(unassigned: true);
      expect(resUnassigned.items.any((t) => t.id == taskUpcomingLow.id), isTrue);
      expect(resUnassigned.items.any((t) => t.id == taskOverdueUrgent.id), isFalse);
    });

    test('9. Filter by status: in_progress vs pending vs completed', () async {
      final resInProgress = await taskService.getTasks(status: 'in_progress');
      expect(resInProgress.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(resInProgress.items.any((t) => t.id == taskDueTodayHigh.id), isFalse);

      final resPending = await taskService.getTasks(status: 'pending');
      expect(resPending.items.any((t) => t.id == taskDueTodayHigh.id), isTrue);
      expect(resPending.items.any((t) => t.id == taskOverdueUrgent.id), isFalse);
    });

    test('10. Filter by priority: urgent vs high vs low', () async {
      final resUrgent = await taskService.getTasks(priority: 'urgent');
      expect(resUrgent.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(resUrgent.items.any((t) => t.id == taskDueTodayHigh.id), isFalse);

      final resLow = await taskService.getTasks(priority: 'low');
      expect(resLow.items.any((t) => t.id == taskUpcomingLow.id), isTrue);
      expect(resLow.items.any((t) => t.id == taskOverdueUrgent.id), isFalse);
    });

    test('11. Filter overdue: Returns tasks past due date not completed', () async {
      final res = await taskService.getTasks(overdue: true);
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(res.items.any((t) => t.id == taskUpcomingLow.id), isFalse);
    });

    test('12. Filter due today: Returns tasks scheduled for today', () async {
      final res = await taskService.getTasks(dueToday: true);
      expect(res.items.any((t) => t.id == taskDueTodayHigh.id), isTrue);
      expect(res.items.any((t) => t.id == taskUpcomingLow.id), isFalse);
    });

    test('13. Filter upcoming: Returns future due tasks not completed', () async {
      final res = await taskService.getTasks(upcoming: true);
      expect(res.items.any((t) => t.id == taskUpcomingLow.id), isTrue);
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isFalse);
    });

    test('14. Filter next action presence: hasNextAction vs noNextAction', () async {
      final resHas = await taskService.getTasks(hasNextAction: true);
      expect(resHas.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(resHas.items.any((t) => t.id == taskNoNextAction.id), isFalse);

      final resNo = await taskService.getTasks(noNextAction: true);
      expect(resNo.items.any((t) => t.id == taskNoNextAction.id), isTrue);
      expect(resNo.items.any((t) => t.id == taskOverdueUrgent.id), isFalse);
    });

    test('15. Filter near max attempts: Returns tasks approaching or at max attempts', () async {
      final res = await taskService.getTasks(nearMaxAttempts: true);
      expect(res.items.any((t) => t.id == taskNearMax.id), isTrue);
    });

    test('16. Combine multiple filters: status + priority + client_id', () async {
      final res = await taskService.getTasks(
        status: 'in_progress',
        priority: 'urgent',
        clientId: clientAlpha.id,
      );
      expect(res.items.length, greaterThanOrEqualTo(1));
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(res.items.any((t) => t.id == taskDueTodayHigh.id), isFalse);
    });

    test('17. Sort results: due_date asc, priority desc, created_at desc', () async {
      final resDueAsc = await taskService.getTasks(sortBy: 'due_date', sortOrder: 'asc', pageSize: 50);
      expect(resDueAsc.items.isNotEmpty, isTrue);

      final resPriorityDesc = await taskService.getTasks(sortBy: 'priority', sortOrder: 'desc', pageSize: 50);
      expect(resPriorityDesc.items.isNotEmpty, isTrue);

      final resCreatedDesc = await taskService.getTasks(sortBy: 'created_at', sortOrder: 'desc', pageSize: 50);
      expect(resCreatedDesc.items.isNotEmpty, isTrue);
    });

    test('18. Paginate results: page, page_size, total metadata', () async {
      final page1 = await taskService.getTasks(page: 1, pageSize: 2);
      expect(page1.items.length, lessThanOrEqualTo(2));
      expect(page1.page, equals(1));
      expect(page1.pageSize, equals(2));
      expect(page1.total, greaterThanOrEqualTo(4));

      final page2 = await taskService.getTasks(page: 2, pageSize: 2);
      expect(page2.page, equals(2));
    });

    test('19. Clear filters: returns unfiltered task corpus', () async {
      final res = await taskService.getTasks(pageSize: 100);
      expect(res.items.length, greaterThanOrEqualTo(5));
      expect(res.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(res.items.any((t) => t.id == taskDueTodayHigh.id), isTrue);
      expect(res.items.any((t) => t.id == taskUpcomingLow.id), isTrue);
      expect(res.items.any((t) => t.id == taskNearMax.id), isTrue);
      expect(res.items.any((t) => t.id == taskNoNextAction.id), isTrue);
    });

    test('20. Dashboard KPI Navigation query: queries overdue tasks accurately', () async {
      final overdueRes = await taskService.getTasks(overdue: true);
      expect(overdueRes.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
    });

    test('21. ClientDetail Navigation query: queries client tasks accurately', () async {
      final clientTasks = await taskService.getTasks(clientId: clientBeta.id);
      expect(clientTasks.items.any((t) => t.id == taskDueTodayHigh.id), isTrue);
      expect(clientTasks.items.every((t) => t.clientId == clientBeta.id), isTrue);
    });

    test('22. WorkflowDetail Navigation query: queries workflow tasks accurately', () async {
      final wfTasks = await taskService.getTasks(workflowId: workflowAudit.id);
      expect(wfTasks.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);
      expect(wfTasks.items.every((t) => t.workflowId == workflowAudit.id), isTrue);
    });

    test('23. TeamMemberDetail Navigation query: queries assigned user tasks accurately', () async {
      final member = await userService.getUser(userB.id);
      expect(member.id, equals(userB.id));
      final userBTasks = await taskService.getTasks(assignedUserId: userB.id);
      expect(userBTasks.items.any((t) => t.id == taskDueTodayHigh.id), isTrue);
    });

    test('24. Security: User B can read tasks, and unauthenticated request fails', () async {
      // User B lists tasks
      final resB = await taskServiceB.getTasks(search: 'Cryptographic');
      expect(resB.items.isNotEmpty, isTrue);

      // Unauthenticated client
      final unauthClient = ApiClient(tokenStorage: TestTokenStorage());
      final unauthService = TaskService(apiClient: unauthClient);
      expect(
        () async => await unauthService.getTasks(),
        throwsA(isA<ApiException>()),
      );
    });

    test('25. State Stability: Multiple sequential search and filter queries execute consistently', () async {
      final query1 = await taskService.getTasks(search: 'Cryptographic', status: 'in_progress');
      expect(query1.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);

      final query2 = await taskService.getTasks(clientId: clientAlpha.id, priority: 'urgent');
      expect(query2.items.any((t) => t.id == taskOverdueUrgent.id), isTrue);

      final query3 = await taskService.getTasks(upcoming: true);
      expect(query3.items.any((t) => t.id == taskUpcomingLow.id), isTrue);
    });
  });
}
