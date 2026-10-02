// Models representing Reminder entities and requests.

class Reminder {
  final String id;
  final String taskId;
  final DateTime remindAt;
  final String message;
  final bool isSent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Reminder({
    required this.id,
    required this.taskId,
    required this.remindAt,
    required this.message,
    required this.isSent,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now();
    return Reminder(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      remindAt: DateTime.parse(json['remind_at'] as String),
      message: json['message'] as String? ?? '',
      isSent: json['is_sent'] as bool? ?? false,
      createdAt: createdAt,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'remind_at': remindAt.toIso8601String(),
        'message': message,
        'is_sent': isSent,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class ReminderCreateRequest {
  final String taskId;
  final DateTime remindAt;
  final String message;

  const ReminderCreateRequest({
    required this.taskId,
    required this.remindAt,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'remind_at': remindAt.toIso8601String(),
        'message': message,
      };
}
