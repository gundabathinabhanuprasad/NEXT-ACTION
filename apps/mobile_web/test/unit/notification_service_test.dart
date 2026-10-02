import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/services/notification/notification_service.dart';

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
  group('NotificationService Tests', () {
    late TokenStorage tokenStorage;

    setUp(() {
      tokenStorage = InMemoryTokenStorage('test_jwt_token');
    });

    test('getNotifications sends unread_only and pagination query params', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/notifications'));
        expect(request.url.queryParameters['unread_only'], equals('true'));
        expect(request.url.queryParameters['page'], equals('1'));
        expect(request.url.queryParameters['page_size'], equals('20'));
        expect(request.headers['Authorization'], equals('Bearer test_jwt_token'));

        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'notif-1',
                'user_id': 'u-1',
                'task_id': 'task-1',
                'type': 'task_assigned',
                'title': 'New Task',
                'message': 'Assigned to you',
                'is_read': false,
                'created_at': '2026-09-29T10:00:00Z',
                'updated_at': '2026-09-29T10:00:00Z',
              }
            ],
            'total': 1,
            'unread_count': 1,
            'page': 1,
            'page_size': 20,
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = NotificationService(apiClient: apiClient);

      final result = await service.getNotifications(unreadOnly: true, page: 1, pageSize: 20);

      expect(result.total, equals(1));
      expect(result.unreadCount, equals(1));
      expect(result.items.first.id, equals('notif-1'));
      expect(result.items.first.isRead, isFalse);
    });

    test('getUnreadCount returns integer count', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/notifications/unread-count'));
        return http.Response(
          jsonEncode({'unread_count': 5}),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = NotificationService(apiClient: apiClient);

      final count = await service.getUnreadCount();
      expect(count, equals(5));
    });

    test('markAsRead calls /api/v1/notifications/{id}/read', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/notifications/notif-123/read'));
        expect(request.method, equals('POST'));
        return http.Response(
          jsonEncode({
            'id': 'notif-123',
            'user_id': 'u-1',
            'task_id': 'task-1',
            'type': 'reminder_due',
            'title': 'Reminder Due',
            'message': 'Reminder message',
            'is_read': true,
            'read_at': '2026-09-29T11:00:00Z',
            'created_at': '2026-09-29T10:00:00Z',
            'updated_at': '2026-09-29T11:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = NotificationService(apiClient: apiClient);

      final notif = await service.markAsRead('notif-123');
      expect(notif.id, equals('notif-123'));
      expect(notif.isRead, isTrue);
    });

    test('markAllAsRead calls /api/v1/notifications/read-all', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/notifications/read-all'));
        expect(request.method, equals('POST'));
        return http.Response(
          jsonEncode({'unread_count': 0}),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = NotificationService(apiClient: apiClient);

      final remaining = await service.markAllAsRead();
      expect(remaining, equals(0));
    });

    test('evaluateNotifications calls /api/v1/notifications/evaluate', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/notifications/evaluate'));
        expect(request.method, equals('POST'));
        return http.Response(
          jsonEncode({
            'created_count': 3,
            'evaluated_at': '2026-09-29T12:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = NotificationService(apiClient: apiClient);

      final result = await service.evaluateNotifications();
      expect(result.createdCount, equals(3));
    });
  });
}
