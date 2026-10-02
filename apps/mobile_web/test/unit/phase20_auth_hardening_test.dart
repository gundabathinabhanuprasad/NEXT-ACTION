import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/providers/settings_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/settings/settings_service.dart';

class InMemoryTokenStorage implements TokenStorage {
  String? token;
  InMemoryTokenStorage([this.token]);

  @override
  Future<void> saveToken(String token) async => this.token = token;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> deleteToken() async => token = null;
  @override
  Future<bool> hasToken() async => token != null && token!.isNotEmpty;
}

void main() {
  group('Phase 20 — Authentication Hardening & Session Security Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage();
    });

    test('1. TokenStorage securely saves, retrieves, and deletes JWT token', () async {
      expect(await tokenStorage.hasToken(), isFalse);
      expect(await tokenStorage.getToken(), isNull);

      await tokenStorage.saveToken('jwt_access_token_sample');
      expect(await tokenStorage.hasToken(), isTrue);
      expect(await tokenStorage.getToken(), equals('jwt_access_token_sample'));

      await tokenStorage.deleteToken();
      expect(await tokenStorage.hasToken(), isFalse);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('2. Successful login persists token and populates authenticated user', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'new_jwt_token_123',
              'token_type': 'bearer',
              'expires_in': 3600,
            }),
            200,
          );
        } else if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': '11111111-1111-1111-1111-111111111111',
              'name': 'Alice Hardened',
              'email': 'alice@example.com',
              'is_active': true,
              'created_at': '2026-09-29T10:00:00Z',
              'updated_at': '2026-09-29T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final authProvider = AuthProvider(authService: authService);

      final success = await authProvider.login('alice@example.com', 'SecurePassword123!');
      expect(success, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUser?.email, equals('alice@example.com'));
      expect(await tokenStorage.getToken(), equals('new_jwt_token_123'));
    });

    test('3. Logout completely invalidates local session and clears token', () async {
      tokenStorage.token = 'existing_token';
      final mockClient = MockClient((_) async => http.Response('', 200));
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final authProvider = AuthProvider(authService: authService);

      await authProvider.logout();
      expect(authProvider.status, equals(AuthStatus.unauthenticated));
      expect(authProvider.currentUser, isNull);
      expect(authProvider.isAuthenticated, isFalse);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('4. Centralized handleSessionExpired clears state and sets expiry notice', () async {
      tokenStorage.token = 'stale_expired_token';
      final mockClient = MockClient((_) async => http.Response('', 200));
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final authProvider = AuthProvider(authService: authService);

      // Trigger session expiration
      await authProvider.handleSessionExpired('Your session has expired. Please sign in again.');

      expect(authProvider.status, equals(AuthStatus.unauthenticated));
      expect(authProvider.currentUser, isNull);
      expect(authProvider.errorMessage, equals('Your session has expired. Please sign in again.'));
      expect(await tokenStorage.getToken(), isNull);
    });

    test('5. ApiClient 401 response automatically invokes onUnauthorized callback', () async {
      tokenStorage.token = 'invalid_server_rejected_token';
      bool onUnauthorizedCalled = false;

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Token expired'}),
          401,
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        onUnauthorized: () {
          onUnauthorizedCalled = true;
        },
      );

      try {
        await apiClient.get('/tasks');
      } catch (_) {}

      expect(onUnauthorizedCalled, isTrue);
    });

    test('6. SettingsProvider clear() resets cached settings to prevent cross-account leakage', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/settings') {
          return http.Response(
            jsonEncode({
              'id': 'set-123',
              'user_id': 'user-123',
              'timezone': 'America/New_York',
              'theme': 'dark',
              'created_at': '2026-09-29T10:00:00Z',
              'updated_at': '2026-09-29T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final settingsService = SettingsService(apiClient: apiClient);
      final settingsProvider = SettingsProvider(settingsService: settingsService);

      await settingsProvider.loadSettings();
      expect(settingsProvider.settings?.timezone, equals('America/New_York'));

      // Logout occurs -> clear() is invoked
      settingsProvider.clear();
      expect(settingsProvider.settings, isNull);
      expect(settingsProvider.errorMessage, isNull);
    });

    test('7. Password change method delegates to backend and updates profile', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/change-password') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['current_password'] == 'CorrectPassword123!') {
            return http.Response(
              jsonEncode({
                'id': 'user-abc',
                'name': 'Alice User',
                'email': 'alice@example.com',
                'is_active': true,
                'created_at': '2026-09-29T10:00:00Z',
                'updated_at': '2026-09-29T11:00:00Z',
              }),
              200,
            );
          } else {
            return http.Response(
              jsonEncode({'error': 'INVALID_CREDENTIALS', 'message': 'Invalid password'}),
              401,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final authProvider = AuthProvider(authService: authService);

      // Wrong current password fails
      final fail = await authProvider.changePassword('WrongPassword!', 'NewSecretPassword123!');
      expect(fail, isFalse);
      expect(authProvider.errorMessage, isNotNull);

      // Correct current password succeeds
      final success = await authProvider.changePassword('CorrectPassword123!', 'NewSecretPassword123!');
      expect(success, isTrue);
      expect(authProvider.currentUser?.email, equals('alice@example.com'));
    });

    test('8. Startup session verification with expired token cleanly resets to unauthenticated', () async {
      tokenStorage.token = 'expired_startup_token';
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Expired token'}),
            401,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final authProvider = AuthProvider(authService: authService);

      await authProvider.checkAuthStatus();
      expect(authProvider.status, equals(AuthStatus.unauthenticated));
      expect(authProvider.currentUser, isNull);
      expect(await tokenStorage.getToken(), isNull);
    });
  });
}
