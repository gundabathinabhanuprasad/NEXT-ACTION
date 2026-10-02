// Phase 18: Settings Models, Service & Provider Unit Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/models/settings/settings_models.dart';
import 'package:nextaction/providers/settings_provider.dart';
import 'package:nextaction/services/settings/settings_service.dart';

class MockSettingsApiClient extends ApiClient {
  Map<String, dynamic>? mockGetResponse;
  Map<String, dynamic>? mockPatchResponse;
  Map<String, dynamic>? mockResetResponse;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers, bool requiresAuth = true}) async {
    if (path == '/settings') {
      return mockGetResponse ?? _sampleSettingsJson();
    }
    throw UnimplementedError('GET $path not mocked');
  }

  @override
  Future<dynamic> patch(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers, bool requiresAuth = true}) async {
    if (path == '/settings') {
      final b = body as Map<String, dynamic>;
      return mockPatchResponse ?? _sampleSettingsJson(theme: b['theme'] as String?, timezone: b['timezone'] as String?);
    }
    throw UnimplementedError('PATCH $path not mocked');
  }

  @override
  Future<dynamic> post(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers, bool requiresAuth = true}) async {
    if (path == '/settings/reset') {
      return mockResetResponse ?? _sampleSettingsJson();
    }
    throw UnimplementedError('POST $path not mocked');
  }

  static Map<String, dynamic> _sampleSettingsJson({String? theme, String? timezone}) {
    final now = DateTime.now().toIso8601String();
    return {
      'id': 'settings-123',
      'user_id': 'user-123',
      'display_name_override': 'Captain Kirk',
      'timezone': timezone ?? 'Asia/Kolkata',
      'date_format': 'DD/MM/YYYY',
      'time_format': '12h',
      'first_day_of_week': 'sunday',
      'theme': theme ?? 'dark',
      'compact_mode': true,
      'default_task_priority': 'urgent',
      'default_task_status_filter': 'pending',
      'default_task_sort': 'created_at',
      'default_task_sort_order': 'desc',
      'default_max_attempts': 5,
      'default_page_size': 50,
      'default_dashboard_time_range': 'last_30_days',
      'default_report_date_range': 'this_month',
      'default_report_type': 'workload',
      'default_export_format': 'json',
      'notify_task_assigned': true,
      'notify_task_reassigned': false,
      'notify_reminder_due': true,
      'notify_follow_up_due': false,
      'notify_next_action_due': true,
      'notify_task_overdue': false,
      'notify_attempt_limit_reached': true,
      'notify_task_completed': false,
      'notify_task_reopened': true,
      'created_at': now,
      'updated_at': now,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 18: UserSettings Model', () {
    test('fromJson and toJson roundtrip preserves all preferences', () {
      final now = DateTime.now();
      final settings = UserSettings(
        id: 's-1',
        userId: 'u-1',
        displayNameOverride: 'Chief',
        timezone: 'Asia/Dubai',
        dateFormat: 'YYYY-MM-DD',
        timeFormat: '24h',
        firstDayOfWeek: 'monday',
        theme: 'light',
        compactMode: false,
        defaultTaskPriority: 'high',
        defaultTaskStatusFilter: 'in_progress',
        defaultTaskSort: 'due_date',
        defaultTaskSortOrder: 'asc',
        defaultMaxAttempts: 4,
        defaultPageSize: 100,
        defaultDashboardTimeRange: 'today',
        defaultReportDateRange: 'last_7_days',
        defaultReportType: 'sla_compliance',
        defaultExportFormat: 'csv',
        notifyTaskAssigned: true,
        notifyTaskReassigned: true,
        notifyReminderDue: false,
        notifyFollowUpDue: true,
        notifyNextActionDue: false,
        notifyTaskOverdue: true,
        notifyAttemptLimitReached: false,
        notifyTaskCompleted: true,
        notifyTaskReopened: false,
        createdAt: now,
        updatedAt: now,
      );

      final json = settings.toJson();
      expect(json['id'], 's-1');
      expect(json['timezone'], 'Asia/Dubai');
      expect(json['theme'], 'light');
      expect(json['notify_reminder_due'], false);
      expect(json['default_max_attempts'], 4);

      final parsed = UserSettings.fromJson(json);
      expect(parsed.id, settings.id);
      expect(parsed.userId, settings.userId);
      expect(parsed.displayNameOverride, 'Chief');
      expect(parsed.timezone, 'Asia/Dubai');
      expect(parsed.theme, 'light');
      expect(parsed.notifyReminderDue, false);
      expect(parsed.defaultTaskPriority, 'high');
      expect(parsed.defaultMaxAttempts, 4);
    });

    test('copyWith updates specified fields and supports clearing displayNameOverride', () {
      final now = DateTime.now();
      final original = UserSettings(
        id: 's-1',
        userId: 'u-1',
        displayNameOverride: 'Nickname',
        timezone: 'UTC',
        createdAt: now,
        updatedAt: now,
      );

      final updated = original.copyWith(
        theme: 'dark',
        defaultTaskPriority: 'urgent',
      );
      expect(updated.theme, 'dark');
      expect(updated.defaultTaskPriority, 'urgent');
      expect(updated.displayNameOverride, 'Nickname');

      final cleared = updated.copyWith(clearDisplayNameOverride: true);
      expect(cleared.displayNameOverride, isNull);
    });
  });

  group('Phase 18: UserSettingsUpdate Model', () {
    test('toJson omits null fields', () {
      const update = UserSettingsUpdate(
        theme: 'dark',
        timezone: 'Asia/Kolkata',
      );

      final json = update.toJson();
      expect(json.length, 2);
      expect(json['theme'], 'dark');
      expect(json['timezone'], 'Asia/Kolkata');
      expect(json.containsKey('default_task_priority'), isFalse);
    });
  });

  group('Phase 18: SettingsService & SettingsProvider', () {
    test('loadSettings updates provider state and derives ThemeMode correctly', () async {
      final mockClient = MockSettingsApiClient();
      final service = SettingsService(apiClient: mockClient);
      final provider = SettingsProvider(settingsService: service);

      expect(provider.settings, isNull);
      expect(provider.themeMode, ThemeMode.system);

      await provider.loadSettings();

      expect(provider.isLoading, isFalse);
      expect(provider.settings, isNotNull);
      expect(provider.settings!.displayNameOverride, 'Captain Kirk');
      expect(provider.settings!.timezone, 'Asia/Kolkata');
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isCompact, isTrue);
      expect(provider.defaultTaskPriority, 'urgent');
      expect(provider.defaultMaxAttempts, 5);
      expect(provider.defaultDashboardRange, 'last_30_days');
    });

    test('updateSettings modifies settings and updates listeners', () async {
      final mockClient = MockSettingsApiClient();
      final service = SettingsService(apiClient: mockClient);
      final provider = SettingsProvider(settingsService: service);

      await provider.loadSettings();

      final success = await provider.updateSettings(
        const UserSettingsUpdate(theme: 'light', timezone: 'Europe/London'),
      );

      expect(success, isTrue);
      expect(provider.settings!.theme, 'light');
      expect(provider.themeMode, ThemeMode.light);
      expect(provider.settings!.timezone, 'Europe/London');
    });

    test('resetSettings restores default configuration', () async {
      final mockClient = MockSettingsApiClient();
      final service = SettingsService(apiClient: mockClient);
      final provider = SettingsProvider(settingsService: service);

      await provider.loadSettings();
      final success = await provider.resetSettings();

      expect(success, isTrue);
      expect(provider.settings, isNotNull);
    });

    test('loadSettings falls back gracefully on network error without blocking app', () async {
      final mockClient = ApiClient(); // Unconfigured client that will fail network call
      final service = SettingsService(apiClient: mockClient);
      final provider = SettingsProvider(settingsService: service);

      await provider.loadSettings();

      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNotNull);
      // Fallback settings populated
      expect(provider.settings, isNotNull);
      expect(provider.settings!.timezone, 'UTC');
      expect(provider.settings!.theme, 'system');
      expect(provider.themeMode, ThemeMode.system);
    });
  });
}
