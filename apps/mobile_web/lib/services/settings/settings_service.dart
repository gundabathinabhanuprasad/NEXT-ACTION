// Phase 18: User Settings & Personalization REST Service.

import '../../core/network/api_client.dart';
import '../../models/settings/settings_models.dart';

class SettingsService {
  final ApiClient _apiClient;

  SettingsService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve the current authenticated user's settings and preferences.
  Future<UserSettings> getSettings() async {
    final response = await _apiClient.get(
      '/settings',
      requiresAuth: true,
    );
    return UserSettings.fromJson(response as Map<String, dynamic>);
  }

  /// Partial update (PATCH) of user settings.
  Future<UserSettings> updateSettings(UserSettingsUpdate updates) async {
    final response = await _apiClient.patch(
      '/settings',
      body: updates.toJson(),
      requiresAuth: true,
    );
    return UserSettings.fromJson(response as Map<String, dynamic>);
  }

  /// Reset user settings back to system defaults.
  Future<UserSettings> resetSettings() async {
    final response = await _apiClient.post(
      '/settings/reset',
      body: {},
      requiresAuth: true,
    );
    return UserSettings.fromJson(response as Map<String, dynamic>);
  }
}
