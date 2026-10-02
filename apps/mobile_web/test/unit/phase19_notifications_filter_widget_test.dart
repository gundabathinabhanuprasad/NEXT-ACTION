// Phase 19 NotificationsScreen Category Filtering & Scheduler Integration Widget Test

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/models/notification/notification_models.dart';
import 'package:nextaction/screens/notifications/notifications_screen.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/scheduler/scheduler_service.dart';
import 'package:nextaction/services/task/task_service.dart';

class MockNotificationsApiClient extends ApiClient {
  List<AppNotification> sampleNotifications = [];
  bool evaluateCalled = false;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    if (path == '/notifications') {
      return {
        'items': sampleNotifications.map((n) => n.toJson()).toList(),
        'total': sampleNotifications.length,
        'unread_count': sampleNotifications.where((n) => !n.isRead).length,
        'page': 1,
        'page_size': 100,
      };
    }
    if (path == '/notifications/unread-count') {
      return {
        'unread_count': sampleNotifications.where((n) => !n.isRead).length,
      };
    }
    throw UnimplementedError('GET $path not mocked');
  }

  @override
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    if (path == '/scheduler/evaluate') {
      evaluateCalled = true;
      return {
        'evaluated': 10,
        'notifications_created': 2,
        'duplicates_skipped': 4,
        'preferences_suppressed': 1,
        'errors_count': 0,
        'duration_ms': 5.2,
        'evaluated_at': DateTime.now().toIso8601String(),
        'user_id': 'u1',
        'details': {},
      };
    }
    if (path == '/notifications/read-all') {
      return {'unread_count': 0};
    }
    throw UnimplementedError('POST $path not mocked');
  }
}

void main() {
  testWidgets('NotificationsScreen displays category filter chips and filters correctly', (WidgetTester tester) async {
    final mockClient = MockNotificationsApiClient();
    final now = DateTime.now();

    mockClient.sampleNotifications = [
      AppNotification(
        id: 'n1',
        userId: 'u1',
        type: 'reminder_due',
        title: 'Review Marketing Deck',
        message: 'Reminder is due',
        isRead: false,
        createdAt: now,
        updatedAt: now,
      ),
      AppNotification(
        id: 'n2',
        userId: 'u1',
        type: 'task_overdue',
        title: 'Submit Tax Filings',
        message: 'Task is overdue',
        isRead: false,
        createdAt: now,
        updatedAt: now,
      ),
      AppNotification(
        id: 'n3',
        userId: 'u1',
        type: 'near_max_attempts',
        title: 'Payment Gateway Integration',
        message: 'Near max attempts',
        isRead: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final notifService = NotificationService(apiClient: mockClient);
    final taskService = TaskService(apiClient: mockClient);
    final schedulerService = SchedulerService(apiClient: mockClient);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          notificationService: notifService,
          taskService: taskService,
          schedulerService: schedulerService,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Notification Center title and unread count badge
    expect(find.text('Notification Center'), findsOneWidget);
    expect(find.text('3'), findsNWidgets(2)); // Badge and All (3)

    // Verify all 3 notification titles are visible initially
    expect(find.text('Review Marketing Deck'), findsOneWidget);
    expect(find.text('Submit Tax Filings'), findsOneWidget);
    expect(find.text('Payment Gateway Integration'), findsOneWidget);

    // Verify category chips are present
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Attempt Limits'), findsOneWidget);

    // Tap "Reminders" filter chip
    await tester.ensureVisible(find.text('Reminders'));
    await tester.tap(find.text('Reminders'));
    await tester.pumpAndSettle();

    // Only "Review Marketing Deck" should be visible
    expect(find.text('Review Marketing Deck'), findsOneWidget);
    expect(find.text('Submit Tax Filings'), findsNothing);
    expect(find.text('Payment Gateway Integration'), findsNothing);

    // Tap "Attempt Limits" filter chip
    await tester.ensureVisible(find.text('Attempt Limits'));
    await tester.tap(find.text('Attempt Limits'));
    await tester.pumpAndSettle();

    // Only "Payment Gateway Integration" should be visible
    expect(find.text('Payment Gateway Integration'), findsOneWidget);
    expect(find.text('Review Marketing Deck'), findsNothing);

    // Tap evaluate action button (Icons.sync)
    final syncIcon = find.byIcon(Icons.sync);
    expect(syncIcon, findsOneWidget);
    await tester.tap(syncIcon);
    await tester.pumpAndSettle();

    expect(mockClient.evaluateCalled, isTrue);
  });
}
