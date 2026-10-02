import '../../core/network/api_client.dart';
import '../../models/report/report_models.dart';

/// Service for fetching server-side report metrics, datasets, and on-demand exports for Phase 17.
class ReportService {
  final ApiClient _apiClient;

  ReportService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve Task Summary report metrics.
  Future<TaskSummaryReport> getTaskSummaryReport({ReportFilters? filters}) async {
    final queryParams = filters?.toQueryParams() ?? <String, String>{};
    final response = await _apiClient.get(
      '/reports/task-summary',
      queryParameters: queryParams,
      requiresAuth: true,
    );
    return TaskSummaryReport.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve detailed, paginated task list report.
  Future<TaskDetailReportResponse> getTaskDetailReport({
    ReportFilters? filters,
    int page = 1,
    int pageSize = 20,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  }) async {
    final queryParams = filters?.toQueryParams() ?? <String, String>{};
    queryParams['page'] = page.toString();
    queryParams['page_size'] = pageSize.toString();
    queryParams['sort_by'] = sortBy;
    queryParams['sort_order'] = sortOrder;

    final response = await _apiClient.get(
      '/reports/tasks',
      queryParameters: queryParams,
      requiresAuth: true,
    );
    return TaskDetailReportResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve productivity metrics and zero-filled time trends.
  Future<ProductivityReportResponse> getProductivityReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    ReportFilters? filters,
  }) async {
    final queryParams = filters?.toQueryParams() ?? <String, String>{};
    if (dateFrom != null) {
      queryParams['date_from'] = dateFrom.toUtc().toIso8601String();
    }
    if (dateTo != null) {
      queryParams['date_to'] = dateTo.toUtc().toIso8601String();
    }

    final response = await _apiClient.get(
      '/reports/productivity',
      queryParameters: queryParams,
      requiresAuth: true,
    );
    return ProductivityReportResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve multi-dimensional workload report.
  Future<WorkloadReportResponse> getWorkloadReport({ReportFilters? filters}) async {
    final queryParams = filters?.toQueryParams() ?? <String, String>{};
    final response = await _apiClient.get(
      '/reports/workload',
      queryParameters: queryParams,
      requiresAuth: true,
    );
    return WorkloadReportResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve activity audit history report.
  Future<ActivityReportResponse> getActivityReport({
    String? action,
    String? actorId,
    String? taskId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };
    if (action != null && action.isNotEmpty) queryParams['action'] = action;
    if (actorId != null && actorId.isNotEmpty) queryParams['actor_id'] = actorId;
    if (taskId != null && taskId.isNotEmpty) queryParams['task_id'] = taskId;
    if (dateFrom != null) queryParams['date_from'] = dateFrom.toUtc().toIso8601String();
    if (dateTo != null) queryParams['date_to'] = dateTo.toUtc().toIso8601String();
    if (search != null && search.trim().isNotEmpty) queryParams['search'] = search.trim();

    final response = await _apiClient.get(
      '/reports/activity',
      queryParameters: queryParams,
      requiresAuth: true,
    );
    return ActivityReportResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve scheduling queues report for reminders and follow-ups.
  Future<ReminderFollowUpReportResponse> getRemindersFollowupsReport({ReportFilters? filters}) async {
    final queryParams = filters?.toQueryParams() ?? <String, String>{};
    final response = await _apiClient.get(
      '/reports/reminders-followups',
      queryParameters: queryParams,
      requiresAuth: true,
    );
    return ReminderFollowUpReportResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Export on-demand report in CSV or JSON format as raw string.
  Future<String> exportReport({
    required ReportType reportType,
    ExportFormat format = ExportFormat.csv,
    ReportFilters? filters,
    String? action,
    String? actorId,
    String? taskId,
  }) async {
    final queryParams = filters?.toQueryParams() ?? <String, String>{};
    queryParams['report_type'] = reportType.apiValue;
    queryParams['format'] = format.apiValue;
    if (action != null && action.isNotEmpty) queryParams['action'] = action;
    if (actorId != null && actorId.isNotEmpty) queryParams['actor_id'] = actorId;
    if (taskId != null && taskId.isNotEmpty) queryParams['task_id'] = taskId;

    return await _apiClient.getRaw(
      '/reports/export',
      queryParameters: queryParams,
      requiresAuth: true,
    );
  }
}
