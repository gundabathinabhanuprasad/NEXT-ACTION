import '../../core/network/api_client.dart';
import '../../models/task/task_models.dart';
import '../../models/template/task_template_models.dart';

/// Service for managing Task Templates and instantiating tasks from templates.
class TaskTemplateService {
  final ApiClient apiClient;

  TaskTemplateService({required this.apiClient});

  /// Create a new TaskTemplate blueprint.
  Future<TaskTemplate> createTemplate({
    required String name,
    String? description,
    String? subjectLine,
    String? workflowId,
    String? clientId,
    String? assignedUserId,
    String priority = 'medium',
    int maxAttempts = 2,
    int? defaultDueOffsetDays,
    int? defaultNextActionOffsetDays,
    bool isActive = true,
  }) async {
    final payload = {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      if (subjectLine != null && subjectLine.isNotEmpty) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      'priority': priority.toLowerCase(),
      'max_attempts': maxAttempts,
      if (defaultDueOffsetDays != null) 'default_due_offset_days': defaultDueOffsetDays,
      if (defaultNextActionOffsetDays != null) 'default_next_action_offset_days': defaultNextActionOffsetDays,
      'is_active': isActive,
    };

    final response = await apiClient.post('/task-templates', body: payload);
    return TaskTemplate.fromJson(response as Map<String, dynamic>);
  }

  /// List templates with search, active filter, and pagination.
  Future<TaskTemplateListResponse> getTemplates({
    String? search,
    bool? isActive,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (isActive != null) 'is_active': isActive.toString(),
    };

    final response = await apiClient.get('/task-templates', queryParameters: queryParams);
    return TaskTemplateListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve a single template by ID.
  Future<TaskTemplate> getTemplate(String templateId) async {
    final response = await apiClient.get('/task-templates/$templateId');
    return TaskTemplate.fromJson(response as Map<String, dynamic>);
  }

  /// Update an existing template.
  Future<TaskTemplate> updateTemplate({
    required String templateId,
    String? name,
    String? description,
    String? subjectLine,
    String? workflowId,
    String? clientId,
    String? assignedUserId,
    String? priority,
    int? maxAttempts,
    int? defaultDueOffsetDays,
    int? defaultNextActionOffsetDays,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (subjectLine != null) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      if (priority != null) 'priority': priority.toLowerCase(),
      if (maxAttempts != null) 'max_attempts': maxAttempts,
      if (defaultDueOffsetDays != null) 'default_due_offset_days': defaultDueOffsetDays,
      if (defaultNextActionOffsetDays != null) 'default_next_action_offset_days': defaultNextActionOffsetDays,
      if (isActive != null) 'is_active': isActive,
    };

    final response = await apiClient.patch('/task-templates/$templateId', body: payload);
    return TaskTemplate.fromJson(response as Map<String, dynamic>);
  }

  /// Delete a template.
  Future<void> deleteTemplate(String templateId) async {
    await apiClient.delete('/task-templates/$templateId');
  }

  /// Instantiate a concrete Task from a TaskTemplate.
  Future<Task> createTaskFromTemplate({
    required String templateId,
    String? title,
    String? description,
    String? subjectLine,
    String? workflowId,
    String? clientId,
    String? assignedUserId,
    String? priority,
    int? maxAttempts,
    DateTime? dueDate,
    DateTime? nextActionDate,
  }) async {
    final payload = <String, dynamic>{
      if (title != null && title.isNotEmpty) 'title': title,
      if (description != null) 'description': description,
      if (subjectLine != null) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      if (priority != null) 'priority': priority.toLowerCase(),
      if (maxAttempts != null) 'max_attempts': maxAttempts,
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
      if (nextActionDate != null) 'next_action_date': nextActionDate.toIso8601String(),
    };

    final response = await apiClient.post(
      '/task-templates/$templateId/create-task',
      body: payload,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }
}
