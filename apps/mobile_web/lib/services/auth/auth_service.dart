import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../models/auth/auth_models.dart';

/// Service managing user authentication, registration, session verification, and logout.
class AuthService {
  final ApiClient _apiClient;

  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;
  TokenStorage get tokenStorage => _apiClient.tokenStorage;
  RefreshTokenStorage? get refreshTokenStorage => _apiClient.refreshTokenStorage;

  /// Authenticate with email & password and persist the returned JWT access token.
  Future<TokenResponse> login(String email, String password) async {
    final payload = LoginRequest(
      email: email.trim(),
      password: password,
    );

    final response = await _apiClient.post(
      '/auth/login',
      body: payload.toJson(),
      requiresAuth: false,
    );

    final tokenResponse = TokenResponse.fromJson(response as Map<String, dynamic>);
    await _apiClient.tokenStorage.saveToken(tokenResponse.accessToken);
    if (tokenResponse.refreshToken != null && _apiClient.refreshTokenStorage != null) {
      await _apiClient.refreshTokenStorage!.saveRefreshToken(tokenResponse.refreshToken!);
    }
    return tokenResponse;
  }

  /// Register a new user account.
  Future<User> register(String name, String email, String password) async {
    final payload = UserCreateRequest(
      name: name.trim(),
      email: email.trim(),
      password: password,
    );

    final response = await _apiClient.post(
      '/auth/register',
      body: payload.toJson(),
      requiresAuth: false,
    );

    return User.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve the current authenticated user profile from `/api/v1/auth/me`.
  Future<User> getCurrentUser() async {
    final response = await _apiClient.get('/auth/me', requiresAuth: true);
    return User.fromJson(response as Map<String, dynamic>);
  }

  /// Check whether a local token exists.
  Future<bool> hasStoredToken() async {
    return _apiClient.tokenStorage.hasToken();
  }

  /// Rotate stored refresh token and update stored tokens.
  Future<TokenResponse?> refreshToken() async {
    if (_apiClient.refreshTokenStorage == null) return null;
    final storedRefresh = await _apiClient.refreshTokenStorage!.getRefreshToken();
    if (storedRefresh == null || storedRefresh.isEmpty) {
      return null;
    }

    final response = await _apiClient.post(
      '/auth/refresh',
      body: {'refresh_token': storedRefresh},
      requiresAuth: false,
    );

    final tokenResponse = TokenResponse.fromJson(response as Map<String, dynamic>);
    await _apiClient.tokenStorage.saveToken(tokenResponse.accessToken);
    if (tokenResponse.refreshToken != null) {
      await _apiClient.refreshTokenStorage!.saveRefreshToken(tokenResponse.refreshToken!);
    }
    return tokenResponse;
  }

  /// Logout by revoking refresh token on server and clearing all local tokens.
  Future<void> logout() async {
    final refreshToken = await _apiClient.refreshTokenStorage?.getRefreshToken();
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.post(
          '/auth/logout',
          body: {'refresh_token': refreshToken},
          requiresAuth: false,
        );
      }
    } catch (_) {
      // Best-effort remote revocation on logout
    } finally {
      await _apiClient.tokenStorage.deleteToken();
      await _apiClient.refreshTokenStorage?.clearAllTokens();
    }
  }

  /// Change user password.
  Future<User> changePassword(String currentPassword, String newPassword) async {
    final response = await _apiClient.post(
      '/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
      requiresAuth: true,
    );
    return User.fromJson(response as Map<String, dynamic>);
  }
}
