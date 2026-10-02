// Models representing Client entities and operation requests/responses.

class Client {
  final String id;
  final String name;
  final String? company;
  final String? email;
  final String? phone;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Client({
    required this.id,
    required this.name,
    this.company,
    this.email,
    this.phone,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName {
    if (company != null && company!.trim().isNotEmpty) {
      return '$name ($company)';
    }
    return name;
  }

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id'] as String,
      name: json['name'] as String,
      company: json['company'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (company != null) 'company': company,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (notes != null) 'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class ClientCreateRequest {
  final String name;
  final String? company;
  final String? email;
  final String? phone;
  final String? notes;

  const ClientCreateRequest({
    required this.name,
    this.company,
    this.email,
    this.phone,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (company != null && company!.isNotEmpty) 'company': company,
        if (email != null && email!.isNotEmpty) 'email': email,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class ClientUpdateRequest {
  final String? name;
  final String? company;
  final String? email;
  final String? phone;
  final String? notes;

  const ClientUpdateRequest({
    this.name,
    this.company,
    this.email,
    this.phone,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (company != null) map['company'] = company;
    if (email != null) map['email'] = email;
    if (phone != null) map['phone'] = phone;
    if (notes != null) map['notes'] = notes;
    return map;
  }
}

class ClientListResponse {
  final List<Client> items;
  final int total;
  final int page;
  final int pageSize;

  const ClientListResponse({
    required this.items,
    required this.total,
    this.page = 1,
    this.pageSize = 100,
  });

  factory ClientListResponse.fromJson(Map<String, dynamic> json) {
    return ClientListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => Client.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 100,
    );
  }
}
