import '../../core/network/api_client.dart';
import '../../models/notification/notification_models.dart';

/// Service for managing In-App Notifications and Alerts via the FastAPI REST API.
class NotificationService {
  final ApiClient _apiClient;

  NotificationService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve paginated notifications strictly scoped to the authenticated user.
  Future<NotificationListResponse> getNotifications({
    bool unreadOnly = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, dynamic>{
      'unread_only': unreadOnly,
      'page': page,
      'page_size': pageSize,
    };

    final response = await _apiClient.get(
      '/notifications',
      queryParameters: queryParams,
      requiresAuth: true,
    );

    return NotificationListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Get the total count of unread notifications for the authenticated user.
  Future<int> getUnreadCount() async {
    final response = await _apiClient.get(
      '/notifications/unread-count',
      requiresAuth: true,
    );

    final res = UnreadCountResponse.fromJson(response as Map<String, dynamic>);
    return res.unreadCount;
  }

  /// Mark a specific notification as read.
  Future<AppNotification> markAsRead(String notificationId) async {
    final response = await _apiClient.post(
      '/notifications/$notificationId/read',
      body: const {},
      requiresAuth: true,
    );

    return AppNotification.fromJson(response as Map<String, dynamic>);
  }

  /// Mark all unread notifications belonging to the authenticated user as read.
  Future<int> markAllAsRead() async {
    final response = await _apiClient.post(
      '/notifications/read-all',
      body: const {},
      requiresAuth: true,
    );

    final res = UnreadCountResponse.fromJson(response as Map<String, dynamic>);
    return res.unreadCount;
  }

  /// Retrieve a single notification ensuring ownership by authenticated user.
  Future<AppNotification> getNotification(String notificationId) async {
    final response = await _apiClient.get(
      '/notifications/$notificationId',
      requiresAuth: true,
    );

    return AppNotification.fromJson(response as Map<String, dynamic>);
  }

  /// Trigger evaluation of due reminders, follow-ups, next actions, overdue tasks, and max attempts.
  Future<NotificationEvaluateResponse> evaluateNotifications() async {
    final response = await _apiClient.post(
      '/notifications/evaluate',
      body: const {},
      requiresAuth: true,
    );

    return NotificationEvaluateResponse.fromJson(response as Map<String, dynamic>);
  }
}
