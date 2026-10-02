// Phase 18: Settings Provider & Application State Management.

import 'package:flutter/material.dart';
import '../models/settings/settings_models.dart';
import '../services/settings/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsService _settingsService;

  UserSettings? _settings;
  bool _isLoading = false;
  String? _errorMessage;

  SettingsProvider({SettingsService? settingsService})
      : _settingsService = settingsService ?? SettingsService();

  UserSettings? get settings => _settings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  ThemeMode get themeMode {
    switch (_settings?.theme.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  bool get isCompact => _settings?.compactMode ?? false;
  String get timezone => _settings?.timezone ?? 'UTC';
  String get defaultTaskPriority => _settings?.defaultTaskPriority ?? 'medium';
  int get defaultMaxAttempts => _settings?.defaultMaxAttempts ?? 3;
  String get defaultDashboardRange => _settings?.defaultDashboardTimeRange ?? 'last_7_days';
  String get defaultReportDateRange => _settings?.defaultReportDateRange ?? 'last_7_days';
  String get defaultReportType => _settings?.defaultReportType ?? 'task_summary';
  String get defaultExportFormat => _settings?.defaultExportFormat ?? 'csv';

  /// Load settings from the backend. Fallback to sensible defaults on network/auth error.
  Future<void> loadSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await _settingsService.getSettings();
    } catch (e) {
      _errorMessage = e.toString();
      _settings ??= _defaultFallbackSettings();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Partial update of user preferences.
  Future<bool> updateSettings(UserSettingsUpdate updates) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await _settingsService.updateSettings(updates);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Reset preferences back to system defaults.
  Future<bool> resetSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await _settingsService.resetSettings();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear all cached user settings and preferences on logout or session expiry.
  void clear() {
    _settings = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  static UserSettings _defaultFallbackSettings() {
    final now = DateTime.now();
    return UserSettings(
      id: 'local-fallback',
      userId: 'local-user',
      timezone: 'UTC',
      dateFormat: 'YYYY-MM-DD',
      timeFormat: '24h',
      firstDayOfWeek: 'monday',
      theme: 'system',
      compactMode: false,
      defaultTaskPriority: 'medium',
      defaultTaskStatusFilter: 'all',
      defaultTaskSort: 'due_date',
      defaultTaskSortOrder: 'asc',
      defaultMaxAttempts: 3,
      defaultPageSize: 20,
      defaultDashboardTimeRange: 'last_7_days',
      defaultReportDateRange: 'last_7_days',
      defaultReportType: 'task_summary',
      defaultExportFormat: 'csv',
      notifyTaskAssigned: true,
      notifyTaskReassigned: true,
      notifyReminderDue: true,
      notifyFollowUpDue: true,
      notifyNextActionDue: true,
      notifyTaskOverdue: true,
      notifyAttemptLimitReached: true,
      notifyTaskCompleted: true,
      notifyTaskReopened: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}
