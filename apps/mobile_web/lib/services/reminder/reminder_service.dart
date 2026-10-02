import '../../core/network/api_client.dart';
import '../../models/reminder/reminder_models.dart';

/// Service for managing Reminder entities and operations via the FastAPI REST API.
class ReminderService {
  final ApiClient _apiClient;

  ReminderService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve reminders with optional task_id and is_sent filter.
  Future<List<Reminder>> getReminders({
    String? taskId,
    bool? isSent,
  }) async {
    final queryParams = <String, dynamic>{
      if (taskId != null) 'task_id': taskId,
      if (isSent != null) 'is_sent': isSent,
    };

    final response = await _apiClient.get(
      '/reminders',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      requiresAuth: true,
    );

    final list = response as List<dynamic>? ?? [];
    return list.map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Retrieve due reminders on or before the given timestamp (default UTC now).
  Future<List<Reminder>> getDueReminders({DateTime? asOf}) async {
    final queryParams = <String, dynamic>{
      if (asOf != null) 'as_of': asOf.toIso8601String(),
    };

    final response = await _apiClient.get(
      '/reminders/due',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      requiresAuth: true,
    );

    final list = response as List<dynamic>? ?? [];
    return list.map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Retrieve a single reminder by ID.
  Future<Reminder> getReminder(String reminderId) async {
    final response = await _apiClient.get(
      '/reminders/$reminderId',
      requiresAuth: true,
    );
    return Reminder.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve reminders for a specific task.
  Future<List<Reminder>> getTaskReminders(String taskId) async {
    final response = await _apiClient.get(
      '/tasks/$taskId/reminders',
      requiresAuth: true,
    );
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a new reminder for a task.
  /// CRITICAL INVARIANT: Does NOT increment Task.attempt_count.
  Future<Reminder> createReminder(ReminderCreateRequest request) async {
    final response = await _apiClient.post(
      '/reminders',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Reminder.fromJson(response as Map<String, dynamic>);
  }

  /// Mark a reminder as sent/processed.
  /// CRITICAL INVARIANT: Does NOT increment Task.attempt_count.
  Future<Reminder> sendReminder(String reminderId) async {
    final response = await _apiClient.post(
      '/reminders/$reminderId/send',
      body: const {},
      requiresAuth: true,
    );
    return Reminder.fromJson(response as Map<String, dynamic>);
  }

  /// Delete/cancel a reminder by ID.
  Future<void> deleteReminder(String reminderId) async {
    await _apiClient.delete(
      '/reminders/$reminderId',
      requiresAuth: true,
    );
  }
}
