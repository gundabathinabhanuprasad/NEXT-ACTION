// Models representing Task entities and operation requests/responses.

class Task {
  final String id;
  final String title;
  final String? description;
  final String? subjectLine;
  final String? clientId;
  final String? workflowId;
  final String? assignedUserId;
  final String? templateId;
  final String? recurringTaskId;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final DateTime? nextActionDate;
  final int attemptCount;
  final int maxAttempts;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Task({
    required this.id,
    required this.title,
    this.description,
    this.subjectLine,
    this.clientId,
    this.workflowId,
    this.assignedUserId,
    this.templateId,
    this.recurringTaskId,
    this.status = 'pending',
    this.priority = 'medium',
    this.dueDate,
    this.nextActionDate,
    required this.attemptCount,
    this.maxAttempts = 2,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get hasReachedMaxAttempts => attemptCount >= maxAttempts;
  bool get isApproachingMaxAttempts => attemptCount == maxAttempts - 1 && maxAttempts > 1 && !isCompleted;
  bool get isNearMaxAttempts => (attemptCount >= maxAttempts - 1) && !isCompleted && !isCancelled;
  bool get canAttemptNormally => attemptCount < maxAttempts && !isCompleted && !isCancelled;
  bool get isFromTemplate => templateId != null;
  bool get isFromRecurrence => recurringTaskId != null;

  bool get isOverdue {
    if (dueDate == null || isCompleted || isCancelled) return false;
    if (isDueToday) return false;
    return dueDate!.isBefore(DateTime.now());
  }

  bool get isDueToday {
    if (dueDate == null || isCompleted || isCancelled) return false;
    final now = DateTime.now();
    final localDue = dueDate!.toLocal();
    return localDue.year == now.year && localDue.month == now.month && localDue.day == now.day;
  }

  int get priorityWeight {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return 4;
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
      default:
        return 1;
    }
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      subjectLine: json['subject_line'] as String?,
      clientId: json['client_id'] as String?,
      workflowId: json['workflow_id'] as String?,
      assignedUserId: json['assigned_user_id'] as String?,
      templateId: json['template_id'] as String?,
      recurringTaskId: json['recurring_task_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      priority: json['priority'] as String? ?? 'medium',
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      nextActionDate: json['next_action_date'] != null
          ? DateTime.parse(json['next_action_date'] as String)
          : null,
      attemptCount: json['attempt_count'] as int? ?? 0,
      maxAttempts: json['max_attempts'] as int? ?? 2,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'subject_line': subjectLine,
        'client_id': clientId,
        'workflow_id': workflowId,
        'assigned_user_id': assignedUserId,
        if (templateId != null) 'template_id': templateId,
        if (recurringTaskId != null) 'recurring_task_id': recurringTaskId,
        'status': status,
        'priority': priority,
        'due_date': dueDate?.toIso8601String(),
        'next_action_date': nextActionDate?.toIso8601String(),
        'attempt_count': attemptCount,
        'max_attempts': maxAttempts,
        'completed_at': completedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class TaskListResponse {
  final List<Task> items;
  final int total;
  final int page;
  final int pageSize;

  const TaskListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory TaskListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return TaskListResponse(
      items: rawItems.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }
}

class TaskCreateRequest {
  final String title;
  final String? description;
  final String? subjectLine;
  final String? clientId;
  final String? workflowId;
  final String? assignedUserId;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final DateTime? nextActionDate;
  final int maxAttempts;

  final String? templateId;
  final String? recurringTaskId;

  const TaskCreateRequest({
    required this.title,
    this.description,
    this.subjectLine,
    this.clientId,
    this.workflowId,
    this.assignedUserId,
    this.templateId,
    this.recurringTaskId,
    this.status = 'pending',
    this.priority = 'medium',
    this.dueDate,
    this.nextActionDate,
    this.maxAttempts = 2,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
        if (subjectLine != null) 'subject_line': subjectLine,
        if (clientId != null) 'client_id': clientId,
        if (workflowId != null) 'workflow_id': workflowId,
        if (assignedUserId != null) 'assigned_user_id': assignedUserId,
        if (templateId != null) 'template_id': templateId,
        if (recurringTaskId != null) 'recurring_task_id': recurringTaskId,
        'status': status,
        'priority': priority,
        if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
        if (nextActionDate != null) 'next_action_date': nextActionDate!.toIso8601String(),
        'max_attempts': maxAttempts,
      };
}

class TaskUpdateRequest {
  final String? title;
  final String? description;
  final String? subjectLine;

  const TaskUpdateRequest({
    this.title,
    this.description,
    this.subjectLine,
  });

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (subjectLine != null) 'subject_line': subjectLine,
      };
}

class AttemptRequest {
  final String? notes;

  const AttemptRequest({this.notes});

  Map<String, dynamic> toJson() => {
        if (notes != null) 'notes': notes,
      };
}

class OverrideAttemptRequest {
  final bool authorizedOverride;
  final String reason;

  const OverrideAttemptRequest({
    this.authorizedOverride = true,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'authorized_override': authorizedOverride,
        'reason': reason,
      };
}

class PostponeTaskRequest {
  final DateTime newDueDate;
  final String reason;

  const PostponeTaskRequest({
    required this.newDueDate,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'new_due_date': newDueDate.toIso8601String(),
        'reason': reason,
      };
}

class NextActionDateRequest {
  final DateTime? nextActionDate;

  const NextActionDateRequest({this.nextActionDate});

  Map<String, dynamic> toJson() => {
        'next_action_date': nextActionDate?.toIso8601String(),
      };
}

class ReopenTaskRequest {
  final String reason;

  const ReopenTaskRequest({required this.reason});

  Map<String, dynamic> toJson() => {
        'reason': reason,
      };
}

class StatusChangeRequest {
  final String status;
  final String? reason;

  const StatusChangeRequest({
    required this.status,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        if (reason != null) 'reason': reason,
      };
}

class PriorityChangeRequest {
  final String priority;
  final String? reason;

  const PriorityChangeRequest({
    required this.priority,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
        'priority': priority,
        if (reason != null) 'reason': reason,
      };
}

class AssignmentChangeRequest {
  final String? assignedUserId;

  const AssignmentChangeRequest({this.assignedUserId});

  Map<String, dynamic> toJson() => {
        'assigned_user_id': assignedUserId,
      };
}

class SubjectLineChangeRequest {
  final String? subjectLine;

  const SubjectLineChangeRequest({this.subjectLine});

  Map<String, dynamic> toJson() => {
        'subject_line': subjectLine,
      };
}
