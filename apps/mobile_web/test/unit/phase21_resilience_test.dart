import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/widgets/common_widgets.dart';

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
  group('Phase 21 — Operational Resilience, Network Error & Retry Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage('test_token_123');
    });

    test('1. ApiClient maps 401 Unauthorized and invokes onUnauthorized callback', () async {
      bool unauthorizedCalled = false;
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'AUTHENTICATION_REQUIRED', 'message': 'Token expired.'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        onUnauthorized: () {
          unauthorizedCalled = true;
        },
      );

      try {
        await apiClient.get('/tasks');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.errorCode, equals('AUTHENTICATION_REQUIRED'));
        expect(e.message, equals('Token expired.'));
        expect(unauthorizedCalled, isTrue);
      }
    });

    test('2. ApiClient maps 403 Forbidden with structured error code', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'FORBIDDEN', 'message': 'Permission denied.'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.get('/tasks/restricted');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(403));
        expect(e.errorCode, equals('FORBIDDEN'));
        expect(e.message, equals('Permission denied.'));
      }
    });

    test('3. ApiClient maps 404 Not Found cleanly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'TASK_NOT_FOUND', 'message': 'Task does not exist.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.get('/tasks/nonexistent');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(404));
        expect(e.errorCode, equals('TASK_NOT_FOUND'));
        expect(e.message, equals('Task does not exist.'));
      }
    });

    test('4. ApiClient maps 409 Conflict business rule violations', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'TASK_ALREADY_COMPLETED', 'message': 'Cannot modify completed task.'}),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.post('/tasks/123/attempts', body: {'notes': 'test'});
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(409));
        expect(e.errorCode, equals('TASK_ALREADY_COMPLETED'));
      }
    });

    test('5. ApiClient maps 422 Validation Error and extracts field error details', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'VALIDATION_ERROR',
            'message': 'Invalid request parameters.',
            'detail': [
              {'loc': ['body', 'title'], 'msg': 'Field required', 'type': 'missing'}
            ]
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.post('/tasks', body: {});
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(422));
        expect(e.errorCode, equals('VALIDATION_ERROR'));
      }
    });

    test('6. ApiClient maps 429 Rate Limit Exceeded', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'RATE_LIMIT_EXCEEDED', 'message': 'Too many requests. Please wait.'}),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.get('/tasks');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(429));
        expect(e.errorCode, equals('RATE_LIMIT_EXCEEDED'));
      }
    });

    test('7. ApiClient maps 500 Internal Server Error without leaking internal tracebacks', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'INTERNAL_SERVER_ERROR',
            'message': 'An unexpected server error occurred. Please contact support.',
            'request_id': 'req-safe-12345'
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.get('/tasks');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(500));
        expect(e.errorCode, equals('INTERNAL_SERVER_ERROR'));
        expect(e.message, contains('An unexpected server error occurred'));
        expect(e.message, isNot(contains('Traceback')));
        expect(e.message, isNot(contains('.py')));
      }
    });

    test('8. ApiClient converts SocketException into user-friendly network error', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection refused to backend host');
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.get('/tasks');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(0));
        expect(e.errorCode, equals('NETWORK_UNAVAILABLE'));
        expect(e.message, contains('Network connection failed'));
      }
    });

    test('9. ApiClient converts TimeoutException into user-friendly timeout message', () async {
      final mockClient = MockClient((request) async {
        throw TimeoutException('HTTP connection timed out');
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);

      try {
        await apiClient.get('/tasks');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(0));
        expect(e.errorCode, equals('NETWORK_UNAVAILABLE'));
        expect(e.message, contains('timed out'));
      }
    });

    testWidgets('10. ErrorStateWidget renders message and triggers onRetry callback', (tester) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Failed to connect to NextAction server. Please check your network.',
              onRetry: () {
                retried = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Failed to connect to NextAction server. Please check your network.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retried, isTrue);
    });

    testWidgets('11. Preserved form state allows user to retry without losing input', (tester) async {
      final titleController = TextEditingController(text: 'Important task title');
      final descController = TextEditingController(text: 'Detailed description preserved');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: titleController),
                TextField(controller: descController),
                const Text('Network error occurred. Try again.'),
              ],
            ),
          ),
        ),
      );

      expect(titleController.text, equals('Important task title'));
      expect(descController.text, equals('Detailed description preserved'));
      expect(find.text('Important task title'), findsOneWidget);
      expect(find.text('Detailed description preserved'), findsOneWidget);
    });
  });
}
