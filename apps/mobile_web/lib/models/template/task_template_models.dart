/// Model representing a reusable TaskTemplate blueprint in NextAction.
class TaskTemplate {
  final String id;
  final String name;
  final String? description;
  final String? subjectLine;
  final String? workflowId;
  final String? clientId;
  final String? assignedUserId;
  final String priority;
  final int maxAttempts;
  final int? defaultDueOffsetDays;
  final int? defaultNextActionOffsetDays;
  final bool isActive;
  final String createdByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaskTemplate({
    required this.id,
    required this.name,
    this.description,
    this.subjectLine,
    this.workflowId,
    this.clientId,
    this.assignedUserId,
    this.priority = 'medium',
    this.maxAttempts = 2,
    this.defaultDueOffsetDays,
    this.defaultNextActionOffsetDays,
    this.isActive = true,
    required this.createdByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskTemplate.fromJson(Map<String, dynamic> json) {
    return TaskTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      subjectLine: json['subject_line'] as String?,
      workflowId: json['workflow_id'] as String?,
      clientId: json['client_id'] as String?,
      assignedUserId: json['assigned_user_id'] as String?,
      priority: (json['priority'] as String?)?.toLowerCase() ?? 'medium',
      maxAttempts: json['max_attempts'] as int? ?? 2,
      defaultDueOffsetDays: json['default_due_offset_days'] as int?,
      defaultNextActionOffsetDays: json['default_next_action_offset_days'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      createdByUserId: json['created_by_user_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (subjectLine != null) 'subject_line': subjectLine,
      if (workflowId != null) 'workflow_id': workflowId,
      if (clientId != null) 'client_id': clientId,
      if (assignedUserId != null) 'assigned_user_id': assignedUserId,
      'priority': priority,
      'max_attempts': maxAttempts,
      if (defaultDueOffsetDays != null) 'default_due_offset_days': defaultDueOffsetDays,
      if (defaultNextActionOffsetDays != null) 'default_next_action_offset_days': defaultNextActionOffsetDays,
      'is_active': isActive,
      'created_by_user_id': createdByUserId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Paginated list response for Task Templates.
class TaskTemplateListResponse {
  final List<TaskTemplate> items;
  final int total;
  final int page;
  final int pageSize;

  const TaskTemplateListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory TaskTemplateListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return TaskTemplateListResponse(
      items: rawItems
          .map((e) => TaskTemplate.fromJson(e as Map<String, dynamic>))
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
