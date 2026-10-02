import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
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
  group('Phase 9 Live End-to-End Client, Workflow & Task Organization Verification (25 Steps)', () {
    late ApiClient apiClient;
    late AuthService authService;
    late AuthProvider authProvider;
    late TaskService taskService;
    late ClientService clientService;
    late WorkflowService workflowService;
    late TestTokenStorage tokenStorage;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'phase9_e2e_$testRunId@nextaction.local';
    const testPassword = 'Password123!';
    final testName = 'Phase 9 Lead $testRunId';

    late String createdClientId;
    late String createdWorkflowId;
    late String createdTaskId;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = TestTokenStorage();
      apiClient = ApiClient(tokenStorage: tokenStorage);
      authService = AuthService(apiClient: apiClient);
      authProvider = AuthProvider(authService: authService);
      taskService = TaskService(apiClient: apiClient);
      clientService = ClientService(apiClient: apiClient);
      workflowService = WorkflowService(apiClient: apiClient);

      // Register user against real FastAPI / PostgreSQL
      final user = await authProvider.register(testName, testEmail, testPassword);
      expect(user, isNotNull);
    });

    test('1. Login with credentials and receive authenticated JWT session', () async {
      final success = await authProvider.login(testEmail, testPassword);
      expect(success, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(await tokenStorage.hasToken(), isTrue);
    });

    test('2. Open Clients - query real clients endpoint from PostgreSQL', () async {
      final clientList = await clientService.getClients();
      expect(clientList.items, isA<List<Client>>());
      expect(clientList.total, isNonNegative);
    });

    test('3. Create a real client and 4. Verify client persists in PostgreSQL', () async {
      final newClient = await clientService.createClient(
        ClientCreateRequest(
          name: 'Acme Apex Enterprises $testRunId',
          company: 'Acme Global Group',
          email: 'apex_$testRunId@acme.com',
          phone: '+1-555-0199',
          notes: 'High-priority enterprise account',
        ),
      );

      expect(newClient.id, isNotEmpty);
      expect(newClient.name, 'Acme Apex Enterprises $testRunId');
      expect(newClient.company, 'Acme Global Group');
      createdClientId = newClient.id;

      // Verify persistence by querying directly
      final retrievedClient = await clientService.getClient(createdClientId);
      expect(retrievedClient.id, createdClientId);
      expect(retrievedClient.name, 'Acme Apex Enterprises $testRunId');
      expect(retrievedClient.displayName, 'Acme Apex Enterprises $testRunId (Acme Global Group)');
    });

    test('5. Open client detail and verify information', () async {
      final client = await clientService.getClient(createdClientId);
      expect(client.email, 'apex_$testRunId@acme.com');
      expect(client.phone, '+1-555-0199');
      expect(client.notes, 'High-priority enterprise account');
    });

    test('6. Open Workflows - query real workflows endpoint from PostgreSQL', () async {
      final workflowList = await workflowService.getWorkflows();
      expect(workflowList.items, isA<List<Workflow>>());
      expect(workflowList.total, isNonNegative);
    });

    test('7. Create a real workflow and 8. Verify workflow persists in PostgreSQL', () async {
      final newWorkflow = await workflowService.createWorkflow(
        WorkflowCreateRequest(
          name: 'Enterprise Onboarding Pipeline $testRunId',
          description: 'Standard 14-day customer integration workflow',
          isActive: true,
        ),
      );

      expect(newWorkflow.id, isNotEmpty);
      expect(newWorkflow.name, 'Enterprise Onboarding Pipeline $testRunId');
      expect(newWorkflow.isActive, isTrue);
      createdWorkflowId = newWorkflow.id;

      // Verify persistence by querying directly
      final retrievedWorkflow = await workflowService.getWorkflow(createdWorkflowId);
      expect(retrievedWorkflow.id, createdWorkflowId);
      expect(retrievedWorkflow.name, 'Enterprise Onboarding Pipeline $testRunId');
      expect(retrievedWorkflow.isActive, isTrue);
    });

    test('9. Create a new task, 10. Select created client, 11. Select created workflow, 12. Save task', () async {
      final task = await taskService.createTask(
        TaskCreateRequest(
          title: 'Execute Infrastructure Milestone $testRunId',
          description: 'Deploy PostgreSQL clustering and configure JWT tokens',
          subjectLine: 'Milestone Execution Plan',
          clientId: createdClientId,
          workflowId: createdWorkflowId,
          priority: 'urgent',
          dueDate: DateTime.now().add(const Duration(days: 3)),
          nextActionDate: DateTime.now().add(const Duration(days: 1)),
          maxAttempts: 3,
        ),
      );

      expect(task.id, isNotEmpty);
      expect(task.title, 'Execute Infrastructure Milestone $testRunId');
      expect(task.clientId, createdClientId);
      expect(task.workflowId, createdWorkflowId);
      expect(task.priority, 'urgent');
      createdTaskId = task.id;
    });

    test('13. Open task detail, 14. Verify client is displayed, 15. Verify workflow is displayed', () async {
      final task = await taskService.getTask(createdTaskId);
      expect(task.id, createdTaskId);
      expect(task.clientId, createdClientId);
      expect(task.workflowId, createdWorkflowId);

      // Verify client and workflow details can be loaded from their foreign keys
      final client = await clientService.getClient(task.clientId!);
      expect(client.id, createdClientId);
      expect(client.name, 'Acme Apex Enterprises $testRunId');

      final workflow = await workflowService.getWorkflow(task.workflowId!);
      expect(workflow.id, createdWorkflowId);
      expect(workflow.name, 'Enterprise Onboarding Pipeline $testRunId');
    });

    test('16. Open client from task and 17. Verify related task appears', () async {
      final clientTasks = await taskService.getTasks(clientId: createdClientId);
      expect(clientTasks.items.any((t) => t.id == createdTaskId), isTrue);
      final foundTask = clientTasks.items.firstWhere((t) => t.id == createdTaskId);
      expect(foundTask.title, 'Execute Infrastructure Milestone $testRunId');
    });

    test('18. Open workflow from task and 19. Verify related task appears', () async {
      final workflowTasks = await taskService.getTasks(workflowId: createdWorkflowId);
      expect(workflowTasks.items.any((t) => t.id == createdTaskId), isTrue);
      final foundTask = workflowTasks.items.firstWhere((t) => t.id == createdTaskId);
      expect(foundTask.title, 'Execute Infrastructure Milestone $testRunId');
    });

    test('20. Filter tasks by client and 21. Verify correct task appears', () async {
      final filteredTasks = await taskService.getTasks(clientId: createdClientId);
      expect(filteredTasks.items.length, 1);
      expect(filteredTasks.items.first.id, createdTaskId);
      expect(filteredTasks.items.first.clientId, createdClientId);
    });

    test('22. Filter tasks by workflow and 23. Verify correct task appears', () async {
      final filteredTasks = await taskService.getTasks(workflowId: createdWorkflowId);
      expect(filteredTasks.items.length, 1);
      expect(filteredTasks.items.first.id, createdTaskId);
      expect(filteredTasks.items.first.workflowId, createdWorkflowId);
    });

    test('24. Refresh application and 25. Verify relationships persist from PostgreSQL', () async {
      // Create new ApiClient instance to simulate full app restart
      final freshApiClient = ApiClient(tokenStorage: tokenStorage);
      final freshTaskService = TaskService(apiClient: freshApiClient);
      final freshClientService = ClientService(apiClient: freshApiClient);
      final freshWorkflowService = WorkflowService(apiClient: freshApiClient);

      final persistedTask = await freshTaskService.getTask(createdTaskId);
      expect(persistedTask.id, createdTaskId);
      expect(persistedTask.clientId, createdClientId);
      expect(persistedTask.workflowId, createdWorkflowId);

      final persistedClient = await freshClientService.getClient(createdClientId);
      expect(persistedClient.id, createdClientId);

      final persistedWorkflow = await freshWorkflowService.getWorkflow(createdWorkflowId);
      expect(persistedWorkflow.id, createdWorkflowId);

      final clientTasks = await freshTaskService.getTasks(clientId: createdClientId);
      expect(clientTasks.items.any((t) => t.id == createdTaskId), isTrue);
    });
  });
}
