import '../../core/network/api_client.dart';
import '../../models/auth/auth_models.dart';

/// Service for interacting with User and Team endpoints in the FastAPI backend.
class UserService {
  final ApiClient _apiClient;

  UserService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve the authoritative current authenticated user from /auth/me.
  Future<User> getCurrentUser() async {
    final response = await _apiClient.get(
      '/auth/me',
      requiresAuth: true,
    );
    return User.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve team users with optional search, active filtering, and pagination.
  Future<UserListResponse> getUsers({
    String? search,
    bool? isActive,
    int page = 1,
    int pageSize = 100,
  }) async {
    final queryParams = <String, dynamic>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (isActive != null) 'is_active': isActive,
      'page': page,
      'page_size': pageSize,
    };

    final response = await _apiClient.get(
      '/users',
      queryParameters: queryParams,
      requiresAuth: true,
    );

    return UserListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve a single user by ID.
  Future<User> getUser(String userId) async {
    final response = await _apiClient.get(
      '/users/$userId',
      requiresAuth: true,
    );
    return User.fromJson(response as Map<String, dynamic>);
  }
}
