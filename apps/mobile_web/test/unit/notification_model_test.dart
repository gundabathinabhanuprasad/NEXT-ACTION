import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/models/notification/notification_models.dart';

void main() {
  group('Notification Model & Serialization Tests', () {
    test('AppNotification deserializes correctly from FastAPI JSON response', () {
      final json = {
        'id': 'b1111111-2222-3333-4444-555555555555',
        'user_id': 'u1111111-2222-3333-4444-555555555555',
        'task_id': 't1111111-2222-3333-4444-555555555555',
        'type': 'task_assigned',
        'title': 'New Task Assigned: Setup Database',
        'message': 'You have been assigned to task Setup Database.',
        'dedup_key': 'task_assigned:t111:u111',
        'is_read': false,
        'read_at': null,
        'created_at': '2026-09-29T10:00:00.000Z',
        'updated_at': '2026-09-29T10:00:00.000Z',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.id, 'b1111111-2222-3333-4444-555555555555');
      expect(notif.userId, 'u1111111-2222-3333-4444-555555555555');
      expect(notif.taskId, 't1111111-2222-3333-4444-555555555555');
      expect(notif.type, 'task_assigned');
      expect(notif.title, 'New Task Assigned: Setup Database');
      expect(notif.message, 'You have been assigned to task Setup Database.');
      expect(notif.dedupKey, 'task_assigned:t111:u111');
      expect(notif.isRead, false);
      expect(notif.readAt, isNull);
      expect(notif.isTaskAssigned, isTrue);
      expect(notif.isReminderDue, isFalse);
      expect(notif.isOverdue, isFalse);
    });

    test('Helper getters correctly identify notification types', () {
      final baseJson = {
        'id': 'b111',
        'user_id': 'u111',
        'title': 'Test',
        'message': 'Msg',
        'is_read': true,
        'read_at': '2026-09-29T10:05:00.000Z',
        'created_at': '2026-09-29T10:00:00.000Z',
        'updated_at': '2026-09-29T10:05:00.000Z',
      };

      final remNotif = AppNotification.fromJson({...baseJson, 'type': 'reminder_due'});
      expect(remNotif.isReminderDue, isTrue);
      expect(remNotif.isRead, isTrue);

      final followUpNotif = AppNotification.fromJson({...baseJson, 'type': 'follow_up_due'});
      expect(followUpNotif.isFollowUpDue, isTrue);

      final nextActionNotif = AppNotification.fromJson({...baseJson, 'type': 'next_action_due'});
      expect(nextActionNotif.isNextActionDue, isTrue);

      final overdueNotif = AppNotification.fromJson({...baseJson, 'type': 'task_overdue'});
      expect(overdueNotif.isOverdue, isTrue);

      final attemptLimitNotif = AppNotification.fromJson({...baseJson, 'type': 'attempt_limit_reached'});
      expect(attemptLimitNotif.isAttemptLimit, isTrue);

      final compNotif = AppNotification.fromJson({...baseJson, 'type': 'task_completed'});
      expect(compNotif.isCompleted, isTrue);

      final reopenNotif = AppNotification.fromJson({...baseJson, 'type': 'task_reopened'});
      expect(reopenNotif.isReopened, isTrue);
    });

    test('NotificationListResponse parses list, totals, and unread counts', () {
      final json = {
        'items': [
          {
            'id': 'n1',
            'user_id': 'u1',
            'type': 'task_assigned',
            'title': 'Task 1',
            'message': 'Msg 1',
            'is_read': false,
            'created_at': '2026-09-29T10:00:00.000Z',
          },
          {
            'id': 'n2',
            'user_id': 'u1',
            'type': 'reminder_due',
            'title': 'Task 2',
            'message': 'Msg 2',
            'is_read': true,
            'read_at': '2026-09-29T10:05:00.000Z',
            'created_at': '2026-09-29T10:00:00.000Z',
          }
        ],
        'total': 15,
        'unread_count': 6,
        'page': 1,
        'page_size': 20,
      };

      final response = NotificationListResponse.fromJson(json);

      expect(response.total, 15);
      expect(response.unreadCount, 6);
      expect(response.page, 1);
      expect(response.pageSize, 20);
      expect(response.items.length, 2);
      expect(response.items[0].id, 'n1');
      expect(response.items[0].isRead, isFalse);
      expect(response.items[1].id, 'n2');
      expect(response.items[1].isRead, isTrue);
    });

    test('UnreadCountResponse and NotificationEvaluateResponse parse correctly', () {
      final countJson = {'unread_count': 7};
      final unreadRes = UnreadCountResponse.fromJson(countJson);
      expect(unreadRes.unreadCount, 7);

      final evalJson = {
        'created_count': 4,
        'evaluated_at': '2026-09-29T12:00:00.000Z',
      };
      final evalRes = NotificationEvaluateResponse.fromJson(evalJson);
      expect(evalRes.createdCount, 4);
      expect(evalRes.evaluatedAt.toUtc().hour, 12);
    });
  });
}
