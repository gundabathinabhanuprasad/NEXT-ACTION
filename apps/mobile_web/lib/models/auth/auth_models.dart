// Models representing authentication requests and responses.

class User {
  final String id;
  final String name;
  final String email;
  final bool isActive;
  final String? googleId;
  final String authProvider;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    this.googleId,
    this.authProvider = 'local',
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      isActive: json['is_active'] as bool? ?? true,
      googleId: json['google_id'] as String?,
      authProvider: json['auth_provider'] as String? ?? 'local',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'is_active': isActive,
        if (googleId != null) 'google_id': googleId,
        'auth_provider': authProvider,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class GoogleLoginRequest {
  final String idToken;

  const GoogleLoginRequest({required this.idToken});

  Map<String, dynamic> toJson() => {
        'id_token': idToken,
      };
}

class UserListResponse {
  final List<User> items;
  final int total;
  final int page;
  final int pageSize;

  const UserListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory UserListResponse.fromJson(Map<String, dynamic> json) {
    return UserListResponse(
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'total': total,
        'page': page,
        'page_size': pageSize,
      };
}

class TokenResponse {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String? refreshToken;

  const TokenResponse({
    required this.accessToken,
    this.tokenType = 'bearer',
    required this.expiresIn,
    this.refreshToken,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'token_type': tokenType,
        'expires_in': expiresIn,
        if (refreshToken != null) 'refresh_token': refreshToken,
      };
}

class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

class UserCreateRequest {
  final String name;
  final String email;
  final String password;

  const UserCreateRequest({
    required this.name,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'password': password,
      };
}

class ChangePasswordRequest {
  final String currentPassword;
  final String newPassword;

  const ChangePasswordRequest({
    required this.currentPassword,
    required this.newPassword,
  });

  Map<String, dynamic> toJson() => {
        'current_password': currentPassword,
        'new_password': newPassword,
      };
}
