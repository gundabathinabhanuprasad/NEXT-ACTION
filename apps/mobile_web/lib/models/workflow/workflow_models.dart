// Models representing Workflow process entities and operation requests/responses.

class Workflow {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Workflow({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class WorkflowCreateRequest {
  final String name;
  final String? description;
  final bool isActive;

  const WorkflowCreateRequest({
    required this.name,
    this.description,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'is_active': isActive,
      };
}

class WorkflowUpdateRequest {
  final String? name;
  final String? description;
  final bool? isActive;

  const WorkflowUpdateRequest({
    this.name,
    this.description,
    this.isActive,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (isActive != null) map['is_active'] = isActive;
    return map;
  }
}

class WorkflowListResponse {
  final List<Workflow> items;
  final int total;
  final int page;
  final int pageSize;

  const WorkflowListResponse({
    required this.items,
    required this.total,
    this.page = 1,
    this.pageSize = 100,
  });

  factory WorkflowListResponse.fromJson(Map<String, dynamic> json) {
    return WorkflowListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => Workflow.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 100,
    );
  }
}
