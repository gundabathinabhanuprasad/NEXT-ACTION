// Phase 18: Live E2E Verification against PostgreSQL 16 & FastAPI (16 Steps)

import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/settings/settings_models.dart';
import 'package:nextaction/models/task/task_models.dart';
import 'package:nextaction/providers/settings_provider.dart';
import 'package:nextaction/services/auth/auth_service.dart';
import 'package:nextaction/services/notification/notification_service.dart';
import 'package:nextaction/services/settings/settings_service.dart';
import 'package:nextaction/services/task/task_service.dart';

class TestTokenStorage implements TokenStorage {
  String? _token;
  @override
  Future<void> saveToken(String token) async => _token = token;
  @override
  Future<String?> getToken() async => _token;
  @override
  Future<void> deleteToken() async => _token = null;
  @override
  Future<bool> hasToken() async => _token != null && _token!.isNotEmpty;
}

void main() {
  group('Phase 18 Live E2E: Settings, Personalization & System Configuration (16 Steps)', () {
    late ApiClient apiClientA;
    late AuthService authServiceA;
    late SettingsService settingsServiceA;
    late SettingsProvider settingsProviderA;
    late TaskService taskServiceA;
    late NotificationService notificationServiceA;
    late TestTokenStorage tokenStorageA;

    late ApiClient apiClientB;
    late AuthService authServiceB;
    late SettingsService settingsServiceB;
    late SettingsProvider settingsProviderB;
    late TestTokenStorage tokenStorageB;

    final testRunId = DateTime.now().millisecondsSinceEpoch;
    final userAEmail = 'phase18_usera_$testRunId@nextaction.local';
    final userAName = 'Phase 18 User A $testRunId';
    final userBEmail = 'phase18_userb_$testRunId@nextaction.local';
    final userBName = 'Phase 18 User B $testRunId';
    const userPassword = 'Password123!';

    late User userA;
    late User userB;

    setUpAll(() async {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      tokenStorageA = TestTokenStorage();
      apiClientA = ApiClient(tokenStorage: tokenStorageA);
      authServiceA = AuthService(apiClient: apiClientA);
      settingsServiceA = SettingsService(apiClient: apiClientA);
      settingsProviderA = SettingsProvider(settingsService: settingsServiceA);
      taskServiceA = TaskService(apiClient: apiClientA);
      notificationServiceA = NotificationService(apiClient: apiClientA);

      tokenStorageB = TestTokenStorage();
      apiClientB = ApiClient(tokenStorage: tokenStorageB);
      authServiceB = AuthService(apiClient: apiClientB);
      settingsServiceB = SettingsService(apiClient: apiClientB);
      settingsProviderB = SettingsProvider(settingsService: settingsServiceB);
    });

    // 1. Register/login User A and User B
    test('Step 1: Register and login User A and User B', () async {
      userA = await authServiceA.register(userAName, userAEmail, userPassword);
      final loginA = await authServiceA.login(userAEmail, userPassword);
      await tokenStorageA.saveToken(loginA.accessToken);

      expect(userA.id, isNotEmpty);
      expect(loginA.accessToken, isNotEmpty);

      userB = await authServiceB.register(userBName, userBEmail, userPassword);
      final loginB = await authServiceB.login(userBEmail, userPassword);
      await tokenStorageB.saveToken(loginB.accessToken);

      expect(userB.id, isNotEmpty);
      expect(loginB.accessToken, isNotEmpty);
    });

    // 2. Load settings for User A
    test('Step 2: Load settings for User A via SettingsProvider', () async {
      await settingsProviderA.loadSettings();

      expect(settingsProviderA.isLoading, isFalse);
      expect(settingsProviderA.errorMessage, isNull);
      expect(settingsProviderA.settings, isNotNull);
    });

    // 3. Verify default settings
    test('Step 3: Verify initial default settings for User A', () async {
      final s = settingsProviderA.settings!;
      expect(s.timezone, 'UTC');
      expect(s.dateFormat, 'YYYY-MM-DD');
      expect(s.timeFormat, '24h');
      expect(s.firstDayOfWeek, 'monday');
      expect(s.theme, 'system');
      expect(s.compactMode, isFalse);
      expect(s.defaultTaskPriority, 'medium');
      expect(s.defaultTaskStatusFilter, 'all');
      expect(s.defaultTaskSort, 'due_date');
      expect(s.defaultTaskSortOrder, 'asc');
      expect(s.defaultMaxAttempts, 3);
      expect(s.defaultPageSize, 20);
      expect(s.defaultDashboardTimeRange, 'last_7_days');
      expect(s.defaultReportDateRange, 'last_7_days');
      expect(s.defaultReportType, 'task_summary');
      expect(s.defaultExportFormat, 'csv');
      expect(s.notifyTaskAssigned, isTrue);
      expect(s.notifyTaskReassigned, isTrue);
      expect(s.notifyReminderDue, isTrue);
      expect(s.notifyFollowUpDue, isTrue);
      expect(s.notifyNextActionDue, isTrue);
      expect(s.notifyTaskOverdue, isTrue);
      expect(s.notifyAttemptLimitReached, isTrue);
      expect(s.notifyTaskCompleted, isTrue);
      expect(s.notifyTaskReopened, isTrue);
    });

    // 4. Update timezone
    test('Step 4: Update timezone to Asia/Kolkata', () async {
      final ok = await settingsProviderA.updateSettings(
        const UserSettingsUpdate(timezone: 'Asia/Kolkata'),
      );
      expect(ok, isTrue);
      expect(settingsProviderA.settings!.timezone, 'Asia/Kolkata');
    });

    // 5. Update task defaults
    test('Step 5: Update default task priority, max attempts, and sort order', () async {
      final ok = await settingsProviderA.updateSettings(
        const UserSettingsUpdate(
          defaultTaskPriority: 'urgent',
          defaultMaxAttempts: 5,
          defaultTaskSort: 'created_at',
          defaultTaskSortOrder: 'desc',
          defaultPageSize: 50,
        ),
      );
      expect(ok, isTrue);
      expect(settingsProviderA.settings!.defaultTaskPriority, 'urgent');
      expect(settingsProviderA.settings!.defaultMaxAttempts, 5);
      expect(settingsProviderA.settings!.defaultTaskSort, 'created_at');
      expect(settingsProviderA.settings!.defaultTaskSortOrder, 'desc');
      expect(settingsProviderA.settings!.defaultPageSize, 50);
    });

    // 6. Update notification preferences
    test('Step 6: Update notification preferences (disable assignment & reminder alerts)', () async {
      final ok = await settingsProviderA.updateSettings(
        const UserSettingsUpdate(
          notifyTaskAssigned: false,
          notifyReminderDue: false,
        ),
      );
      expect(ok, isTrue);
      expect(settingsProviderA.settings!.notifyTaskAssigned, isFalse);
      expect(settingsProviderA.settings!.notifyReminderDue, isFalse);
      expect(settingsProviderA.settings!.notifyTaskOverdue, isTrue); // Unmodified remains true
    });

    // 7. Update dashboard preference
    test('Step 7: Update default dashboard time range', () async {
      final ok = await settingsProviderA.updateSettings(
        const UserSettingsUpdate(
          defaultDashboardTimeRange: 'last_30_days',
          compactMode: true,
          theme: 'dark',
        ),
      );
      expect(ok, isTrue);
      expect(settingsProviderA.settings!.defaultDashboardTimeRange, 'last_30_days');
      expect(settingsProviderA.settings!.compactMode, isTrue);
      expect(settingsProviderA.settings!.theme, 'dark');
      expect(settingsProviderA.themeMode.name, 'dark');
    });

    // 8. Update report preference
    test('Step 8: Update report defaults (workload, this_month, json)', () async {
      final ok = await settingsProviderA.updateSettings(
        const UserSettingsUpdate(
          defaultReportType: 'workload',
          defaultReportDateRange: 'this_month',
          defaultExportFormat: 'json',
          displayNameOverride: 'Special Agent A',
        ),
      );
      expect(ok, isTrue);
      expect(settingsProviderA.settings!.defaultReportType, 'workload');
      expect(settingsProviderA.settings!.defaultReportDateRange, 'this_month');
      expect(settingsProviderA.settings!.defaultExportFormat, 'json');
      expect(settingsProviderA.settings!.displayNameOverride, 'Special Agent A');
    });

    // 9. Reload settings from backend
    test('Step 9: Reload settings from backend into clean provider instance', () async {
      final freshProvider = SettingsProvider(settingsService: settingsServiceA);
      await freshProvider.loadSettings();

      expect(freshProvider.isLoading, isFalse);
      expect(freshProvider.settings, isNotNull);
    });

    // 10. Verify persistence
    test('Step 10: Verify all updated settings persisted in PostgreSQL', () async {
      final s = await settingsServiceA.getSettings();

      expect(s.timezone, 'Asia/Kolkata');
      expect(s.defaultTaskPriority, 'urgent');
      expect(s.defaultMaxAttempts, 5);
      expect(s.defaultTaskSort, 'created_at');
      expect(s.defaultTaskSortOrder, 'desc');
      expect(s.defaultPageSize, 50);
      expect(s.notifyTaskAssigned, isFalse);
      expect(s.notifyReminderDue, isFalse);
      expect(s.defaultDashboardTimeRange, 'last_30_days');
      expect(s.compactMode, isTrue);
      expect(s.theme, 'dark');
      expect(s.defaultReportType, 'workload');
      expect(s.defaultReportDateRange, 'this_month');
      expect(s.defaultExportFormat, 'json');
      expect(s.displayNameOverride, 'Special Agent A');
    });

    // 11. Create a task and verify explicit task values override defaults
    test('Step 11: Explicit task values override user settings defaults', () async {
      // User A default is priority='urgent', max_attempts=5.
      // Explicitly specify priority='low', max_attempts=2.
      final task = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Explicit Task Override Test $testRunId',
          priority: 'low',
          maxAttempts: 2,
          assignedUserId: userA.id,
        ),
      );

      expect(task.priority, 'low'); // Explicit user input authoritative
      expect(task.maxAttempts, 2); // Explicit user input authoritative
    });

    // 12. Open Dashboard and verify configured defaults
    test('Step 12: Verify Dashboard uses user configured default time range', () async {
      expect(settingsProviderA.defaultDashboardRange, 'last_30_days');
      expect(settingsProviderA.isCompact, isTrue);
    });

    // 13. Open Reports and verify configured defaults
    test('Step 13: Verify Reports uses user configured default report type and format', () async {
      expect(settingsProviderA.defaultReportType, 'workload');
      expect(settingsProviderA.defaultReportDateRange, 'this_month');
      expect(settingsProviderA.defaultExportFormat, 'json');
    });

    // 14. Trigger notification-related behavior and verify preferences are respected
    test('Step 14: Notification opt-out suppresses in-app notification while preserving task history', () async {
      // User A opted out of notifyTaskAssigned in Step 6
      final initialNotifications = await notificationServiceA.getNotifications(unreadOnly: false);
      final initialCount = initialNotifications.total;

      // Assign a new task to User A
      final assignedTask = await taskServiceA.createTask(
        TaskCreateRequest(
          title: 'Notification Opt-out Verification Task $testRunId',
          assignedUserId: userA.id,
        ),
      );

      // Verify no new in-app notification was dispatched to User A
      final updatedNotifications = await notificationServiceA.getNotifications(unreadOnly: false);
      expect(updatedNotifications.total, initialCount);

      // Verify immutable task history audit trail was still recorded
      final history = await taskServiceA.getTaskHistory(assignedTask.id);
      expect(history.isNotEmpty, isTrue);
      expect(history.any((h) => h.action.toLowerCase() == 'created'), isTrue);
    });

    // 15. Verify another authenticated user cannot access/update User A's settings
    test('Step 15: Cross-user isolation - User B has independent defaults and cannot mutate User A', () async {
      // Load settings for User B
      await settingsProviderB.loadSettings();
      final settingsB = settingsProviderB.settings!;

      // User B should have pristine factory defaults, unaffected by User A's customizations
      expect(settingsB.timezone, 'UTC');
      expect(settingsB.theme, 'system');
      expect(settingsB.defaultTaskPriority, 'medium');
      expect(settingsB.notifyTaskAssigned, isTrue);
      expect(settingsB.displayNameOverride, isNull);

      // User B updates their own theme to light and timezone to Europe/London
      final okB = await settingsProviderB.updateSettings(
        const UserSettingsUpdate(theme: 'light', timezone: 'Europe/London'),
      );
      expect(okB, isTrue);
      expect(settingsProviderB.settings!.theme, 'light');
      expect(settingsProviderB.settings!.timezone, 'Europe/London');

      // User A's settings remain untouched (dark theme, Asia/Kolkata timezone)
      final reloadedA = await settingsServiceA.getSettings();
      expect(reloadedA.theme, 'dark');
      expect(reloadedA.timezone, 'Asia/Kolkata');
      expect(reloadedA.displayNameOverride, 'Special Agent A');
    });

    // 16. Verify logout/login preserves settings
    test('Step 16: Logout and re-login preserves user settings intact', () async {
      // Simulate logout by clearing User A's token
      await tokenStorageA.deleteToken();

      // Re-login User A
      final reLogin = await authServiceA.login(userAEmail, userPassword);
      await tokenStorageA.saveToken(reLogin.accessToken);

      // Load settings afresh
      final finalSettings = await settingsServiceA.getSettings();
      expect(finalSettings.timezone, 'Asia/Kolkata');
      expect(finalSettings.theme, 'dark');
      expect(finalSettings.compactMode, isTrue);
      expect(finalSettings.defaultTaskPriority, 'urgent');
      expect(finalSettings.defaultMaxAttempts, 5);
      expect(finalSettings.defaultDashboardTimeRange, 'last_30_days');
      expect(finalSettings.defaultReportType, 'workload');
      expect(finalSettings.defaultReportDateRange, 'this_month');
      expect(finalSettings.defaultExportFormat, 'json');
      expect(finalSettings.displayNameOverride, 'Special Agent A');
      expect(finalSettings.notifyTaskAssigned, isFalse);
      expect(finalSettings.notifyReminderDue, isFalse);
    });
  });
}
