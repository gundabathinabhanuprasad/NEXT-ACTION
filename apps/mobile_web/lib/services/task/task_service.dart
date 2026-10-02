import '../../core/network/api_client.dart';
import '../../models/follow_up/follow_up_models.dart';
import '../../models/history/task_history_models.dart';
import '../../models/reminder/reminder_models.dart';
import '../../models/task/task_models.dart';

/// Service for executing all Task operations against the FastAPI REST API.
class TaskService {
  final ApiClient _apiClient;

  TaskService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve paginated tasks with search, advanced filtering, and sorting.
  Future<TaskListResponse> getTasks({
    String? search,
    String? status,
    String? priority,
    String? assignedUserId,
    bool? unassigned,
    String? clientId,
    String? workflowId,
    DateTime? dueFrom,
    DateTime? dueTo,
    DateTime? nextActionFrom,
    DateTime? nextActionTo,
    bool? overdue,
    bool? dueToday,
    bool? upcoming,
    bool? hasNextAction,
    bool? noNextAction,
    bool? nearMaxAttempts,
    DateTime? dueDateBefore,
    DateTime? nextActionBefore,
    String? sortBy,
    String? sortOrder,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, dynamic>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (status != null && status != 'all') 'status': status,
      if (priority != null && priority != 'all') 'priority': priority,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      if (unassigned != null) 'unassigned': unassigned,
      if (clientId != null && clientId != 'all') 'client_id': clientId,
      if (workflowId != null && workflowId != 'all') 'workflow_id': workflowId,
      if (dueFrom != null) 'due_from': dueFrom.toIso8601String(),
      if (dueTo != null) 'due_to': dueTo.toIso8601String(),
      if (nextActionFrom != null) 'next_action_from': nextActionFrom.toIso8601String(),
      if (nextActionTo != null) 'next_action_to': nextActionTo.toIso8601String(),
      if (overdue != null) 'overdue': overdue,
      if (dueToday != null) 'due_today': dueToday,
      if (upcoming != null) 'upcoming': upcoming,
      if (hasNextAction != null) 'has_next_action': hasNextAction,
      if (noNextAction != null) 'no_next_action': noNextAction,
      if (nearMaxAttempts != null) 'near_max_attempts': nearMaxAttempts,
      if (dueDateBefore != null) 'due_date_before': dueDateBefore.toIso8601String(),
      if (nextActionBefore != null) 'next_action_before': nextActionBefore.toIso8601String(),
      if (sortBy != null) 'sort_by': sortBy,
      if (sortOrder != null) 'sort_order': sortOrder,
      'page': page,
      'page_size': pageSize,
    };

    final response = await _apiClient.get(
      '/tasks',
      queryParameters: queryParams,
      requiresAuth: true,
    );

    return TaskListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve a specific task by its ID.
  Future<Task> getTask(String taskId) async {
    final response = await _apiClient.get('/tasks/$taskId', requiresAuth: true);
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Create a new task.
  Future<Task> createTask(TaskCreateRequest request) async {
    final response = await _apiClient.post(
      '/tasks',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Update basic fields on an existing task.
  Future<Task> updateTask(String taskId, TaskUpdateRequest request) async {
    final response = await _apiClient.patch(
      '/tasks/$taskId',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Record a normal work attempt on a task.
  Future<Task> recordAttempt(String taskId, {String? notes}) async {
    final payload = AttemptRequest(notes: notes);
    final response = await _apiClient.post(
      '/tasks/$taskId/attempt',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Record an authorized override attempt with mandatory reason.
  Future<Task> recordOverrideAttempt(
    String taskId, {
    required String reason,
    bool authorizedOverride = true,
  }) async {
    final payload = OverrideAttemptRequest(
      authorizedOverride: authorizedOverride,
      reason: reason,
    );
    final response = await _apiClient.post(
      '/tasks/$taskId/attempt/override',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Postpone task due date with mandatory reason.
  Future<Task> postponeTask(
    String taskId, {
    required DateTime newDueDate,
    required String reason,
  }) async {
    final payload = PostponeTaskRequest(
      newDueDate: newDueDate,
      reason: reason,
    );
    final response = await _apiClient.post(
      '/tasks/$taskId/postpone',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Update next action date for a task.
  Future<Task> updateNextActionDate(
    String taskId, {
    DateTime? nextActionDate,
  }) async {
    final payload = NextActionDateRequest(nextActionDate: nextActionDate);
    final response = await _apiClient.post(
      '/tasks/$taskId/next-action',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Mark a task as completed.
  Future<Task> completeTask(String taskId) async {
    final response = await _apiClient.post(
      '/tasks/$taskId/complete',
      body: const {},
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Reopen a completed task with mandatory justification reason.
  Future<Task> reopenTask(String taskId, {required String reason}) async {
    final payload = ReopenTaskRequest(reason: reason);
    final response = await _apiClient.post(
      '/tasks/$taskId/reopen',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Change status of a task.
  Future<Task> changeStatus(
    String taskId, {
    required String status,
    String? reason,
  }) async {
    final payload = StatusChangeRequest(status: status, reason: reason);
    final response = await _apiClient.post(
      '/tasks/$taskId/status',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Change priority of a task.
  Future<Task> changePriority(
    String taskId, {
    required String priority,
    String? reason,
  }) async {
    final payload = PriorityChangeRequest(priority: priority, reason: reason);
    final response = await _apiClient.post(
      '/tasks/$taskId/priority',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Assign or reassign a task.
  Future<Task> assignTask(String taskId, {String? assignedUserId}) async {
    final payload = AssignmentChangeRequest(assignedUserId: assignedUserId);
    final response = await _apiClient.post(
      '/tasks/$taskId/assign',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Update subject line for a task.
  Future<Task> changeSubjectLine(String taskId, {String? subjectLine}) async {
    final payload = SubjectLineChangeRequest(subjectLine: subjectLine);
    final response = await _apiClient.post(
      '/tasks/$taskId/subject-line',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return Task.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve chronological audit history for a task.
  Future<List<TaskHistory>> getTaskHistory(
    String taskId, {
    String? action,
    String? actorId,
    String order = 'asc',
    int? page,
    int? pageSize,
  }) async {
    final queryParams = <String, String>{
      if (action != null && action.isNotEmpty) 'action': action,
      if (actorId != null && actorId.isNotEmpty) 'actor_id': actorId,
      'order': order,
      if (page != null) 'page': page.toString(),
      if (pageSize != null) 'page_size': pageSize.toString(),
    };
    final queryString = queryParams.isNotEmpty
        ? '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';
    final response = await _apiClient.get('/tasks/$taskId/history$queryString', requiresAuth: true);
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => TaskHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Retrieve follow-ups for a task.
  Future<List<FollowUp>> getTaskFollowUps(String taskId) async {
    final response = await _apiClient.get('/tasks/$taskId/follow-ups', requiresAuth: true);
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => FollowUp.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a follow-up for a task.
  Future<FollowUp> createFollowUp(FollowUpCreateRequest request) async {
    final response = await _apiClient.post(
      '/follow-ups',
      body: request.toJson(),
      requiresAuth: true,
    );
    return FollowUp.fromJson(response as Map<String, dynamic>);
  }

  /// Mark a follow-up as completed.
  Future<FollowUp> completeFollowUp(
    String followUpId, {
    DateTime? completedAt,
    String? notes,
  }) async {
    final payload = FollowUpCompleteRequest(
      completedAt: completedAt,
      notes: notes,
    );
    final response = await _apiClient.post(
      '/follow-ups/$followUpId/complete',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return FollowUp.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve reminders for a task.
  Future<List<Reminder>> getTaskReminders(String taskId) async {
    final response = await _apiClient.get('/tasks/$taskId/reminders', requiresAuth: true);
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a reminder for a task. Invariant: Does NOT change task attempt count.
  Future<Reminder> createReminder(ReminderCreateRequest request) async {
    final response = await _apiClient.post(
      '/reminders',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Reminder.fromJson(response as Map<String, dynamic>);
  }

  /// Send/process a reminder. Invariant: Does NOT change task attempt count.
  Future<Reminder> sendReminder(String reminderId) async {
    final response = await _apiClient.post(
      '/reminders/$reminderId/send',
      body: const {},
      requiresAuth: true,
    );
    return Reminder.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve recent activity history logs across all tasks.
  Future<List<TaskHistory>> getRecentActivity({
    int limit = 20,
    String? action,
    String? taskId,
    String? actorId,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      if (action != null && action.isNotEmpty) 'action': action,
      if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
      if (actorId != null && actorId.isNotEmpty) 'actor_id': actorId,
    };
    final queryString = '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    final response = await _apiClient.get(
      '/tasks/activity/recent$queryString',
      requiresAuth: true,
    );
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => TaskHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Retrieve paginated chronological activity logs across all accessible tasks.
  Future<TaskHistoryListResponse> getActivity({
    int page = 1,
    int pageSize = 20,
    String? action,
    String? taskId,
    String? actorId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (action != null && action.isNotEmpty) 'action': action,
      if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
      if (actorId != null && actorId.isNotEmpty) 'actor_id': actorId,
      if (startDate != null) 'start_date': startDate.toUtc().toIso8601String(),
      if (endDate != null) 'end_date': endDate.toUtc().toIso8601String(),
    };
    final queryString = '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    final response = await _apiClient.get(
      '/activity$queryString',
      requiresAuth: true,
    );
    return TaskHistoryListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve all follow-ups with optional task or completion filter.
  Future<List<FollowUp>> getFollowUps({
    String? taskId,
    bool? isCompleted,
  }) async {
    final queryParams = <String, String>{};
    if (taskId != null) queryParams['task_id'] = taskId;
    if (isCompleted != null) queryParams['is_completed'] = isCompleted.toString();

    final queryString = queryParams.isNotEmpty
        ? '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';

    final response = await _apiClient.get('/follow-ups$queryString', requiresAuth: true);
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => FollowUp.fromJson(e as Map<String, dynamic>)).toList();
  }
}
