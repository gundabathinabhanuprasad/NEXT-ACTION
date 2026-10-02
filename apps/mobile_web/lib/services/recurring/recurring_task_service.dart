import '../../core/network/api_client.dart';
import '../../models/recurring/recurring_task_models.dart';

/// Service for managing Recurring Tasks and triggering evaluation in NextAction.
class RecurringTaskService {
  final ApiClient apiClient;

  RecurringTaskService({required this.apiClient});

  /// Create a new recurring task schedule definition.
  Future<RecurringTask> createRecurringTask({
    required String name,
    required DateTime startDate,
    String? templateId,
    String? description,
    String? subjectLine,
    String? workflowId,
    String? clientId,
    String? assignedUserId,
    String priority = 'medium',
    int maxAttempts = 2,
    int? dueOffsetDays,
    int? nextActionOffsetDays,
    String recurrenceType = 'daily',
    int interval = 1,
    int? dayOfWeek,
    int? dayOfMonth,
    DateTime? endDate,
    bool isActive = true,
  }) async {
    final payload = {
      'name': name,
      'start_date': startDate.toIso8601String(),
      if (templateId != null) 'template_id': templateId,
      if (description != null && description.isNotEmpty) 'description': description,
      if (subjectLine != null && subjectLine.isNotEmpty) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      'priority': priority.toLowerCase(),
      'max_attempts': maxAttempts,
      if (dueOffsetDays != null) 'due_offset_days': dueOffsetDays,
      if (nextActionOffsetDays != null) 'next_action_offset_days': nextActionOffsetDays,
      'recurrence_type': recurrenceType.toLowerCase(),
      'interval': interval,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (dayOfMonth != null) 'day_of_month': dayOfMonth,
      if (endDate != null) 'end_date': endDate.toIso8601String(),
      'is_active': isActive,
    };

    final response = await apiClient.post('/recurring-tasks', body: payload);
    return RecurringTask.fromJson(response as Map<String, dynamic>);
  }

  /// List recurring tasks with search, active filter, and pagination.
  Future<RecurringTaskListResponse> getRecurringTasks({
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

    final response = await apiClient.get('/recurring-tasks', queryParameters: queryParams);
    return RecurringTaskListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve a single recurring task by ID.
  Future<RecurringTask> getRecurringTask(String recurringTaskId) async {
    final response = await apiClient.get('/recurring-tasks/$recurringTaskId');
    return RecurringTask.fromJson(response as Map<String, dynamic>);
  }

  /// Update an existing recurring task schedule definition.
  Future<RecurringTask> updateRecurringTask({
    required String recurringTaskId,
    String? name,
    String? templateId,
    String? description,
    String? subjectLine,
    String? workflowId,
    String? clientId,
    String? assignedUserId,
    String? priority,
    int? maxAttempts,
    int? dueOffsetDays,
    int? nextActionOffsetDays,
    String? recurrenceType,
    int? interval,
    int? dayOfWeek,
    int? dayOfMonth,
    DateTime? startDate,
    DateTime? nextRunAt,
    DateTime? endDate,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (templateId != null) 'template_id': templateId,
      if (description != null) 'description': description,
      if (subjectLine != null) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      if (priority != null) 'priority': priority.toLowerCase(),
      if (maxAttempts != null) 'max_attempts': maxAttempts,
      if (dueOffsetDays != null) 'due_offset_days': dueOffsetDays,
      if (nextActionOffsetDays != null) 'next_action_offset_days': nextActionOffsetDays,
      if (recurrenceType != null) 'recurrence_type': recurrenceType.toLowerCase(),
      if (interval != null) 'interval': interval,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (dayOfMonth != null) 'day_of_month': dayOfMonth,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (nextRunAt != null) 'next_run_at': nextRunAt.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
      if (isActive != null) 'is_active': isActive,
    };

    final response = await apiClient.patch('/recurring-tasks/$recurringTaskId', body: payload);
    return RecurringTask.fromJson(response as Map<String, dynamic>);
  }

  /// Delete a recurring task.
  Future<void> deleteRecurringTask(String recurringTaskId) async {
    await apiClient.delete('/recurring-tasks/$recurringTaskId');
  }

  /// Trigger evaluation of due recurring tasks to generate task instances.
  Future<RecurringTaskEvaluationResponse> evaluateRecurringTasks({
    int maxEvaluations = 50,
  }) async {
    final response = await apiClient.post(
      '/recurring-tasks/evaluate',
      body: {'max_evaluations': maxEvaluations},
    );
    return RecurringTaskEvaluationResponse.fromJson(response as Map<String, dynamic>);
  }
}
