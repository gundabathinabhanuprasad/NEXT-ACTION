import '../../core/network/api_client.dart';
import '../../models/scheduler/scheduler_models.dart';

/// Service for interacting with the Phase 19 Scheduler & Automated Evaluation Engine.
class SchedulerService {
  final ApiClient _apiClient;

  SchedulerService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Trigger evaluation of due reminders, follow-ups, next actions, overdue tasks, and attempt limits.
  Future<SchedulerEvaluationResponse> evaluateScheduler({
    DateTime? asOf,
    bool userScoped = true,
  }) async {
    final body = <String, dynamic>{
      'user_scoped': userScoped,
    };
    if (asOf != null) {
      body['as_of'] = asOf.toUtc().toIso8601String();
    }

    final response = await _apiClient.post(
      '/scheduler/evaluate',
      body: body,
      requiresAuth: true,
    );

    return SchedulerEvaluationResponse.fromJson(response as Map<String, dynamic>);
  }
}
