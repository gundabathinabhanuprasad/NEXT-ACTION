import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/screens/home/home_screen.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/follow_up/follow_up_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/reminder/reminder_service.dart';
import 'package:nextaction/services/task/task_service.dart';
import 'package:nextaction/services/user/user_service.dart';
import 'package:nextaction/services/workflow/workflow_service.dart';

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
  group('Phase 12 — HomeScreen Attention & Notification Badge Tests', () {
    testWidgets('HomeScreen renders Notification Bell Badge and Attention & Recent Alerts section', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 'u-1',
              'name': 'Bhanu Pratap',
              'email': 'bhanu@nextaction.local',
              'is_active': true,
              'created_at': '2026-09-29T10:00:00Z',
              'updated_at': '2026-09-29T10:00:00Z',
            }),
            200,
          );
        }

        if (request.url.path == '/api/v1/tasks') {
          return http.Response(
            jsonEncode({
              'items': [],
              'total': 0,
              'page': 1,
              'page_size': 100,
            }),
            200,
          );
        }

        if (request.url.path == '/api/v1/follow-ups') {
          return http.Response(jsonEncode([]), 200);
        }

        if (request.url.path == '/api/v1/reminders') {
          return http.Response(jsonEncode([]), 200);
        }

        if (request.url.path == '/api/v1/tasks/activity/recent') {
          return http.Response(jsonEncode([]), 200);
        }

        if (request.url.path == '/api/v1/clients') {
          return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 1}), 200);
        }

        if (request.url.path == '/api/v1/workflows') {
          return http.Response(jsonEncode({'items': [], 'total': 0, 'page': 1, 'page_size': 1}), 200);
        }

        if (request.url.path == '/api/v1/users') {
          return http.Response(jsonEncode({'items': [], 'total': 1, 'page': 1, 'page_size': 1}), 200);
        }

        if (request.url.path == '/api/v1/notifications') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'notif-1',
                  'user_id': 'u-1',
                  'type': 'task_assigned',
                  'title': 'New Task: Security Review',
                  'message': 'Assigned to review auth tokens.',
                  'is_read': false,
                  'created_at': '2026-09-29T10:00:00Z',
                  'updated_at': '2026-09-29T10:00:00Z',
                }
              ],
              'total': 1,
              'unread_count': 3,
              'page': 1,
              'page_size': 5,
            }),
            200,
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final tokenStorage = InMemoryTokenStorage('test_jwt_token');
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final authProvider = AuthProvider(authService: authService);
      final taskService = TaskService(apiClient: apiClient);
      final clientService = ClientService(apiClient: apiClient);
      final workflowService = WorkflowService(apiClient: apiClient);
      final userService = UserService(apiClient: apiClient);
      final reminderService = ReminderService(apiClient: apiClient);
      final followUpService = FollowUpService(apiClient: apiClient);
      final notifService = NotificationService(apiClient: apiClient);

      await authProvider.checkAuthStatus();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            authProvider: authProvider,
            taskService: taskService,
            clientService: clientService,
            workflowService: workflowService,
            userService: userService,
            reminderService: reminderService,
            followUpService: followUpService,
            notificationService: notifService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Bell Icon exists with tooltip 'Notifications'
      expect(find.byTooltip('Notifications'), findsOneWidget);

      // Verify Unread Badge shows '3'
      expect(find.text('3'), findsWidgets);

      // Verify "Attention & Recent Alerts" section
      expect(find.text('Attention & Recent Alerts'), findsOneWidget);
      expect(find.text('New Task: Security Review'), findsOneWidget);
      expect(find.text('ASSIGNED'), findsOneWidget);
    });
  });
}
