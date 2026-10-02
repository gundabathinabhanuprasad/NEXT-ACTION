import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/config/api_config.dart';
import '../../core/errors/api_exception.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../models/auth/auth_models.dart';

/// Service managing user authentication, registration, session verification, and logout.
class AuthService {
  final ApiClient _apiClient;
  final GoogleSignIn? _defaultGoogleSignIn;

  AuthService({ApiClient? apiClient, GoogleSignIn? googleSignIn})
      : _apiClient = apiClient ?? ApiClient(),
        _defaultGoogleSignIn = googleSignIn;

  ApiClient get apiClient => _apiClient;
  TokenStorage get tokenStorage => _apiClient.tokenStorage;
  RefreshTokenStorage? get refreshTokenStorage => _apiClient.refreshTokenStorage;

  GoogleSignIn _createGoogleSignIn() {
    return GoogleSignIn(
      clientId: kIsWeb && ApiConfig.googleWebClientId.isNotEmpty ? ApiConfig.googleWebClientId : null,
      serverClientId: ApiConfig.googleServerClientId.isNotEmpty ? ApiConfig.googleServerClientId : null,
      scopes: const ['email', 'profile'],
    );
  }

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

  /// Authenticate using Google credential (ID Token) and persist returned NextAction JWT.
  /// Returns null if user cancelled the sign-in flow.
  Future<TokenResponse?> signInWithGoogle({GoogleSignIn? customGoogleSignIn}) async {
    final googleSignIn = customGoogleSignIn ?? _defaultGoogleSignIn ?? _createGoogleSignIn();

    final GoogleSignInAccount? account = await googleSignIn.signIn();
    if (account == null) {
      // User explicitly cancelled the sign-in flow
      return null;
    }

    final GoogleSignInAuthentication auth = await account.authentication;
    final String? idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const ApiException(
        statusCode: 400,
        errorCode: 'INVALID_CREDENTIALS',
        message: 'Google Sign-In failed to retrieve ID token. Verify OAuth client ID configuration.',
      );
    }

    final payload = GoogleLoginRequest(idToken: idToken);
    final response = await _apiClient.post(
      '/auth/google',
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
  Future<void> logout({GoogleSignIn? customGoogleSignIn}) async {
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
      try {
        final googleSignIn = customGoogleSignIn ?? _defaultGoogleSignIn ?? _createGoogleSignIn();
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
        }
      } catch (_) {
        // Best-effort Google sign-out
      }
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
