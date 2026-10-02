import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/screens/notifications/notifications_screen.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/task/task_service.dart';

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
  group('Phase 12 — NotificationsScreen Widget Integration Tests', () {
    testWidgets('1. NotificationsScreen renders header, unread badge, items, and filters', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/notifications') {
          final unreadOnly = request.url.queryParameters['unread_only'] == 'true';
          final items = [
            {
              'id': 'notif-1',
              'user_id': 'u-1',
              'task_id': 'task-101',
              'type': 'task_assigned',
              'title': 'New Task Assigned: Deploy Release',
              'message': 'You have been assigned to task Deploy Release.',
              'is_read': false,
              'created_at': '2026-09-29T10:00:00Z',
              'updated_at': '2026-09-29T10:00:00Z',
            },
            if (!unreadOnly)
              {
                'id': 'notif-2',
                'user_id': 'u-1',
                'task_id': 'task-102',
                'type': 'reminder_due',
                'title': 'Reminder: Client Call',
                'message': 'Meeting reminder for client call.',
                'is_read': true,
                'read_at': '2026-09-29T09:30:00Z',
                'created_at': '2026-09-29T09:00:00Z',
                'updated_at': '2026-09-29T09:30:00Z',
              },
          ];

          return http.Response(
            jsonEncode({
              'items': items,
              'total': unreadOnly ? 1 : 2,
              'unread_count': 1,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final tokenStorage = InMemoryTokenStorage('test_token');
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final notifService = NotificationService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            notificationService: notifService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Notification Center'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Unread'), findsWidgets);

      // Verify Notification Items
      expect(find.text('New Task Assigned: Deploy Release'), findsOneWidget);
      expect(find.text('Reminder: Client Call'), findsOneWidget);
      expect(find.text('ASSIGNED'), findsOneWidget);
      expect(find.text('REMINDER DUE'), findsOneWidget);

      // Switch to Unread filter
      await tester.tap(find.text('Unread').first);
      await tester.pumpAndSettle();

      expect(find.text('New Task Assigned: Deploy Release'), findsOneWidget);
      expect(find.text('Reminder: Client Call'), findsNothing);
    });

    testWidgets('2. NotificationsScreen marks single notification read and marks all read', (WidgetTester tester) async {
      bool markedSingle = false;
      bool markedAll = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/notifications/notif-1/read') {
          markedSingle = true;
          return http.Response(
            jsonEncode({
              'id': 'notif-1',
              'user_id': 'u-1',
              'task_id': 'task-101',
              'type': 'task_assigned',
              'title': 'New Task Assigned: Deploy Release',
              'message': 'You have been assigned to task Deploy Release.',
              'is_read': true,
              'read_at': '2026-09-29T10:15:00Z',
              'created_at': '2026-09-29T10:00:00Z',
              'updated_at': '2026-09-29T10:15:00Z',
            }),
            200,
          );
        }

        if (request.url.path == '/api/v1/notifications/read-all') {
          markedAll = true;
          return http.Response(jsonEncode({'unread_count': 0}), 200);
        }

        if (request.url.path == '/api/v1/notifications') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'notif-1',
                  'user_id': 'u-1',
                  'task_id': 'task-101',
                  'type': 'task_assigned',
                  'title': 'New Task Assigned: Deploy Release',
                  'message': 'You have been assigned to task Deploy Release.',
                  'is_read': markedSingle || markedAll,
                  'created_at': '2026-09-29T10:00:00Z',
                  'updated_at': '2026-09-29T10:00:00Z',
                }
              ],
              'total': 1,
              'unread_count': markedSingle || markedAll ? 0 : 1,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final tokenStorage = InMemoryTokenStorage('test_token');
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final notifService = NotificationService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            notificationService: notifService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Mark read" button
      expect(find.text('Mark read'), findsOneWidget);
      await tester.tap(find.text('Mark read'));
      await tester.pumpAndSettle();

      expect(markedSingle, isTrue);
    });

    testWidgets('2b. NotificationsScreen marks all notifications as read from AppBar action', (WidgetTester tester) async {
      bool markedAll = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/notifications/read-all') {
          markedAll = true;
          return http.Response(jsonEncode({'unread_count': 0}), 200);
        }

        if (request.url.path == '/api/v1/notifications') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'notif-1',
                  'user_id': 'u-1',
                  'type': 'task_assigned',
                  'title': 'New Task Assigned: Deploy Release',
                  'message': 'You have been assigned to task Deploy Release.',
                  'is_read': markedAll,
                  'created_at': '2026-09-29T10:00:00Z',
                  'updated_at': '2026-09-29T10:00:00Z',
                }
              ],
              'total': 1,
              'unread_count': markedAll ? 0 : 1,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final tokenStorage = InMemoryTokenStorage('test_token');
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final notifService = NotificationService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            notificationService: notifService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Mark All as Read" AppBar action
      await tester.tap(find.byTooltip('Mark All as Read'));
      await tester.pumpAndSettle();

      expect(markedAll, isTrue);
    });

    testWidgets('3. NotificationsScreen evaluates due alerts and handles empty state', (WidgetTester tester) async {
      bool evaluated = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/notifications/evaluate') {
          evaluated = true;
          return http.Response(
            jsonEncode({
              'created_count': 2,
              'evaluated_at': '2026-09-29T10:00:00Z',
            }),
            200,
          );
        }

        if (request.url.path == '/api/v1/notifications') {
          return http.Response(
            jsonEncode({
              'items': [],
              'total': 0,
              'unread_count': 0,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final tokenStorage = InMemoryTokenStorage('test_token');
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final notifService = NotificationService(apiClient: apiClient);
      final taskService = TaskService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            notificationService: notifService,
            taskService: taskService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify empty state
      expect(find.text('No notifications yet'), findsOneWidget);

      // Tap Evaluate Due Alerts
      await tester.tap(find.byTooltip('Evaluate Due Alerts'));
      await tester.pumpAndSettle();

      expect(evaluated, isTrue);
    });
  });
}
