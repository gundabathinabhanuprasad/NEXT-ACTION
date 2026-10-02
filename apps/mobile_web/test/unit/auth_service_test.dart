import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
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
  group('AuthService Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage();
    });

    test('login success stores access token and returns TokenResponse', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'test_jwt_access_token_123',
              'token_type': 'bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      final tokenResponse = await authService.login('alice@example.com', 'secret123');

      expect(tokenResponse.accessToken, equals('test_jwt_access_token_123'));
      expect(tokenResponse.expiresIn, equals(3600));
      expect(await tokenStorage.getToken(), equals('test_jwt_access_token_123'));
      expect(await authService.hasStoredToken(), isTrue);
    });

    test('login failure throws ApiException and does not store token', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid email or password.',
          }),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      expect(
        () async => await authService.login('alice@example.com', 'wrong_pass'),
        throwsA(isA<ApiException>().having((e) => e.errorCode, 'errorCode', 'INVALID_CREDENTIALS')),
      );

      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('getCurrentUser retrieves user profile using stored JWT', () async {
      tokenStorage.token = 'valid_token';

      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer valid_token'));
        return http.Response(
          jsonEncode({
            'id': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
            'name': 'Alice Smith',
            'email': 'alice@example.com',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      final user = await authService.getCurrentUser();
      expect(user.id, equals('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d'));
      expect(user.name, equals('Alice Smith'));
      expect(user.email, equals('alice@example.com'));
      expect(user.isActive, isTrue);
    });

    test('logout clears stored token', () async {
      tokenStorage.token = 'existing_token';
      expect(await tokenStorage.hasToken(), isTrue);

      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      await authService.logout();
      expect(await tokenStorage.hasToken(), isFalse);
    });
  });
}
