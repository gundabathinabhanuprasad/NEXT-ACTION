import '../task/task_models.dart';

/// Model representing a RecurringTask schedule definition in NextAction.
class RecurringTask {
  final String id;
  final String? templateId;
  final String name;
  final String? description;
  final String? subjectLine;
  final String? workflowId;
  final String? clientId;
  final String? assignedUserId;
  final String priority;
  final int maxAttempts;
  final int? dueOffsetDays;
  final int? nextActionOffsetDays;
  final String recurrenceType;
  final int interval;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final bool isActive;
  final String createdByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringTask({
    required this.id,
    this.templateId,
    required this.name,
    this.description,
    this.subjectLine,
    this.workflowId,
    this.clientId,
    this.assignedUserId,
    this.priority = 'medium',
    this.maxAttempts = 2,
    this.dueOffsetDays,
    this.nextActionOffsetDays,
    this.recurrenceType = 'daily',
    this.interval = 1,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.startDate,
    this.endDate,
    required this.nextRunAt,
    this.lastRunAt,
    this.isActive = true,
    required this.createdByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RecurringTask.fromJson(Map<String, dynamic> json) {
    return RecurringTask(
      id: json['id'] as String,
      templateId: json['template_id'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      subjectLine: json['subject_line'] as String?,
      workflowId: json['workflow_id'] as String?,
      clientId: json['client_id'] as String?,
      assignedUserId: json['assigned_user_id'] as String?,
      priority: (json['priority'] as String?)?.toLowerCase() ?? 'medium',
      maxAttempts: json['max_attempts'] as int? ?? 2,
      dueOffsetDays: json['due_offset_days'] as int?,
      nextActionOffsetDays: json['next_action_offset_days'] as int?,
      recurrenceType: (json['recurrence_type'] as String?)?.toLowerCase() ?? 'daily',
      interval: json['interval'] as int? ?? 1,
      dayOfWeek: json['day_of_week'] as int?,
      dayOfMonth: json['day_of_month'] as int?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
      nextRunAt: DateTime.parse(json['next_run_at'] as String),
      lastRunAt: json['last_run_at'] != null ? DateTime.parse(json['last_run_at'] as String) : null,
      isActive: json['is_active'] as bool? ?? true,
      createdByUserId: json['created_by_user_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (templateId != null) 'template_id': templateId,
      'name': name,
      if (description != null) 'description': description,
      if (subjectLine != null) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      'priority': priority,
      'max_attempts': maxAttempts,
      if (dueOffsetDays != null) 'due_offset_days': dueOffsetDays,
      if (nextActionOffsetDays != null) 'next_action_offset_days': nextActionOffsetDays,
      'recurrence_type': recurrenceType,
      'interval': interval,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (dayOfMonth != null) 'day_of_month': dayOfMonth,
      'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate!.toIso8601String(),
      'next_run_at': nextRunAt.toIso8601String(),
      if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
      'is_active': isActive,
      'created_by_user_id': createdByUserId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Paginated list response for Recurring Tasks.
class RecurringTaskListResponse {
  final List<RecurringTask> items;
  final int total;
  final int page;
  final int pageSize;

  const RecurringTaskListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory RecurringTaskListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return RecurringTaskListResponse(
      items: rawItems
          .map((e) => RecurringTask.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }

  int get totalPages => (total / pageSize).ceil();
  bool get hasNextPage => page < totalPages;
  bool get hasPreviousPage => page > 1;
}

/// Result response of evaluating recurring tasks.
class RecurringTaskEvaluationResponse {
  final int evaluatedDefinitions;
  final int tasksCreated;
  final List<Task> createdTasks;

  const RecurringTaskEvaluationResponse({
    required this.evaluatedDefinitions,
    required this.tasksCreated,
    required this.createdTasks,
  });

  factory RecurringTaskEvaluationResponse.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['created_tasks'] as List<dynamic>? ?? [];
    return RecurringTaskEvaluationResponse(
      evaluatedDefinitions: json['evaluated_definitions'] as int? ?? 0,
      tasksCreated: json['tasks_created'] as int? ?? 0,
      createdTasks: rawTasks
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
