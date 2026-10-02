// Models representing FollowUp entities and requests.

class FollowUp {
  final String id;
  final String taskId;
  final DateTime scheduledAt;
  final DateTime? completedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FollowUp({
    required this.id,
    required this.taskId,
    required this.scheduledAt,
    this.completedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCompleted => completedAt != null;

  factory FollowUp.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now();
    return FollowUp(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: createdAt,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'scheduled_at': scheduledAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class FollowUpCreateRequest {
  final String taskId;
  final DateTime scheduledAt;
  final String? notes;

  const FollowUpCreateRequest({
    required this.taskId,
    required this.scheduledAt,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'scheduled_at': scheduledAt.toIso8601String(),
        if (notes != null) 'notes': notes,
      };
}

class FollowUpCompleteRequest {
  final DateTime? completedAt;
  final String? notes;

  const FollowUpCompleteRequest({
    this.completedAt,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
        if (notes != null) 'notes': notes,
      };
}
