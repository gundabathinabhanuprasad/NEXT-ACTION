import '../../core/network/api_client.dart';
import '../../models/workflow/workflow_models.dart';

/// Service for interacting with Workflow endpoints in the FastAPI backend.
class WorkflowService {
  final ApiClient _apiClient;

  WorkflowService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve a list of workflows with optional is_active filter and pagination.
  Future<WorkflowListResponse> getWorkflows({
    bool? isActive,
    int page = 1,
    int pageSize = 100,
  }) async {
    final queryParams = <String, dynamic>{
      if (isActive != null) 'is_active': isActive,
      'page': page,
      'page_size': pageSize,
    };

    final response = await _apiClient.get(
      '/workflows',
      queryParameters: queryParams,
      requiresAuth: true,
    );

    return WorkflowListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve a single workflow by its ID.
  Future<Workflow> getWorkflow(String workflowId) async {
    final response = await _apiClient.get(
      '/workflows/$workflowId',
      requiresAuth: true,
    );
    return Workflow.fromJson(response as Map<String, dynamic>);
  }

  /// Create a new workflow.
  Future<Workflow> createWorkflow(WorkflowCreateRequest request) async {
    final response = await _apiClient.post(
      '/workflows',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Workflow.fromJson(response as Map<String, dynamic>);
  }

  /// Update an existing workflow.
  Future<Workflow> updateWorkflow(String workflowId, WorkflowUpdateRequest request) async {
    final response = await _apiClient.patch(
      '/workflows/$workflowId',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Workflow.fromJson(response as Map<String, dynamic>);
  }
}
