import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';

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
  group('AuthProvider Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage();
    });

    test('initial checkAuthStatus with no token transitions to unauthenticated', () async {
      final mockClient = MockClient((_) async => http.Response('Not reached', 500));
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      expect(provider.status, equals(AuthStatus.checking));

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(provider.isAuthenticated, isFalse);
    });

    test('checkAuthStatus with valid token transitions to authenticated', () async {
      tokenStorage.token = 'valid_token_xyz';

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 'b1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
              'name': 'Bob Tester',
              'email': 'bob@example.com',
              'is_active': true,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.authenticated));
      expect(provider.currentUser, isNotNull);
      expect(provider.currentUser?.email, equals('bob@example.com'));
      expect(provider.isAuthenticated, isTrue);
    });

    test('checkAuthStatus with expired/invalid 401 token deletes token and becomes unauthenticated', () async {
      tokenStorage.token = 'expired_token';

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Token expired or signature invalid'}),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('login establishes authenticated state with user profile', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'new_valid_token',
              'token_type': 'bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 'u100',
              'name': 'Charlie',
              'email': 'charlie@example.com',
              'is_active': true,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.login('charlie@example.com', 'mypassword');

      expect(success, isTrue);
      expect(provider.status, equals(AuthStatus.authenticated));
      expect(provider.currentUser?.name, equals('Charlie'));
    });

    test('logout transitions state to unauthenticated', () async {
      tokenStorage.token = 'sample_token';
      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.logout();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(await tokenStorage.hasToken(), isFalse);
    });
  });
}
