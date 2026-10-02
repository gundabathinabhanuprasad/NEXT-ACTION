// Phase 18: Settings, Personalization & System Configuration Screen.

import 'package:flutter/material.dart';
import '../../models/settings/settings_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsProvider settingsProvider;
  final AuthProvider authProvider;

  const SettingsScreen({
    super.key,
    required this.settingsProvider,
    required this.authProvider,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSaving = false;
  String? _statusMessage;
  bool _isError = false;

  // Form field state
  late TextEditingController _displayNameController;
  late String _selectedTimezone;
  late String _selectedDateFormat;
  late String _selectedTimeFormat;
  late String _selectedFirstDayOfWeek;
  late String _selectedTheme;
  late bool _compactMode;

  late String _defaultTaskPriority;
  late String _defaultTaskStatusFilter;
  late String _defaultTaskSort;
  late String _defaultTaskSortOrder;
  late int _defaultMaxAttempts;
  late int _defaultPageSize;

  late String _defaultDashboardTimeRange;
  late String _defaultReportDateRange;
  late String _defaultReportType;
  late String _defaultExportFormat;

  late bool _notifyTaskAssigned;
  late bool _notifyTaskReassigned;
  late bool _notifyReminderDue;
  late bool _notifyFollowUpDue;
  late bool _notifyNextActionDue;
  late bool _notifyTaskOverdue;
  late bool _notifyAttemptLimitReached;
  late bool _notifyTaskCompleted;
  late bool _notifyTaskReopened;

  static const List<String> _popularTimezones = [
    'UTC',
    'Asia/Kolkata',
    'Asia/Dubai',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Asia/Tokyo',
    'Asia/Singapore',
    'Australia/Sydney',
  ];

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _syncFormWithSettings();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  void _syncFormWithSettings() {
    final s = widget.settingsProvider.settings;
    _displayNameController.text = s?.displayNameOverride ?? '';
    _selectedTimezone = s?.timezone ?? 'UTC';
    if (!_popularTimezones.contains(_selectedTimezone)) {
      // If user has a custom timezone not in quick list, preserve it
      _selectedTimezone = s?.timezone ?? 'UTC';
    }
    _selectedDateFormat = s?.dateFormat ?? 'YYYY-MM-DD';
    _selectedTimeFormat = s?.timeFormat ?? '24h';
    _selectedFirstDayOfWeek = s?.firstDayOfWeek ?? 'monday';
    _selectedTheme = s?.theme ?? 'system';
    _compactMode = s?.compactMode ?? false;

    _defaultTaskPriority = s?.defaultTaskPriority ?? 'medium';
    _defaultTaskStatusFilter = s?.defaultTaskStatusFilter ?? 'all';
    _defaultTaskSort = s?.defaultTaskSort ?? 'due_date';
    _defaultTaskSortOrder = s?.defaultTaskSortOrder ?? 'asc';
    _defaultMaxAttempts = s?.defaultMaxAttempts ?? 3;
    _defaultPageSize = s?.defaultPageSize ?? 20;

    _defaultDashboardTimeRange = s?.defaultDashboardTimeRange ?? 'last_7_days';
    _defaultReportDateRange = s?.defaultReportDateRange ?? 'last_7_days';
    _defaultReportType = s?.defaultReportType ?? 'task_summary';
    _defaultExportFormat = s?.defaultExportFormat ?? 'csv';

    _notifyTaskAssigned = s?.notifyTaskAssigned ?? true;
    _notifyTaskReassigned = s?.notifyTaskReassigned ?? true;
    _notifyReminderDue = s?.notifyReminderDue ?? true;
    _notifyFollowUpDue = s?.notifyFollowUpDue ?? true;
    _notifyNextActionDue = s?.notifyNextActionDue ?? true;
    _notifyTaskOverdue = s?.notifyTaskOverdue ?? true;
    _notifyAttemptLimitReached = s?.notifyAttemptLimitReached ?? true;
    _notifyTaskCompleted = s?.notifyTaskCompleted ?? true;
    _notifyTaskReopened = s?.notifyTaskReopened ?? true;
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
      _statusMessage = null;
      _isError = false;
    });

    final update = UserSettingsUpdate(
      displayNameOverride: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
      timezone: _selectedTimezone,
      dateFormat: _selectedDateFormat,
      timeFormat: _selectedTimeFormat,
      firstDayOfWeek: _selectedFirstDayOfWeek,
      theme: _selectedTheme,
      compactMode: _compactMode,
      defaultTaskPriority: _defaultTaskPriority,
      defaultTaskStatusFilter: _defaultTaskStatusFilter,
      defaultTaskSort: _defaultTaskSort,
      defaultTaskSortOrder: _defaultTaskSortOrder,
      defaultMaxAttempts: _defaultMaxAttempts,
      defaultPageSize: _defaultPageSize,
      defaultDashboardTimeRange: _defaultDashboardTimeRange,
      defaultReportDateRange: _defaultReportDateRange,
      defaultReportType: _defaultReportType,
      defaultExportFormat: _defaultExportFormat,
      notifyTaskAssigned: _notifyTaskAssigned,
      notifyTaskReassigned: _notifyTaskReassigned,
      notifyReminderDue: _notifyReminderDue,
      notifyFollowUpDue: _notifyFollowUpDue,
      notifyNextActionDue: _notifyNextActionDue,
      notifyTaskOverdue: _notifyTaskOverdue,
      notifyAttemptLimitReached: _notifyAttemptLimitReached,
      notifyTaskCompleted: _notifyTaskCompleted,
      notifyTaskReopened: _notifyTaskReopened,
    );

    final success = await widget.settingsProvider.updateSettings(update);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (success) {
        _statusMessage = 'Settings saved successfully.';
        _isError = false;
        _syncFormWithSettings();
      } else {
        _statusMessage = widget.settingsProvider.errorMessage ?? 'Failed to save settings.';
        _isError = true;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_statusMessage ?? (success ? 'Settings updated' : 'Error updating settings')),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults?'),
        content: const Text(
          'This will revert all your preferences (theme, task defaults, notifications, date formats) to system factory defaults. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade100, foregroundColor: Colors.red.shade900),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    final success = await widget.settingsProvider.resetSettings();
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (success) {
        _syncFormWithSettings();
        _statusMessage = 'Preferences reset to factory defaults.';
        _isError = false;
      } else {
        _statusMessage = widget.settingsProvider.errorMessage ?? 'Failed to reset settings.';
        _isError = true;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_statusMessage ?? 'Reset complete'),
        backgroundColor: success ? Colors.blue.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Personalization'),
        actions: [
          IconButton(
            tooltip: 'Refresh Settings',
            icon: const Icon(Icons.refresh),
            onPressed: _isSaving
                ? null
                : () async {
                    await widget.settingsProvider.loadSettings();
                    if (mounted) {
                      setState(() => _syncFormWithSettings());
                    }
                  },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _confirmReset,
              icon: const Icon(Icons.restore),
              label: const Text('Reset Defaults'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
            ),
          ],
        ),
      ),
      body: widget.settingsProvider.isLoading && widget.settingsProvider.settings == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status / Error Banner
                      if (_statusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isError ? Colors.red.shade50 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _isError ? Colors.red.shade300 : Colors.green.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isError ? Icons.error_outline : Icons.check_circle_outline,
                                color: _isError ? Colors.red.shade800 : Colors.green.shade800,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: TextStyle(
                                    color: _isError ? Colors.red.shade900 : Colors.green.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 1. Profile Section
                      _buildSectionHeader('1. Profile & Identity', Icons.person_outline),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Text(
                                      user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user?.name ?? 'User',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          user?.email ?? '',
                                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.green.shade200),
                                          ),
                                          child: Text(
                                            'Status: ${user?.isActive == true ? 'Active' : 'Inactive'}',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              TextField(
                                controller: _displayNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Display Name Override (Optional)',
                                  hintText: 'Preferred display name for greetings and headers',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  border: OutlineInputBorder(),
                                  helperText: 'Overrides system full name on screens where configured.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Appearance Section
                      _buildSectionHeader('2. Appearance & Workspace', Icons.palette_outlined),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _selectedTheme,
                                decoration: const InputDecoration(
                                  labelText: 'Application Theme',
                                  prefixIcon: Icon(Icons.brightness_medium_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'system', child: Text('System Default (Follow OS)')),
                                  DropdownMenuItem(value: 'light', child: Text('Light Mode')),
                                  DropdownMenuItem(value: 'dark', child: Text('Dark Mode')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedTheme = val);
                                },
                              ),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Compact Layout Density'),
                                subtitle: const Text('Reduce spacing and padding across data lists and cards'),
                                value: _compactMode,
                                onChanged: (val) => setState(() => _compactMode = val),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 3. Date & Time Section
                      _buildSectionHeader('3. Date, Time & Timezone', Icons.schedule_outlined),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _popularTimezones.contains(_selectedTimezone) ? _selectedTimezone : null,
                                decoration: const InputDecoration(
                                  labelText: 'Primary Timezone (IANA)',
                                  prefixIcon: Icon(Icons.public_outlined),
                                  border: OutlineInputBorder(),
                                  helperText: 'Controls day boundaries (today/overdue) and date filters.',
                                ),
                                items: _popularTimezones
                                    .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedTimezone = val);
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _selectedDateFormat,
                                      decoration: const InputDecoration(
                                        labelText: 'Date Format',
                                        prefixIcon: Icon(Icons.calendar_today_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'YYYY-MM-DD', child: Text('YYYY-MM-DD (ISO)')),
                                        DropdownMenuItem(value: 'DD/MM/YYYY', child: Text('DD/MM/YYYY')),
                                        DropdownMenuItem(value: 'MM/DD/YYYY', child: Text('MM/DD/YYYY')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _selectedDateFormat = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _selectedTimeFormat,
                                      decoration: const InputDecoration(
                                        labelText: 'Time Format',
                                        prefixIcon: Icon(Icons.access_time_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: '24h', child: Text('24 Hours (14:30)')),
                                        DropdownMenuItem(value: '12h', child: Text('12 Hours AM/PM')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _selectedTimeFormat = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _selectedFirstDayOfWeek,
                                decoration: const InputDecoration(
                                  labelText: 'First Day of Week',
                                  prefixIcon: Icon(Icons.view_week_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'monday', child: Text('Monday')),
                                  DropdownMenuItem(value: 'sunday', child: Text('Sunday')),
                                  DropdownMenuItem(value: 'saturday', child: Text('Saturday')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedFirstDayOfWeek = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 4. Task Defaults Section
                      _buildSectionHeader('4. Task Experience Defaults', Icons.task_alt_outlined),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Defaults pre-fill task creation forms and lists. Explicit user input always overrides these defaults.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _defaultTaskPriority,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Priority',
                                        prefixIcon: Icon(Icons.flag_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'low', child: Text('Low')),
                                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                                        DropdownMenuItem(value: 'high', child: Text('High')),
                                        DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultTaskPriority = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isExpanded: true,
                                      value: _defaultMaxAttempts,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Max Attempts',
                                        prefixIcon: Icon(Icons.repeat_one_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [1, 2, 3, 4, 5, 10]
                                          .map((n) => DropdownMenuItem(value: n, child: Text('$n attempts')))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultMaxAttempts = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _defaultTaskSort,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Sort Field',
                                        prefixIcon: Icon(Icons.sort_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'due_date', child: Text('Due Date')),
                                        DropdownMenuItem(value: 'created_at', child: Text('Creation Date')),
                                        DropdownMenuItem(value: 'priority', child: Text('Priority')),
                                        DropdownMenuItem(value: 'title', child: Text('Title')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultTaskSort = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _defaultTaskSortOrder,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Sort Order',
                                        prefixIcon: Icon(Icons.swap_vert_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'asc', child: Text('Ascending (A-Z / Earliest)')),
                                        DropdownMenuItem(value: 'desc', child: Text('Descending (Z-A / Latest)')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultTaskSortOrder = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _defaultTaskStatusFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Status Filter',
                                        prefixIcon: Icon(Icons.filter_list_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                                        DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                                        DropdownMenuItem(value: 'completed', child: Text('Completed')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultTaskStatusFilter = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isExpanded: true,
                                      value: _defaultPageSize,
                                      decoration: const InputDecoration(
                                        labelText: 'Page Size',
                                        prefixIcon: Icon(Icons.format_list_numbered_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 10, child: Text('10 items')),
                                        DropdownMenuItem(value: 20, child: Text('20 items')),
                                        DropdownMenuItem(value: 50, child: Text('50 items')),
                                        DropdownMenuItem(value: 100, child: Text('100 items')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultPageSize = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 5. Dashboard & Reports Defaults
                      _buildSectionHeader('5. Dashboard & Reports Defaults', Icons.assessment_outlined),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _defaultDashboardTimeRange,
                                decoration: const InputDecoration(
                                  labelText: 'Default Dashboard Time Range',
                                  prefixIcon: Icon(Icons.date_range_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'today', child: Text('Today')),
                                  DropdownMenuItem(value: 'last_7_days', child: Text('Last 7 Days')),
                                  DropdownMenuItem(value: 'last_30_days', child: Text('Last 30 Days')),
                                  DropdownMenuItem(value: 'this_month', child: Text('This Month')),
                                  DropdownMenuItem(value: 'all_time', child: Text('All Time')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _defaultDashboardTimeRange = val);
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _defaultReportDateRange,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Report Range',
                                        prefixIcon: Icon(Icons.date_range_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'today', child: Text('Today')),
                                        DropdownMenuItem(value: 'last_7_days', child: Text('Last 7 Days')),
                                        DropdownMenuItem(value: 'last_30_days', child: Text('Last 30 Days')),
                                        DropdownMenuItem(value: 'this_month', child: Text('This Month')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultReportDateRange = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _defaultReportType,
                                      decoration: const InputDecoration(
                                        labelText: 'Default Report Type',
                                        prefixIcon: Icon(Icons.pie_chart_outline),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'task_summary', child: Text('Task Summary')),
                                        DropdownMenuItem(value: 'workload', child: Text('Workload Analysis')),
                                        DropdownMenuItem(value: 'status_distribution', child: Text('Status Distribution')),
                                        DropdownMenuItem(value: 'sla_compliance', child: Text('SLA Compliance')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _defaultReportType = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _defaultExportFormat,
                                decoration: const InputDecoration(
                                  labelText: 'Default Export Format',
                                  prefixIcon: Icon(Icons.download_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'csv', child: Text('CSV (Comma Separated)')),
                                  DropdownMenuItem(value: 'json', child: Text('JSON (Raw Data)')),
                                  DropdownMenuItem(value: 'pdf', child: Text('PDF Document')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _defaultExportFormat = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 6. Notification Preferences
                      _buildSectionHeader('6. Notification Preferences', Icons.notifications_active_outlined),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 8, bottom: 8),
                                child: Text(
                                  'Configures in-app alerts and notifications. Disabling a notification never affects immutable task audit history.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Task Assignment'),
                                subtitle: const Text('When a task is assigned to you'),
                                value: _notifyTaskAssigned,
                                onChanged: (val) => setState(() => _notifyTaskAssigned = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Task Reassignment'),
                                subtitle: const Text('When an existing task is reassigned to you'),
                                value: _notifyTaskReassigned,
                                onChanged: (val) => setState(() => _notifyTaskReassigned = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Reminder Due'),
                                subtitle: const Text('When an action reminder triggers'),
                                value: _notifyReminderDue,
                                onChanged: (val) => setState(() => _notifyReminderDue = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Follow-up Due'),
                                subtitle: const Text('When a scheduled client follow-up is due'),
                                value: _notifyFollowUpDue,
                                onChanged: (val) => setState(() => _notifyFollowUpDue = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Next Action Due'),
                                subtitle: const Text('When a scheduled next action becomes pending'),
                                value: _notifyNextActionDue,
                                onChanged: (val) => setState(() => _notifyNextActionDue = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Task Overdue Alert'),
                                subtitle: const Text('When a task passes its due date without completion'),
                                value: _notifyTaskOverdue,
                                onChanged: (val) => setState(() => _notifyTaskOverdue = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Attempt Limit Reached'),
                                subtitle: const Text('When a task reaches its maximum configured attempts'),
                                value: _notifyAttemptLimitReached,
                                onChanged: (val) => setState(() => _notifyAttemptLimitReached = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Task Completed'),
                                subtitle: const Text('When a subscribed or owned task is completed'),
                                value: _notifyTaskCompleted,
                                onChanged: (val) => setState(() => _notifyTaskCompleted = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Task Reopened'),
                                subtitle: const Text('When a completed or closed task is reopened'),
                                value: _notifyTaskReopened,
                                onChanged: (val) => setState(() => _notifyTaskReopened = val),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 7. About & System Information
                      _buildSectionHeader('7. About & System Information', Icons.info_outline),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NextAction Workspace',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              SizedBox(height: 4),
                              Text('Version: 1.0.0 (Production Release)'),
                              Text('Backend: NextAction Enterprise API (PostgreSQL + Redis)'),
                              Text('Frontend: Flutter Web & Mobile (Release)'),
                              SizedBox(height: 8),
                              Text(
                                'Preferences are securely isolated per user account and synchronized across sessions.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
