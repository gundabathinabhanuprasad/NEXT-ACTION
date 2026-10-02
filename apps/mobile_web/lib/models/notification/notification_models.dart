// Notification models representing in-app notifications and attention alerts.

class AppNotification {
  final String id;
  final String userId;
  final String? taskId;
  final String type;
  final String title;
  final String message;
  final String? dedupKey;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.taskId,
    required this.type,
    required this.title,
    required this.message,
    this.dedupKey,
    required this.isRead,
    this.readAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTaskAssigned => type == 'task_assigned' || type == 'task_reassigned';
  bool get isReminderDue => type == 'reminder_due';
  bool get isFollowUpDue => type == 'follow_up_due';
  bool get isNextActionDue => type == 'next_action_due';
  bool get isOverdue => type == 'task_overdue';
  bool get isAttemptLimit => type == 'attempt_limit_reached' || type == 'near_max_attempts';
  bool get isCompleted => type == 'task_completed';
  bool get isReopened => type == 'task_reopened';

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now();
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      taskId: json['task_id'] as String?,
      type: json['type'] as String? ?? 'general',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      dedupKey: json['dedup_key'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      createdAt: createdAt,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'task_id': taskId,
        'type': type,
        'title': title,
        'message': message,
        'dedup_key': dedupKey,
        'is_read': isRead,
        'read_at': readAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class NotificationListResponse {
  final List<AppNotification> items;
  final int total;
  final int unreadCount;
  final int page;
  final int pageSize;

  const NotificationListResponse({
    required this.items,
    required this.total,
    required this.unreadCount,
    required this.page,
    required this.pageSize,
  });

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>?)
            ?.map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return NotificationListResponse(
      items: itemsList,
      total: json['total'] as int? ?? itemsList.length,
      unreadCount: json['unread_count'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }
}

class UnreadCountResponse {
  final int unreadCount;

  const UnreadCountResponse({required this.unreadCount});

  factory UnreadCountResponse.fromJson(Map<String, dynamic> json) {
    return UnreadCountResponse(
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }
}

class NotificationEvaluateResponse {
  final int createdCount;
  final DateTime evaluatedAt;

  const NotificationEvaluateResponse({
    required this.createdCount,
    required this.evaluatedAt,
  });

  factory NotificationEvaluateResponse.fromJson(Map<String, dynamic> json) {
    return NotificationEvaluateResponse(
      createdCount: json['created_count'] as int? ?? 0,
      evaluatedAt: json['evaluated_at'] != null
          ? DateTime.parse(json['evaluated_at'] as String)
          : DateTime.now(),
    );
  }
}
