// Phase 17: Reports, Exports & Management Insights Models.

enum ReportType {
  taskSummary('task_summary', 'Task Summary Report'),
  taskDetail('task_detail', 'Task Detail Report'),
  productivity('productivity', 'Productivity Report'),
  workload('workload', 'Workload Report'),
  activity('activity', 'Activity Audit Report'),
  remindersFollowups('reminders_followups', 'Scheduling Queues Report');

  final String apiValue;
  final String displayName;

  const ReportType(this.apiValue, this.displayName);

  static ReportType fromApiValue(String val) {
    return ReportType.values.firstWhere(
      (e) => e.apiValue == val,
      orElse: () => ReportType.taskSummary,
    );
  }
}

enum ExportFormat {
  csv('csv', 'CSV (Spreadsheet)'),
  json('json', 'JSON (Data Format)');

  final String apiValue;
  final String displayName;

  const ExportFormat(this.apiValue, this.displayName);
}

class ReportFilters {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? status;
  final String? priority;
  final String? clientId;
  final String? workflowId;
  final String? assignedUserId;
  final bool? unassigned;
  final bool? overdue;
  final bool? dueToday;
  final bool? upcoming;
  final bool? hasNextAction;
  final bool? noNextAction;
  final bool? nearMaxAttempts;
  final String? search;
  final String? source;

  const ReportFilters({
    this.dateFrom,
    this.dateTo,
    this.status,
    this.priority,
    this.clientId,
    this.workflowId,
    this.assignedUserId,
    this.unassigned,
    this.overdue,
    this.dueToday,
    this.upcoming,
    this.hasNextAction,
    this.noNextAction,
    this.nearMaxAttempts,
    this.search,
    this.source,
  });

  ReportFilters copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
    String? priority,
    String? clientId,
    String? workflowId,
    String? assignedUserId,
    bool? unassigned,
    bool? overdue,
    bool? dueToday,
    bool? upcoming,
    bool? hasNextAction,
    bool? noNextAction,
    bool? nearMaxAttempts,
    String? search,
    String? source,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearClientId = false,
    bool clearWorkflowId = false,
    bool clearAssignedUserId = false,
    bool clearUnassigned = false,
    bool clearOverdue = false,
    bool clearDueToday = false,
    bool clearUpcoming = false,
    bool clearHasNextAction = false,
    bool clearNoNextAction = false,
    bool clearNearMaxAttempts = false,
    bool clearSearch = false,
    bool clearSource = false,
  }) {
    return ReportFilters(
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      status: clearStatus ? null : (status ?? this.status),
      priority: clearPriority ? null : (priority ?? this.priority),
      clientId: clearClientId ? null : (clientId ?? this.clientId),
      workflowId: clearWorkflowId ? null : (workflowId ?? this.workflowId),
      assignedUserId: clearAssignedUserId ? null : (assignedUserId ?? this.assignedUserId),
      unassigned: clearUnassigned ? null : (unassigned ?? this.unassigned),
      overdue: clearOverdue ? null : (overdue ?? this.overdue),
      dueToday: clearDueToday ? null : (dueToday ?? this.dueToday),
      upcoming: clearUpcoming ? null : (upcoming ?? this.upcoming),
      hasNextAction: clearHasNextAction ? null : (hasNextAction ?? this.hasNextAction),
      noNextAction: clearNoNextAction ? null : (noNextAction ?? this.noNextAction),
      nearMaxAttempts: clearNearMaxAttempts ? null : (nearMaxAttempts ?? this.nearMaxAttempts),
      search: clearSearch ? null : (search ?? this.search),
      source: clearSource ? null : (source ?? this.source),
    );
  }

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (dateFrom != null) params['date_from'] = dateFrom!.toUtc().toIso8601String();
    if (dateTo != null) params['date_to'] = dateTo!.toUtc().toIso8601String();
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (priority != null && priority!.isNotEmpty) params['priority'] = priority!;
    if (clientId != null && clientId!.isNotEmpty) params['client_id'] = clientId!;
    if (workflowId != null && workflowId!.isNotEmpty) params['workflow_id'] = workflowId!;
    if (assignedUserId != null && assignedUserId!.isNotEmpty) params['assigned_user_id'] = assignedUserId!;
    if (unassigned == true) params['unassigned'] = 'true';
    if (overdue == true) params['overdue'] = 'true';
    if (dueToday == true) params['due_today'] = 'true';
    if (upcoming == true) params['upcoming'] = 'true';
    if (hasNextAction == true) params['has_next_action'] = 'true';
    if (noNextAction == true) params['no_next_action'] = 'true';
    if (nearMaxAttempts == true) params['near_max_attempts'] = 'true';
    if (search != null && search!.trim().isNotEmpty) params['search'] = search!.trim();
    if (source != null && source!.isNotEmpty) params['source'] = source!;
    return params;
  }
}

// =============================================================================
// 1. Task Summary Models
// =============================================================================

class TaskSummaryStatusBreakdown {
  final int pending;
  final int inProgress;
  final int completed;
  final int cancelled;

  const TaskSummaryStatusBreakdown({
    required this.pending,
    required this.inProgress,
    required this.completed,
    required this.cancelled,
  });

  factory TaskSummaryStatusBreakdown.fromJson(Map<String, dynamic> json) {
    return TaskSummaryStatusBreakdown(
      pending: json['pending'] as int? ?? 0,
      inProgress: json['in_progress'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      cancelled: json['cancelled'] as int? ?? 0,
    );
  }
}

class TaskSummaryPriorityBreakdown {
  final int urgent;
  final int high;
  final int medium;
  final int low;

  const TaskSummaryPriorityBreakdown({
    required this.urgent,
    required this.high,
    required this.medium,
    required this.low,
  });

  factory TaskSummaryPriorityBreakdown.fromJson(Map<String, dynamic> json) {
    return TaskSummaryPriorityBreakdown(
      urgent: json['urgent'] as int? ?? 0,
      high: json['high'] as int? ?? 0,
      medium: json['medium'] as int? ?? 0,
      low: json['low'] as int? ?? 0,
    );
  }
}

class TaskSummaryReport {
  final int totalTasks;
  final int openTasks;
  final int completedTasks;
  final int cancelledTasks;
  final int overdueTasks;
  final int dueTodayTasks;
  final int upcomingTasks;
  final int nearMaxAttempts;
  final int maxAttemptsReached;
  final TaskSummaryStatusBreakdown statusBreakdown;
  final TaskSummaryPriorityBreakdown priorityBreakdown;

  const TaskSummaryReport({
    required this.totalTasks,
    required this.openTasks,
    required this.completedTasks,
    required this.cancelledTasks,
    required this.overdueTasks,
    required this.dueTodayTasks,
    required this.upcomingTasks,
    required this.nearMaxAttempts,
    required this.maxAttemptsReached,
    required this.statusBreakdown,
    required this.priorityBreakdown,
  });

  factory TaskSummaryReport.fromJson(Map<String, dynamic> json) {
    return TaskSummaryReport(
      totalTasks: json['total_tasks'] as int? ?? 0,
      openTasks: json['open_tasks'] as int? ?? 0,
      completedTasks: json['completed_tasks'] as int? ?? 0,
      cancelledTasks: json['cancelled_tasks'] as int? ?? 0,
      overdueTasks: json['overdue_tasks'] as int? ?? 0,
      dueTodayTasks: json['due_today_tasks'] as int? ?? 0,
      upcomingTasks: json['upcoming_tasks'] as int? ?? 0,
      nearMaxAttempts: json['near_max_attempts'] as int? ?? 0,
      maxAttemptsReached: json['max_attempts_reached'] as int? ?? 0,
      statusBreakdown: TaskSummaryStatusBreakdown.fromJson(
        json['status_breakdown'] as Map<String, dynamic>? ?? {},
      ),
      priorityBreakdown: TaskSummaryPriorityBreakdown.fromJson(
        json['priority_breakdown'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

// =============================================================================
// 2. Task Detail Report Models
// =============================================================================

class TaskDetailReportItem {
  final String id;
  final String title;
  final String? subjectLine;
  final String? description;
  final String status;
  final String priority;
  final String? clientId;
  final String? clientName;
  final String? workflowId;
  final String? workflowName;
  final String? assignedUserId;
  final String? assignedUserName;
  final String? assignedUserEmail;
  final DateTime? dueDate;
  final DateTime? nextActionDate;
  final int attemptCount;
  final int maxAttempts;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String source;

  const TaskDetailReportItem({
    required this.id,
    required this.title,
    this.subjectLine,
    this.description,
    required this.status,
    required this.priority,
    this.clientId,
    this.clientName,
    this.workflowId,
    this.workflowName,
    this.assignedUserId,
    this.assignedUserName,
    this.assignedUserEmail,
    this.dueDate,
    this.nextActionDate,
    required this.attemptCount,
    required this.maxAttempts,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    required this.source,
  });

  factory TaskDetailReportItem.fromJson(Map<String, dynamic> json) {
    return TaskDetailReportItem(
      id: json['id'] as String,
      title: json['title'] as String,
      subjectLine: json['subject_line'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'pending',
      priority: json['priority'] as String? ?? 'medium',
      clientId: json['client_id'] as String?,
      clientName: json['client_name'] as String?,
      workflowId: json['workflow_id'] as String?,
      workflowName: json['workflow_name'] as String?,
      assignedUserId: json['assigned_user_id'] as String?,
      assignedUserName: json['assigned_user_name'] as String?,
      assignedUserEmail: json['assigned_user_email'] as String?,
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'] as String) : null,
      nextActionDate: json['next_action_date'] != null ? DateTime.tryParse(json['next_action_date'] as String) : null,
      attemptCount: json['attempt_count'] as int? ?? 0,
      maxAttempts: json['max_attempts'] as int? ?? 2,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'] as String) : null,
      source: json['source'] as String? ?? 'manual',
    );
  }
}

class TaskDetailReportResponse {
  final List<TaskDetailReportItem> items;
  final int total;
  final int page;
  final int pageSize;

  const TaskDetailReportResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory TaskDetailReportResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List<dynamic>? ?? [])
        .map((e) => TaskDetailReportItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return TaskDetailReportResponse(
      items: list,
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }
}

// =============================================================================
// 3. Productivity Report Models
// =============================================================================

class ProductivityDailyTrendPoint {
  final String date;
  final int createdCount;
  final int completedCount;
  final int overdueCount;
  final double completionRate;

  const ProductivityDailyTrendPoint({
    required this.date,
    required this.createdCount,
    required this.completedCount,
    required this.overdueCount,
    required this.completionRate,
  });

  factory ProductivityDailyTrendPoint.fromJson(Map<String, dynamic> json) {
    return ProductivityDailyTrendPoint(
      date: json['date'] as String,
      createdCount: json['created_count'] as int? ?? 0,
      completedCount: json['completed_count'] as int? ?? 0,
      overdueCount: json['overdue_count'] as int? ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ProductivityReportResponse {
  final DateTime dateFrom;
  final DateTime dateTo;
  final int totalCreated;
  final int totalCompleted;
  final int totalOverdue;
  final double overallCompletionRate;
  final List<ProductivityDailyTrendPoint> dailyTrends;

  const ProductivityReportResponse({
    required this.dateFrom,
    required this.dateTo,
    required this.totalCreated,
    required this.totalCompleted,
    required this.totalOverdue,
    required this.overallCompletionRate,
    required this.dailyTrends,
  });

  factory ProductivityReportResponse.fromJson(Map<String, dynamic> json) {
    final trends = (json['daily_trends'] as List<dynamic>? ?? [])
        .map((e) => ProductivityDailyTrendPoint.fromJson(e as Map<String, dynamic>))
        .toList();

    return ProductivityReportResponse(
      dateFrom: DateTime.parse(json['date_from'] as String),
      dateTo: DateTime.parse(json['date_to'] as String),
      totalCreated: json['total_created'] as int? ?? 0,
      totalCompleted: json['total_completed'] as int? ?? 0,
      totalOverdue: json['total_overdue'] as int? ?? 0,
      overallCompletionRate: (json['overall_completion_rate'] as num?)?.toDouble() ?? 0.0,
      dailyTrends: trends,
    );
  }
}

// =============================================================================
// 4. Workload Report Models
// =============================================================================

class WorkloadReportItem {
  final String? id;
  final String name;
  final String? email;
  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int dueTodayTasks;
  final int totalTasks;

  const WorkloadReportItem({
    this.id,
    required this.name,
    this.email,
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.dueTodayTasks,
    required this.totalTasks,
  });

  factory WorkloadReportItem.fromJson(Map<String, dynamic> json) {
    return WorkloadReportItem(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Unknown',
      email: json['email'] as String?,
      openTasks: json['open_tasks'] as int? ?? 0,
      completedTasks: json['completed_tasks'] as int? ?? 0,
      overdueTasks: json['overdue_tasks'] as int? ?? 0,
      dueTodayTasks: json['due_today_tasks'] as int? ?? 0,
      totalTasks: json['total_tasks'] as int? ?? 0,
    );
  }
}

class WorkloadReportResponse {
  final List<WorkloadReportItem> byAssignee;
  final List<WorkloadReportItem> byClient;
  final List<WorkloadReportItem> byWorkflow;
  final int totalOpenTasks;
  final int totalCompletedTasks;
  final int totalOverdueTasks;
  final int totalTasks;

  const WorkloadReportResponse({
    required this.byAssignee,
    required this.byClient,
    required this.byWorkflow,
    required this.totalOpenTasks,
    required this.totalCompletedTasks,
    required this.totalOverdueTasks,
    required this.totalTasks,
  });

  factory WorkloadReportResponse.fromJson(Map<String, dynamic> json) {
    return WorkloadReportResponse(
      byAssignee: (json['by_assignee'] as List<dynamic>? ?? [])
          .map((e) => WorkloadReportItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      byClient: (json['by_client'] as List<dynamic>? ?? [])
          .map((e) => WorkloadReportItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      byWorkflow: (json['by_workflow'] as List<dynamic>? ?? [])
          .map((e) => WorkloadReportItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalOpenTasks: json['total_open_tasks'] as int? ?? 0,
      totalCompletedTasks: json['total_completed_tasks'] as int? ?? 0,
      totalOverdueTasks: json['total_overdue_tasks'] as int? ?? 0,
      totalTasks: json['total_tasks'] as int? ?? 0,
    );
  }
}

// =============================================================================
// 5. Activity Report Models
// =============================================================================

class ActivityReportItem {
  final String id;
  final String? taskId;
  final String? taskTitle;
  final String action;
  final String? actorId;
  final String? actorName;
  final String? actorEmail;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final DateTime createdAt;

  const ActivityReportItem({
    required this.id,
    this.taskId,
    this.taskTitle,
    required this.action,
    this.actorId,
    this.actorName,
    this.actorEmail,
    this.oldValue,
    this.newValue,
    this.reason,
    required this.createdAt,
  });

  factory ActivityReportItem.fromJson(Map<String, dynamic> json) {
    return ActivityReportItem(
      id: json['id'] as String,
      taskId: json['task_id'] as String?,
      taskTitle: json['task_title'] as String?,
      action: json['action'] as String,
      actorId: json['actor_id'] as String?,
      actorName: json['actor_name'] as String?,
      actorEmail: json['actor_email'] as String?,
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ActivityReportResponse {
  final List<ActivityReportItem> items;
  final int total;
  final int page;
  final int pageSize;
  final Map<String, int> actionCounts;

  const ActivityReportResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.actionCounts,
  });

  factory ActivityReportResponse.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['action_counts'] as Map<String, dynamic>? ?? {};
    final counts = rawCounts.map((k, v) => MapEntry(k, v as int? ?? 0));

    return ActivityReportResponse(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => ActivityReportItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
      actionCounts: counts,
    );
  }
}

// =============================================================================
// 6. Reminder & Follow-up Report Models
// =============================================================================

class ReminderFollowUpSummary {
  final int remindersDue;
  final int remindersSent;
  final int remindersPending;
  final int remindersTotal;
  final int followUpsOverdue;
  final int followUpsToday;
  final int followUpsUpcoming;
  final int followUpsCompleted;
  final int followUpsPending;
  final int followUpsTotal;

  const ReminderFollowUpSummary({
    required this.remindersDue,
    required this.remindersSent,
    required this.remindersPending,
    required this.remindersTotal,
    required this.followUpsOverdue,
    required this.followUpsToday,
    required this.followUpsUpcoming,
    required this.followUpsCompleted,
    required this.followUpsPending,
    required this.followUpsTotal,
  });

  factory ReminderFollowUpSummary.fromJson(Map<String, dynamic> json) {
    return ReminderFollowUpSummary(
      remindersDue: json['reminders_due'] as int? ?? 0,
      remindersSent: json['reminders_sent'] as int? ?? 0,
      remindersPending: json['reminders_pending'] as int? ?? 0,
      remindersTotal: json['reminders_total'] as int? ?? 0,
      followUpsOverdue: json['follow_ups_overdue'] as int? ?? 0,
      followUpsToday: json['follow_ups_today'] as int? ?? 0,
      followUpsUpcoming: json['follow_ups_upcoming'] as int? ?? 0,
      followUpsCompleted: json['follow_ups_completed'] as int? ?? 0,
      followUpsPending: json['follow_ups_pending'] as int? ?? 0,
      followUpsTotal: json['follow_ups_total'] as int? ?? 0,
    );
  }
}

class ReminderReportItem {
  final String id;
  final String taskId;
  final String taskTitle;
  final DateTime remindAt;
  final bool isSent;
  final String message;
  final DateTime createdAt;

  const ReminderReportItem({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.remindAt,
    required this.isSent,
    required this.message,
    required this.createdAt,
  });

  factory ReminderReportItem.fromJson(Map<String, dynamic> json) {
    return ReminderReportItem(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      taskTitle: json['task_title'] as String? ?? 'Untitled Task',
      remindAt: DateTime.parse(json['remind_at'] as String),
      isSent: json['is_sent'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class FollowUpReportItem {
  final String id;
  final String taskId;
  final String taskTitle;
  final DateTime scheduledAt;
  final DateTime? completedAt;
  final String? notes;
  final bool isCompleted;
  final DateTime createdAt;

  const FollowUpReportItem({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.scheduledAt,
    this.completedAt,
    this.notes,
    required this.isCompleted,
    required this.createdAt,
  });

  factory FollowUpReportItem.fromJson(Map<String, dynamic> json) {
    return FollowUpReportItem(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      taskTitle: json['task_title'] as String? ?? 'Untitled Task',
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'] as String) : null,
      notes: json['notes'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ReminderFollowUpReportResponse {
  final ReminderFollowUpSummary summary;
  final List<ReminderReportItem> reminders;
  final List<FollowUpReportItem> followUps;

  const ReminderFollowUpReportResponse({
    required this.summary,
    required this.reminders,
    required this.followUps,
  });

  factory ReminderFollowUpReportResponse.fromJson(Map<String, dynamic> json) {
    return ReminderFollowUpReportResponse(
      summary: ReminderFollowUpSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
      reminders: (json['reminders'] as List<dynamic>? ?? [])
          .map((e) => ReminderReportItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      followUps: (json['follow_ups'] as List<dynamic>? ?? [])
          .map((e) => FollowUpReportItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
