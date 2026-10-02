import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/services/auth/auth_service.dart';

class FakeRefreshTokenStorage implements TokenStorage, RefreshTokenStorage {
  String? token;
  String? refreshToken;

  FakeRefreshTokenStorage({this.token, this.refreshToken});

  @override
  Future<void> saveToken(String token) async => this.token = token;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<bool> hasToken() async => token != null && token!.isNotEmpty;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> deleteRefreshToken() async => refreshToken = null;

  @override
  Future<void> clearAllTokens() async {
    token = null;
    refreshToken = null;
  }
}

void main() {
  group('Phase 22 — Refresh Token Security & Rotation Tests', () {
    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
    });

    test('1. TokenResponse parses and serializes refresh_token correctly', () {
      final json = {
        'access_token': 'jwt.access.123',
        'token_type': 'bearer',
        'expires_in': 900,
        'refresh_token': 'opaque.refresh.456',
      };
      final parsed = TokenResponse.fromJson(json);
      expect(parsed.accessToken, equals('jwt.access.123'));
      expect(parsed.refreshToken, equals('opaque.refresh.456'));
      expect(parsed.expiresIn, equals(900));

      final serialized = parsed.toJson();
      expect(serialized['refresh_token'], equals('opaque.refresh.456'));
    });

    test('2. AuthService.login saves both access_token and refresh_token', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/auth/login'));
        return http.Response(
          jsonEncode({
            'access_token': 'new.access.token',
            'token_type': 'bearer',
            'expires_in': 900,
            'refresh_token': 'new.refresh.token',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final storage = FakeRefreshTokenStorage();
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: storage);
      final authService = AuthService(apiClient: apiClient);

      final tokenResponse = await authService.login('test@example.com', 'SecurePass123!');
      expect(tokenResponse.accessToken, equals('new.access.token'));
      expect(tokenResponse.refreshToken, equals('new.refresh.token'));

      expect(await storage.getToken(), equals('new.access.token'));
      expect(await storage.getRefreshToken(), equals('new.refresh.token'));
    });

    test('3. AuthService.refreshToken rotates refresh token and updates storage', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/auth/refresh'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refresh_token'], equals('old.refresh.token'));

        return http.Response(
          jsonEncode({
            'access_token': 'rotated.access.token',
            'token_type': 'bearer',
            'expires_in': 900,
            'refresh_token': 'rotated.refresh.token',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final storage = FakeRefreshTokenStorage(
        token: 'old.access.token',
        refreshToken: 'old.refresh.token',
      );
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: storage);
      final authService = AuthService(apiClient: apiClient);

      final result = await authService.refreshToken();
      expect(result, isNotNull);
      expect(result!.accessToken, equals('rotated.access.token'));
      expect(result.refreshToken, equals('rotated.refresh.token'));

      expect(await storage.getToken(), equals('rotated.access.token'));
      expect(await storage.getRefreshToken(), equals('rotated.refresh.token'));
    });

    test('4. AuthService.logout calls server revocation and clears all local tokens', () async {
      bool serverLogoutCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/auth/logout'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refresh_token'], equals('active.refresh.token'));
        serverLogoutCalled = true;

        return http.Response(
          jsonEncode({'message': 'Logged out successfully.'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final storage = FakeRefreshTokenStorage(
        token: 'active.access.token',
        refreshToken: 'active.refresh.token',
      );
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: storage);
      final authService = AuthService(apiClient: apiClient);

      await authService.logout();
      expect(serverLogoutCalled, isTrue);
      expect(await storage.getToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('5. ApiClient automatically rotates token on 401 and retries original request', () async {
      int tasksRequestCount = 0;
      int refreshRequestCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          refreshRequestCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refresh_token'], equals('initial.refresh.token'));

          return http.Response(
            jsonEncode({
              'access_token': 'new.rotated.jwt',
              'token_type': 'bearer',
              'expires_in': 900,
              'refresh_token': 'new.rotated.refresh',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/tasks') {
          tasksRequestCount++;
          if (tasksRequestCount == 1) {
            // First call with expired token returns 401
            expect(request.headers['Authorization'], equals('Bearer expired.access.token'));
            return http.Response(
              jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Token expired'}),
              401,
            );
          } else {
            // Retry call has rotated access token!
            expect(request.headers['Authorization'], equals('Bearer new.rotated.jwt'));
            return http.Response(
              jsonEncode({'items': [{'id': 'task-1', 'title': 'Test Task'}], 'total': 1}),
              200,
            );
          }
        }

        return http.Response('Not Found', 404);
      });

      final storage = FakeRefreshTokenStorage(
        token: 'expired.access.token',
        refreshToken: 'initial.refresh.token',
      );
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: storage);

      final result = await apiClient.get('/tasks');
      expect(result, isNotNull);
      expect(tasksRequestCount, equals(2)); // Original request + Retry
      expect(refreshRequestCount, equals(1)); // One refresh call
      expect(await storage.getToken(), equals('new.rotated.jwt'));
      expect(await storage.getRefreshToken(), equals('new.rotated.refresh'));
    });

    test('6. ApiClient clears tokens and triggers onUnauthorized when refresh fails', () async {
      bool unauthorizedFired = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          return http.Response(
            jsonEncode({'error': 'REFRESH_TOKEN_EXPIRED', 'message': 'Refresh token has expired.'}),
            401,
          );
        }
        if (request.url.path == '/api/v1/tasks') {
          return http.Response(
            jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Token expired'}),
            401,
          );
        }
        return http.Response('Not Found', 404);
      });

      final storage = FakeRefreshTokenStorage(
        token: 'expired.access.token',
        refreshToken: 'expired.refresh.token',
      );
      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: storage,
        onUnauthorized: () {
          unauthorizedFired = true;
        },
      );

      await expectLater(
        apiClient.get('/tasks'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(unauthorizedFired, isTrue);
      expect(await storage.getToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('7. ApiClient does not attempt refresh on auth endpoints', () async {
      int refreshCalls = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          refreshCalls++;
          return http.Response('ok', 200);
        }
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({'error': 'INVALID_CREDENTIALS', 'message': 'Invalid email or password.'}),
            401,
          );
        }
        return http.Response('Not Found', 404);
      });

      final storage = FakeRefreshTokenStorage(
        token: 'some.token',
        refreshToken: 'some.refresh',
      );
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: storage);

      await expectLater(
        apiClient.post('/auth/login', body: {'email': 'a', 'password': 'b'}, requiresAuth: false),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(refreshCalls, equals(0)); // Never attempted refresh for login
    });
  });
}
