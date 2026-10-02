import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/models/follow_up/follow_up_models.dart';
import 'package:nextaction/models/history/task_history_models.dart';
import 'package:nextaction/models/reminder/reminder_models.dart';
import 'package:nextaction/models/task/task_models.dart';

void main() {
  group('Model Serialization Tests', () {
    test('Task model correctly deserializes from FastAPI JSON response', () {
      final jsonMap = {
        'id': '9f9d784a-912c-4903-8893-d14457dbba91',
        'title': 'Call prospect regarding contract',
        'description': 'Discussion on enterprise SLA terms',
        'subject_line': 'RE: Enterprise SLA',
        'client_id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        'workflow_id': null,
        'assigned_user_id': 'e3b0c442-98fc-1c14-9afb-f4c8996fb924',
        'status': 'in_progress',
        'priority': 'high',
        'due_date': '2026-10-01T15:00:00Z',
        'next_action_date': '2026-09-28T09:00:00Z',
        'attempt_count': 1,
        'max_attempts': 3,
        'completed_at': null,
        'created_at': '2026-09-27T12:00:00Z',
        'updated_at': '2026-09-27T12:30:00Z',
      };

      final task = Task.fromJson(jsonMap);

      expect(task.id, equals('9f9d784a-912c-4903-8893-d14457dbba91'));
      expect(task.title, equals('Call prospect regarding contract'));
      expect(task.description, equals('Discussion on enterprise SLA terms'));
      expect(task.subjectLine, equals('RE: Enterprise SLA'));
      expect(task.clientId, equals('3fa85f64-5717-4562-b3fc-2c963f66afa6'));
      expect(task.workflowId, isNull);
      expect(task.assignedUserId, equals('e3b0c442-98fc-1c14-9afb-f4c8996fb924'));
      expect(task.status, equals('in_progress'));
      expect(task.priority, equals('high'));
      expect(task.attemptCount, equals(1));
      expect(task.maxAttempts, equals(3));
      expect(task.hasReachedMaxAttempts, isFalse);
      expect(task.canAttemptNormally, isTrue);
      expect(task.isCompleted, isFalse);
      expect(task.dueDate, equals(DateTime.parse('2026-10-01T15:00:00Z')));
    });

    test('TaskListResponse parses list and pagination metadata', () {
      final jsonMap = {
        'items': [
          {
            'id': 't1',
            'title': 'Task 1',
            'status': 'pending',
            'priority': 'medium',
            'attempt_count': 0,
            'max_attempts': 2,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          },
          {
            'id': 't2',
            'title': 'Task 2',
            'status': 'completed',
            'priority': 'low',
            'attempt_count': 2,
            'max_attempts': 2,
            'completed_at': '2026-09-27T11:00:00Z',
            'created_at': '2026-09-27T09:00:00Z',
            'updated_at': '2026-09-27T11:00:00Z',
          },
        ],
        'total': 2,
        'page': 1,
        'page_size': 20,
      };

      final response = TaskListResponse.fromJson(jsonMap);

      expect(response.total, equals(2));
      expect(response.page, equals(1));
      expect(response.items.length, equals(2));
      expect(response.items[0].title, equals('Task 1'));
      expect(response.items[1].isCompleted, isTrue);
      expect(response.items[1].hasReachedMaxAttempts, isTrue);
    });

    test('TaskHistory model deserializes audit history logs', () {
      final jsonMap = {
        'id': 'h1',
        'task_id': 't1',
        'action': 'override_attempt',
        'old_value': '2',
        'new_value': '3',
        'reason': 'Special manager approved attempt',
        'created_by_user_id': 'u1',
        'created_at': '2026-09-27T14:00:00Z',
      };

      final history = TaskHistory.fromJson(jsonMap);

      expect(history.action, equals('override_attempt'));
      expect(history.oldValue, equals('2'));
      expect(history.newValue, equals('3'));
      expect(history.reason, equals('Special manager approved attempt'));
    });

    test('Reminder and FollowUp models deserialize correctly', () {
      final reminderJson = {
        'id': 'r1',
        'task_id': 't1',
        'remind_at': '2026-09-28T10:00:00Z',
        'message': 'Follow up reminder',
        'is_sent': false,
        'created_at': '2026-09-27T10:00:00Z',
        'updated_at': '2026-09-27T10:00:00Z',
      };
      final reminder = Reminder.fromJson(reminderJson);
      expect(reminder.message, equals('Follow up reminder'));
      expect(reminder.isSent, isFalse);

      final followUpJson = {
        'id': 'f1',
        'task_id': 't1',
        'scheduled_at': '2026-09-29T14:00:00Z',
        'completed_at': null,
        'notes': 'Check on signed contract',
        'created_at': '2026-09-27T10:00:00Z',
        'updated_at': '2026-09-27T10:00:00Z',
      };
      final followUp = FollowUp.fromJson(followUpJson);
      expect(followUp.notes, equals('Check on signed contract'));
      expect(followUp.isCompleted, isFalse);
    });
  });
}
