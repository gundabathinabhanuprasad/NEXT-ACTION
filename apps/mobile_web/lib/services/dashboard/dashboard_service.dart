import '../../core/network/api_client.dart';
import '../../models/dashboard/dashboard_models.dart';

/// Service for fetching consolidated PostgreSQL dashboard summaries and productivity analytics.
class DashboardService {
  final ApiClient _apiClient;

  DashboardService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve the consolidated operational dashboard summary from PostgreSQL.
  Future<DashboardSummary> getDashboardSummary({
    String timeRange = 'last_7_days',
  }) async {
    final queryParams = <String, dynamic>{
      'time_range': timeRange,
    };

    final response = await _apiClient.get(
      '/dashboard/summary',
      queryParameters: queryParams,
      requiresAuth: true,
    );

    return DashboardSummary.fromJson(response as Map<String, dynamic>);
  }
}
