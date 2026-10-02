// Phase 18: Settings Screen Integration & Widget Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/models/settings/settings_models.dart';
import 'package:nextaction/providers/auth_provider.dart';
import 'package:nextaction/providers/settings_provider.dart';
import 'package:nextaction/screens/settings/settings_screen.dart';
import 'package:nextaction/services/settings/settings_service.dart';

class MockTestApiClient extends ApiClient {
  UserSettings currentSettings = UserSettings(
    id: 's-test',
    userId: 'u-test',
    displayNameOverride: 'Commander',
    timezone: 'Asia/Kolkata',
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
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers, bool requiresAuth = true}) async {
    if (path == '/settings') {
      return currentSettings.toJson();
    }
    throw UnimplementedError('GET $path');
  }

  @override
  Future<dynamic> patch(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers, bool requiresAuth = true}) async {
    if (path == '/settings') {
      final b = body as Map<String, dynamic>;
      currentSettings = currentSettings.copyWith(
        theme: b['theme'] as String?,
        timezone: b['timezone'] as String?,
        defaultTaskPriority: b['default_task_priority'] as String?,
        displayNameOverride: b['display_name_override'] as String?,
      );
      return currentSettings.toJson();
    }
    throw UnimplementedError('PATCH $path');
  }

  @override
  Future<dynamic> post(String path, {dynamic body, Map<String, dynamic>? queryParameters, Map<String, String>? headers, bool requiresAuth = true}) async {
    if (path == '/settings/reset') {
      currentSettings = UserSettings(
        id: 's-test',
        userId: 'u-test',
        timezone: 'UTC',
        theme: 'system',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      return currentSettings.toJson();
    }
    throw UnimplementedError('POST $path');
  }
}

class MockTestAuthProvider extends AuthProvider {
  final User _mockUser = User(
    id: 'u-test',
    email: 'alex@nextaction.local',
    name: 'Alex Mercer',
    isActive: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  MockTestAuthProvider() : super(authService: null);

  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  User? get currentUser => _mockUser;
}

void main() {
  group('Phase 18: SettingsScreen Widget Tests', () {
    testWidgets('renders all preference cards and profile information', (tester) async {
      final mockClient = MockTestApiClient();
      final settingsService = SettingsService(apiClient: mockClient);
      final settingsProvider = SettingsProvider(settingsService: settingsService);
      final authProvider = MockTestAuthProvider();

      await settingsProvider.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsProvider: settingsProvider,
            authProvider: authProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings & Personalization'), findsOneWidget);
      expect(find.text('Alex Mercer'), findsOneWidget);
      expect(find.text('alex@nextaction.local'), findsOneWidget);
      expect(find.text('1. Profile & Identity'), findsOneWidget);
      expect(find.text('2. Appearance & Workspace'), findsOneWidget);
      expect(find.text('3. Date, Time & Timezone'), findsOneWidget);
      expect(find.text('4. Task Experience Defaults'), findsOneWidget);
      expect(find.text('5. Dashboard & Reports Defaults'), findsOneWidget);
      expect(find.text('6. Notification Preferences'), findsOneWidget);
      expect(find.text('7. About & System Information'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('Reset Defaults'), findsOneWidget);
    });

    testWidgets('updates settings and shows success feedback when Save Changes is tapped', (tester) async {
      final mockClient = MockTestApiClient();
      final settingsService = SettingsService(apiClient: mockClient);
      final settingsProvider = SettingsProvider(settingsService: settingsService);
      final authProvider = MockTestAuthProvider();

      await settingsProvider.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsProvider: settingsProvider,
            authProvider: authProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Save Changes
      final saveBtn = find.text('Save Changes');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Settings saved successfully.'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows confirmation dialog when Reset Defaults is clicked', (tester) async {
      final mockClient = MockTestApiClient();
      final settingsService = SettingsService(apiClient: mockClient);
      final settingsProvider = SettingsProvider(settingsService: settingsService);
      final authProvider = MockTestAuthProvider();

      await settingsProvider.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsProvider: settingsProvider,
            authProvider: authProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Reset Defaults
      final resetBtn = find.text('Reset Defaults');
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(find.text('Reset to Defaults?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Reset Everything'), findsOneWidget);

      // Confirm reset
      await tester.tap(find.text('Reset Everything'));
      await tester.pumpAndSettle();

      expect(find.text('Preferences reset to factory defaults.'), findsAtLeastNWidgets(1));
    });
  });
}
