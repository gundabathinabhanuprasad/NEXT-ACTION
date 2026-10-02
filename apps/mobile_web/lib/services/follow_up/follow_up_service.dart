import '../../core/network/api_client.dart';
import '../../models/follow_up/follow_up_models.dart';

/// Service for managing FollowUp entities and operations via the FastAPI REST API.
class FollowUpService {
  final ApiClient _apiClient;

  FollowUpService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve follow-ups with optional task and completion status filtering.
  Future<List<FollowUp>> getFollowUps({
    String? taskId,
    bool? isCompleted,
  }) async {
    final queryParams = <String, dynamic>{
      if (taskId != null) 'task_id': taskId,
      if (isCompleted != null) 'is_completed': isCompleted,
    };

    final response = await _apiClient.get(
      '/follow-ups',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      requiresAuth: true,
    );

    final list = response as List<dynamic>? ?? [];
    return list.map((e) => FollowUp.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Retrieve a specific follow-up by ID.
  Future<FollowUp> getFollowUp(String followUpId) async {
    final response = await _apiClient.get(
      '/follow-ups/$followUpId',
      requiresAuth: true,
    );
    return FollowUp.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve follow-ups for a specific task.
  Future<List<FollowUp>> getTaskFollowUps(String taskId) async {
    final response = await _apiClient.get(
      '/tasks/$taskId/follow-ups',
      requiresAuth: true,
    );
    final list = response as List<dynamic>? ?? [];
    return list.map((e) => FollowUp.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a new follow-up for a task.
  /// CRITICAL INVARIANT: Does NOT increment Task.attempt_count.
  Future<FollowUp> createFollowUp(FollowUpCreateRequest request) async {
    final response = await _apiClient.post(
      '/follow-ups',
      body: request.toJson(),
      requiresAuth: true,
    );
    return FollowUp.fromJson(response as Map<String, dynamic>);
  }

  /// Mark a follow-up as completed.
  /// CRITICAL INVARIANT: Does NOT auto-complete task or modify task attempt_count.
  Future<FollowUp> completeFollowUp(
    String followUpId, {
    DateTime? completedAt,
    String? notes,
  }) async {
    final payload = FollowUpCompleteRequest(
      completedAt: completedAt,
      notes: notes,
    );
    final response = await _apiClient.post(
      '/follow-ups/$followUpId/complete',
      body: payload.toJson(),
      requiresAuth: true,
    );
    return FollowUp.fromJson(response as Map<String, dynamic>);
  }

  /// Delete a follow-up by ID.
  Future<void> deleteFollowUp(String followUpId) async {
    await _apiClient.delete(
      '/follow-ups/$followUpId',
      requiresAuth: true,
    );
  }
}
