import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';

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
  group('ApiClient Tests', () {
    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
    });

    test('successful GET request parses JSON response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/health'));
        return http.Response(
          jsonEncode({'status': 'healthy', 'database': 'connected'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final response = await apiClient.get('/health', requiresAuth: false);
      expect(response, isA<Map<String, dynamic>>());
      expect(response['status'], equals('healthy'));
    });

    test('automatically attaches Authorization Bearer header when token exists', () async {
      const jwt = 'test.jwt.token';
      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer $jwt'));
        expect(request.headers['Content-Type'], equals('application/json'));
        return http.Response(
          jsonEncode({'id': 'u1', 'name': 'Test User', 'email': 't@example.com'}),
          200,
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(jwt),
      );

      final response = await apiClient.get('/auth/me', requiresAuth: true);
      expect(response['email'], equals('t@example.com'));
    });

    test('handles 401 Unauthorized and calls onUnauthorized callback', () async {
      bool unauthorizedTriggered = false;

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Token expired or invalid'}),
          401,
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage('expired.token'),
        onUnauthorized: () {
          unauthorizedTriggered = true;
        },
      );

      await expectLater(
        apiClient.get('/tasks'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(unauthorizedTriggered, isTrue);
    });

    test('handles 404 Task Not Found with domain error code', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'TASK_NOT_FOUND', 'message': 'Task not found'}),
          404,
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage('valid.token'),
      );

      try {
        await apiClient.get('/tasks/non-existent-id');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(404));
        expect(e.errorCode, equals('TASK_NOT_FOUND'));
        expect(e.message, equals('Task not found'));
      }
    });

    test('handles 409 Max Attempts Reached conflict error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'MAX_ATTEMPTS_REACHED',
            'message': 'Task reached maximum attempts (2/2). Authorized override required.',
          }),
          409,
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage('valid.token'),
      );

      try {
        await apiClient.post('/tasks/test-task-id/attempt');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(409));
        expect(e.errorCode, equals('MAX_ATTEMPTS_REACHED'));
        expect(e.message, contains('Authorized override required'));
      }
    });

    test('handles 422 Validation Error structure', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': [
              {
                'loc': ['body', 'title'],
                'msg': 'Field required',
                'type': 'missing',
              }
            ]
          }),
          422,
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage('valid.token'),
      );

      try {
        await apiClient.post('/tasks', body: {});
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(422));
        expect(e.errorCode, equals('VALIDATION_ERROR'));
        expect(e.message, contains('title'));
      }
    });
  });
}
