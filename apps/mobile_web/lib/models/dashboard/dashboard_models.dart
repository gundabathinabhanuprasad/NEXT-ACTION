import '../history/task_history_models.dart';
import '../notification/notification_models.dart';

/// Supported Dashboard time ranges for trends and in-range metrics.
enum DashboardTimeRange {
  today('today', 'Today'),
  last7Days('last_7_days', 'Last 7 Days'),
  last30Days('last_30_days', 'Last 30 Days'),
  thisMonth('this_month', 'This Month');

  final String apiValue;
  final String label;

  const DashboardTimeRange(this.apiValue, this.label);

  static DashboardTimeRange fromApiValue(String val) {
    return DashboardTimeRange.values.firstWhere(
      (e) => e.apiValue == val,
      orElse: () => DashboardTimeRange.last7Days,
    );
  }
}

/// Primary KPI counts.
class DashboardKpis {
  final int totalOpenTasks;
  final int dueTodayTasks;
  final int overdueTasks;
  final int upcomingTasks;
  final int completedTasks;
  final int completedInRange;
  final int createdInRange;
  final int nearMaxAttempts;
  final int maxAttemptsReached;
  final int pendingFollowUps;
  final int overdueFollowUps;
  final int dueTodayFollowUps;
  final int dueReminders;
  final int unreadNotifications;

  const DashboardKpis({
    required this.totalOpenTasks,
    required this.dueTodayTasks,
    required this.overdueTasks,
    required this.upcomingTasks,
    required this.completedTasks,
    required this.completedInRange,
    required this.createdInRange,
    required this.nearMaxAttempts,
    required this.maxAttemptsReached,
    required this.pendingFollowUps,
    required this.overdueFollowUps,
    required this.dueTodayFollowUps,
    required this.dueReminders,
    required this.unreadNotifications,
  });

  factory DashboardKpis.fromJson(Map<String, dynamic> json) {
    return DashboardKpis(
      totalOpenTasks: json['total_open_tasks'] as int? ?? 0,
      dueTodayTasks: json['due_today_tasks'] as int? ?? 0,
      overdueTasks: json['overdue_tasks'] as int? ?? 0,
      upcomingTasks: json['upcoming_tasks'] as int? ?? 0,
      completedTasks: json['completed_tasks'] as int? ?? 0,
      completedInRange: json['completed_in_range'] as int? ?? 0,
      createdInRange: json['created_in_range'] as int? ?? 0,
      nearMaxAttempts: json['near_max_attempts'] as int? ?? 0,
      maxAttemptsReached: json['max_attempts_reached'] as int? ?? 0,
      pendingFollowUps: json['pending_follow_ups'] as int? ?? 0,
      overdueFollowUps: json['overdue_follow_ups'] as int? ?? 0,
      dueTodayFollowUps: json['due_today_follow_ups'] as int? ?? 0,
      dueReminders: json['due_reminders'] as int? ?? 0,
      unreadNotifications: json['unread_notifications'] as int? ?? 0,
    );
  }
}

/// Attention summary aggregates.
class DashboardAttentionSummary {
  final int urgentCount;
  final int todayCount;

  const DashboardAttentionSummary({
    required this.urgentCount,
    required this.todayCount,
  });

  factory DashboardAttentionSummary.fromJson(Map<String, dynamic> json) {
    return DashboardAttentionSummary(
      urgentCount: json['urgent_count'] as int? ?? 0,
      todayCount: json['today_count'] as int? ?? 0,
    );
  }
}

/// Task status distribution.
class DashboardStatusDistribution {
  final int pending;
  final int inProgress;
  final int completed;
  final int cancelled;

  const DashboardStatusDistribution({
    required this.pending,
    required this.inProgress,
    required this.completed,
    required this.cancelled,
  });

  factory DashboardStatusDistribution.fromJson(Map<String, dynamic> json) {
    return DashboardStatusDistribution(
      pending: json['pending'] as int? ?? 0,
      inProgress: json['in_progress'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      cancelled: json['cancelled'] as int? ?? 0,
    );
  }

  int get total => pending + inProgress + completed + cancelled;
}

/// Priority tier distribution.
class DashboardPriorityDistribution {
  final int urgent;
  final int high;
  final int medium;
  final int low;

  const DashboardPriorityDistribution({
    required this.urgent,
    required this.high,
    required this.medium,
    required this.low,
  });

  factory DashboardPriorityDistribution.fromJson(Map<String, dynamic> json) {
    return DashboardPriorityDistribution(
      urgent: json['urgent'] as int? ?? 0,
      high: json['high'] as int? ?? 0,
      medium: json['medium'] as int? ?? 0,
      low: json['low'] as int? ?? 0,
    );
  }

  int get total => urgent + high + medium + low;
}

/// Attempt pressure distribution.
class DashboardAttemptPressure {
  final int zeroAttempts;
  final int oneAttempt;
  final int nearMax;
  final int maxReached;

  const DashboardAttemptPressure({
    required this.zeroAttempts,
    required this.oneAttempt,
    required this.nearMax,
    required this.maxReached,
  });

  factory DashboardAttemptPressure.fromJson(Map<String, dynamic> json) {
    return DashboardAttemptPressure(
      zeroAttempts: json['zero_attempts'] as int? ?? 0,
      oneAttempt: json['one_attempt'] as int? ?? 0,
      nearMax: json['near_max'] as int? ?? 0,
      maxReached: json['max_reached'] as int? ?? 0,
    );
  }
}

/// Workload summary item for assignees.
class AssigneeWorkloadItem {
  final String? userId;
  final String userName;
  final int openTasks;
  final int dueToday;
  final int overdue;
  final int completed;

  const AssigneeWorkloadItem({
    this.userId,
    required this.userName,
    required this.openTasks,
    required this.dueToday,
    required this.overdue,
    required this.completed,
  });

  factory AssigneeWorkloadItem.fromJson(Map<String, dynamic> json) {
    return AssigneeWorkloadItem(
      userId: json['user_id'] as String?,
      userName: json['user_name'] as String? ?? 'Unassigned',
      openTasks: json['open_tasks'] as int? ?? 0,
      dueToday: json['due_today'] as int? ?? 0,
      overdue: json['overdue'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
    );
  }
}

/// Workload summary item for clients.
class ClientWorkloadItem {
  final String clientId;
  final String clientName;
  final int openTasks;
  final int dueToday;
  final int overdue;
  final int completed;

  const ClientWorkloadItem({
    required this.clientId,
    required this.clientName,
    required this.openTasks,
    required this.dueToday,
    required this.overdue,
    required this.completed,
  });

  factory ClientWorkloadItem.fromJson(Map<String, dynamic> json) {
    return ClientWorkloadItem(
      clientId: json['client_id'] as String,
      clientName: json['client_name'] as String? ?? 'Unnamed Client',
      openTasks: json['open_tasks'] as int? ?? 0,
      dueToday: json['due_today'] as int? ?? 0,
      overdue: json['overdue'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
    );
  }
}

/// Workload summary item for workflows.
class WorkflowWorkloadItem {
  final String workflowId;
  final String workflowName;
  final int openTasks;
  final int dueToday;
  final int overdue;
  final int completed;

  const WorkflowWorkloadItem({
    required this.workflowId,
    required this.workflowName,
    required this.openTasks,
    required this.dueToday,
    required this.overdue,
    required this.completed,
  });

  factory WorkflowWorkloadItem.fromJson(Map<String, dynamic> json) {
    return WorkflowWorkloadItem(
      workflowId: json['workflow_id'] as String,
      workflowName: json['workflow_name'] as String? ?? 'Unnamed Workflow',
      openTasks: json['open_tasks'] as int? ?? 0,
      dueToday: json['due_today'] as int? ?? 0,
      overdue: json['overdue'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
    );
  }
}

/// Combined workload breakdowns.
class DashboardWorkloadBreakdown {
  final List<AssigneeWorkloadItem> byAssignee;
  final List<ClientWorkloadItem> byClient;
  final List<WorkflowWorkloadItem> byWorkflow;

  const DashboardWorkloadBreakdown({
    required this.byAssignee,
    required this.byClient,
    required this.byWorkflow,
  });

  factory DashboardWorkloadBreakdown.fromJson(Map<String, dynamic> json) {
    final assigneeRaw = json['by_assignee'] as List<dynamic>? ?? [];
    final clientRaw = json['by_client'] as List<dynamic>? ?? [];
    final workflowRaw = json['by_workflow'] as List<dynamic>? ?? [];

    return DashboardWorkloadBreakdown(
      byAssignee: assigneeRaw.map((e) => AssigneeWorkloadItem.fromJson(e as Map<String, dynamic>)).toList(),
      byClient: clientRaw.map((e) => ClientWorkloadItem.fromJson(e as Map<String, dynamic>)).toList(),
      byWorkflow: workflowRaw.map((e) => WorkflowWorkloadItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// Follow-up scheduling analytics.
class FollowUpAnalytics {
  final int pending;
  final int overdue;
  final int dueToday;
  final int upcoming;
  final int completed;

  const FollowUpAnalytics({
    required this.pending,
    required this.overdue,
    required this.dueToday,
    required this.upcoming,
    required this.completed,
  });

  factory FollowUpAnalytics.fromJson(Map<String, dynamic> json) {
    return FollowUpAnalytics(
      pending: json['pending'] as int? ?? 0,
      overdue: json['overdue'] as int? ?? 0,
      dueToday: json['due_today'] as int? ?? 0,
      upcoming: json['upcoming'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
    );
  }
}

/// Reminder scheduling analytics.
class ReminderAnalytics {
  final int pending;
  final int dueToday;
  final int overdue;
  final int upcoming;

  const ReminderAnalytics({
    required this.pending,
    required this.dueToday,
    required this.overdue,
    required this.upcoming,
  });

  factory ReminderAnalytics.fromJson(Map<String, dynamic> json) {
    return ReminderAnalytics(
      pending: json['pending'] as int? ?? 0,
      dueToday: json['due_today'] as int? ?? 0,
      overdue: json['overdue'] as int? ?? 0,
      upcoming: json['upcoming'] as int? ?? 0,
    );
  }
}

/// Scheduling insights wrapper.
class DashboardSchedulingAnalytics {
  final FollowUpAnalytics followUps;
  final ReminderAnalytics reminders;

  const DashboardSchedulingAnalytics({
    required this.followUps,
    required this.reminders,
  });

  factory DashboardSchedulingAnalytics.fromJson(Map<String, dynamic> json) {
    return DashboardSchedulingAnalytics(
      followUps: FollowUpAnalytics.fromJson(json['follow_ups'] as Map<String, dynamic>? ?? {}),
      reminders: ReminderAnalytics.fromJson(json['reminders'] as Map<String, dynamic>? ?? {}),
    );
  }
}

/// Single day trend data point.
class DashboardTrendPoint {
  final String date;
  final int createdCount;
  final int completedCount;
  final int overdueCount;

  const DashboardTrendPoint({
    required this.date,
    required this.createdCount,
    required this.completedCount,
    required this.overdueCount,
  });

  factory DashboardTrendPoint.fromJson(Map<String, dynamic> json) {
    return DashboardTrendPoint(
      date: json['date'] as String,
      createdCount: json['created_count'] as int? ?? 0,
      completedCount: json['completed_count'] as int? ?? 0,
      overdueCount: json['overdue_count'] as int? ?? 0,
    );
  }
}

/// Consolidated PostgreSQL Dashboard Summary and Productivity Insights.
class DashboardSummary {
  final String timeRange;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DashboardKpis kpis;
  final DashboardAttentionSummary attention;
  final DashboardStatusDistribution statusDistribution;
  final DashboardPriorityDistribution priorityDistribution;
  final DashboardAttemptPressure attemptPressure;
  final DashboardWorkloadBreakdown workload;
  final DashboardSchedulingAnalytics scheduling;
  final List<DashboardTrendPoint> trends;
  final List<TaskHistory> recentActivities;
  final List<AppNotification> recentNotifications;

  const DashboardSummary({
    required this.timeRange,
    required this.rangeStart,
    required this.rangeEnd,
    required this.kpis,
    required this.attention,
    required this.statusDistribution,
    required this.priorityDistribution,
    required this.attemptPressure,
    required this.workload,
    required this.scheduling,
    required this.trends,
    required this.recentActivities,
    required this.recentNotifications,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final activitiesRaw = json['recent_activities'] as List<dynamic>? ?? [];
    final notifsRaw = json['recent_notifications'] as List<dynamic>? ?? [];
    final trendsRaw = json['trends'] as List<dynamic>? ?? [];

    return DashboardSummary(
      timeRange: json['time_range'] as String? ?? 'last_7_days',
      rangeStart: DateTime.parse(json['range_start'] as String),
      rangeEnd: DateTime.parse(json['range_end'] as String),
      kpis: DashboardKpis.fromJson(json['kpis'] as Map<String, dynamic>? ?? {}),
      attention: DashboardAttentionSummary.fromJson(json['attention'] as Map<String, dynamic>? ?? {}),
      statusDistribution: DashboardStatusDistribution.fromJson(json['status_distribution'] as Map<String, dynamic>? ?? {}),
      priorityDistribution: DashboardPriorityDistribution.fromJson(json['priority_distribution'] as Map<String, dynamic>? ?? {}),
      attemptPressure: DashboardAttemptPressure.fromJson(json['attempt_pressure'] as Map<String, dynamic>? ?? {}),
      workload: DashboardWorkloadBreakdown.fromJson(json['workload'] as Map<String, dynamic>? ?? {}),
      scheduling: DashboardSchedulingAnalytics.fromJson(json['scheduling'] as Map<String, dynamic>? ?? {}),
      trends: trendsRaw.map((e) => DashboardTrendPoint.fromJson(e as Map<String, dynamic>)).toList(),
      recentActivities: activitiesRaw.map((e) => TaskHistory.fromJson(e as Map<String, dynamic>)).toList(),
      recentNotifications: notifsRaw.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
