// Phase 18: User Settings, Personalization & System Configuration Models.

class UserSettings {
  final String id;
  final String userId;
  final String? displayNameOverride;
  final String timezone;
  final String dateFormat;
  final String timeFormat;
  final String firstDayOfWeek;

  final String theme;
  final bool compactMode;

  final String defaultTaskPriority;
  final String defaultTaskStatusFilter;
  final String defaultTaskSort;
  final String defaultTaskSortOrder;
  final int defaultMaxAttempts;
  final int defaultPageSize;

  final String defaultDashboardTimeRange;
  final String defaultReportDateRange;
  final String defaultReportType;
  final String defaultExportFormat;

  final bool notifyTaskAssigned;
  final bool notifyTaskReassigned;
  final bool notifyReminderDue;
  final bool notifyFollowUpDue;
  final bool notifyNextActionDue;
  final bool notifyTaskOverdue;
  final bool notifyAttemptLimitReached;
  final bool notifyTaskCompleted;
  final bool notifyTaskReopened;

  final DateTime createdAt;
  final DateTime updatedAt;

  const UserSettings({
    required this.id,
    required this.userId,
    this.displayNameOverride,
    this.timezone = 'UTC',
    this.dateFormat = 'YYYY-MM-DD',
    this.timeFormat = '24h',
    this.firstDayOfWeek = 'monday',
    this.theme = 'system',
    this.compactMode = false,
    this.defaultTaskPriority = 'medium',
    this.defaultTaskStatusFilter = 'all',
    this.defaultTaskSort = 'due_date',
    this.defaultTaskSortOrder = 'asc',
    this.defaultMaxAttempts = 3,
    this.defaultPageSize = 20,
    this.defaultDashboardTimeRange = 'last_7_days',
    this.defaultReportDateRange = 'last_7_days',
    this.defaultReportType = 'task_summary',
    this.defaultExportFormat = 'csv',
    this.notifyTaskAssigned = true,
    this.notifyTaskReassigned = true,
    this.notifyReminderDue = true,
    this.notifyFollowUpDue = true,
    this.notifyNextActionDue = true,
    this.notifyTaskOverdue = true,
    this.notifyAttemptLimitReached = true,
    this.notifyTaskCompleted = true,
    this.notifyTaskReopened = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayNameOverride: json['display_name_override'] as String?,
      timezone: json['timezone'] as String? ?? 'UTC',
      dateFormat: json['date_format'] as String? ?? 'YYYY-MM-DD',
      timeFormat: json['time_format'] as String? ?? '24h',
      firstDayOfWeek: json['first_day_of_week'] as String? ?? 'monday',
      theme: json['theme'] as String? ?? 'system',
      compactMode: json['compact_mode'] as bool? ?? false,
      defaultTaskPriority: json['default_task_priority'] as String? ?? 'medium',
      defaultTaskStatusFilter: json['default_task_status_filter'] as String? ?? 'all',
      defaultTaskSort: json['default_task_sort'] as String? ?? 'due_date',
      defaultTaskSortOrder: json['default_task_sort_order'] as String? ?? 'asc',
      defaultMaxAttempts: json['default_max_attempts'] as int? ?? 3,
      defaultPageSize: json['default_page_size'] as int? ?? 20,
      defaultDashboardTimeRange: json['default_dashboard_time_range'] as String? ?? 'last_7_days',
      defaultReportDateRange: json['default_report_date_range'] as String? ?? 'last_7_days',
      defaultReportType: json['default_report_type'] as String? ?? 'task_summary',
      defaultExportFormat: json['default_export_format'] as String? ?? 'csv',
      notifyTaskAssigned: json['notify_task_assigned'] as bool? ?? true,
      notifyTaskReassigned: json['notify_task_reassigned'] as bool? ?? true,
      notifyReminderDue: json['notify_reminder_due'] as bool? ?? true,
      notifyFollowUpDue: json['notify_follow_up_due'] as bool? ?? true,
      notifyNextActionDue: json['notify_next_action_due'] as bool? ?? true,
      notifyTaskOverdue: json['notify_task_overdue'] as bool? ?? true,
      notifyAttemptLimitReached: json['notify_attempt_limit_reached'] as bool? ?? true,
      notifyTaskCompleted: json['notify_task_completed'] as bool? ?? true,
      notifyTaskReopened: json['notify_task_reopened'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'display_name_override': displayNameOverride,
      'timezone': timezone,
      'date_format': dateFormat,
      'time_format': timeFormat,
      'first_day_of_week': firstDayOfWeek,
      'theme': theme,
      'compact_mode': compactMode,
      'default_task_priority': defaultTaskPriority,
      'default_task_status_filter': defaultTaskStatusFilter,
      'default_task_sort': defaultTaskSort,
      'default_task_sort_order': defaultTaskSortOrder,
      'default_max_attempts': defaultMaxAttempts,
      'default_page_size': defaultPageSize,
      'default_dashboard_time_range': defaultDashboardTimeRange,
      'default_report_date_range': defaultReportDateRange,
      'default_report_type': defaultReportType,
      'default_export_format': defaultExportFormat,
      'notify_task_assigned': notifyTaskAssigned,
      'notify_task_reassigned': notifyTaskReassigned,
      'notify_reminder_due': notifyReminderDue,
      'notify_follow_up_due': notifyFollowUpDue,
      'notify_next_action_due': notifyNextActionDue,
      'notify_task_overdue': notifyTaskOverdue,
      'notify_attempt_limit_reached': notifyAttemptLimitReached,
      'notify_task_completed': notifyTaskCompleted,
      'notify_task_reopened': notifyTaskReopened,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserSettings copyWith({
    String? id,
    String? userId,
    String? displayNameOverride,
    bool clearDisplayNameOverride = false,
    String? timezone,
    String? dateFormat,
    String? timeFormat,
    String? firstDayOfWeek,
    String? theme,
    bool? compactMode,
    String? defaultTaskPriority,
    String? defaultTaskStatusFilter,
    String? defaultTaskSort,
    String? defaultTaskSortOrder,
    int? defaultMaxAttempts,
    int? defaultPageSize,
    String? defaultDashboardTimeRange,
    String? defaultReportDateRange,
    String? defaultReportType,
    String? defaultExportFormat,
    bool? notifyTaskAssigned,
    bool? notifyTaskReassigned,
    bool? notifyReminderDue,
    bool? notifyFollowUpDue,
    bool? notifyNextActionDue,
    bool? notifyTaskOverdue,
    bool? notifyAttemptLimitReached,
    bool? notifyTaskCompleted,
    bool? notifyTaskReopened,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      displayNameOverride: clearDisplayNameOverride ? null : (displayNameOverride ?? this.displayNameOverride),
      timezone: timezone ?? this.timezone,
      dateFormat: dateFormat ?? this.dateFormat,
      timeFormat: timeFormat ?? this.timeFormat,
      firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
      theme: theme ?? this.theme,
      compactMode: compactMode ?? this.compactMode,
      defaultTaskPriority: defaultTaskPriority ?? this.defaultTaskPriority,
      defaultTaskStatusFilter: defaultTaskStatusFilter ?? this.defaultTaskStatusFilter,
      defaultTaskSort: defaultTaskSort ?? this.defaultTaskSort,
      defaultTaskSortOrder: defaultTaskSortOrder ?? this.defaultTaskSortOrder,
      defaultMaxAttempts: defaultMaxAttempts ?? this.defaultMaxAttempts,
      defaultPageSize: defaultPageSize ?? this.defaultPageSize,
      defaultDashboardTimeRange: defaultDashboardTimeRange ?? this.defaultDashboardTimeRange,
      defaultReportDateRange: defaultReportDateRange ?? this.defaultReportDateRange,
      defaultReportType: defaultReportType ?? this.defaultReportType,
      defaultExportFormat: defaultExportFormat ?? this.defaultExportFormat,
      notifyTaskAssigned: notifyTaskAssigned ?? this.notifyTaskAssigned,
      notifyTaskReassigned: notifyTaskReassigned ?? this.notifyTaskReassigned,
      notifyReminderDue: notifyReminderDue ?? this.notifyReminderDue,
      notifyFollowUpDue: notifyFollowUpDue ?? this.notifyFollowUpDue,
      notifyNextActionDue: notifyNextActionDue ?? this.notifyNextActionDue,
      notifyTaskOverdue: notifyTaskOverdue ?? this.notifyTaskOverdue,
      notifyAttemptLimitReached: notifyAttemptLimitReached ?? this.notifyAttemptLimitReached,
      notifyTaskCompleted: notifyTaskCompleted ?? this.notifyTaskCompleted,
      notifyTaskReopened: notifyTaskReopened ?? this.notifyTaskReopened,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class UserSettingsUpdate {
  final String? displayNameOverride;
  final String? timezone;
  final String? dateFormat;
  final String? timeFormat;
  final String? firstDayOfWeek;

  final String? theme;
  final bool? compactMode;

  final String? defaultTaskPriority;
  final String? defaultTaskStatusFilter;
  final String? defaultTaskSort;
  final String? defaultTaskSortOrder;
  final int? defaultMaxAttempts;
  final int? defaultPageSize;

  final String? defaultDashboardTimeRange;
  final String? defaultReportDateRange;
  final String? defaultReportType;
  final String? defaultExportFormat;

  final bool? notifyTaskAssigned;
  final bool? notifyTaskReassigned;
  final bool? notifyReminderDue;
  final bool? notifyFollowUpDue;
  final bool? notifyNextActionDue;
  final bool? notifyTaskOverdue;
  final bool? notifyAttemptLimitReached;
  final bool? notifyTaskCompleted;
  final bool? notifyTaskReopened;

  const UserSettingsUpdate({
    this.displayNameOverride,
    this.timezone,
    this.dateFormat,
    this.timeFormat,
    this.firstDayOfWeek,
    this.theme,
    this.compactMode,
    this.defaultTaskPriority,
    this.defaultTaskStatusFilter,
    this.defaultTaskSort,
    this.defaultTaskSortOrder,
    this.defaultMaxAttempts,
    this.defaultPageSize,
    this.defaultDashboardTimeRange,
    this.defaultReportDateRange,
    this.defaultReportType,
    this.defaultExportFormat,
    this.notifyTaskAssigned,
    this.notifyTaskReassigned,
    this.notifyReminderDue,
    this.notifyFollowUpDue,
    this.notifyNextActionDue,
    this.notifyTaskOverdue,
    this.notifyAttemptLimitReached,
    this.notifyTaskCompleted,
    this.notifyTaskReopened,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (displayNameOverride != null) map['display_name_override'] = displayNameOverride;
    if (timezone != null) map['timezone'] = timezone;
    if (dateFormat != null) map['date_format'] = dateFormat;
    if (timeFormat != null) map['time_format'] = timeFormat;
    if (firstDayOfWeek != null) map['first_day_of_week'] = firstDayOfWeek;
    if (theme != null) map['theme'] = theme;
    if (compactMode != null) map['compact_mode'] = compactMode;
    if (defaultTaskPriority != null) map['default_task_priority'] = defaultTaskPriority;
    if (defaultTaskStatusFilter != null) map['default_task_status_filter'] = defaultTaskStatusFilter;
    if (defaultTaskSort != null) map['default_task_sort'] = defaultTaskSort;
    if (defaultTaskSortOrder != null) map['default_task_sort_order'] = defaultTaskSortOrder;
    if (defaultMaxAttempts != null) map['default_max_attempts'] = defaultMaxAttempts;
    if (defaultPageSize != null) map['default_page_size'] = defaultPageSize;
    if (defaultDashboardTimeRange != null) map['default_dashboard_time_range'] = defaultDashboardTimeRange;
    if (defaultReportDateRange != null) map['default_report_date_range'] = defaultReportDateRange;
    if (defaultReportType != null) map['default_report_type'] = defaultReportType;
    if (defaultExportFormat != null) map['default_export_format'] = defaultExportFormat;
    if (notifyTaskAssigned != null) map['notify_task_assigned'] = notifyTaskAssigned;
    if (notifyTaskReassigned != null) map['notify_task_reassigned'] = notifyTaskReassigned;
    if (notifyReminderDue != null) map['notify_reminder_due'] = notifyReminderDue;
    if (notifyFollowUpDue != null) map['notify_follow_up_due'] = notifyFollowUpDue;
    if (notifyNextActionDue != null) map['notify_next_action_due'] = notifyNextActionDue;
    if (notifyTaskOverdue != null) map['notify_task_overdue'] = notifyTaskOverdue;
    if (notifyAttemptLimitReached != null) map['notify_attempt_limit_reached'] = notifyAttemptLimitReached;
    if (notifyTaskCompleted != null) map['notify_task_completed'] = notifyTaskCompleted;
    if (notifyTaskReopened != null) map['notify_task_reopened'] = notifyTaskReopened;
    return map;
  }
}
