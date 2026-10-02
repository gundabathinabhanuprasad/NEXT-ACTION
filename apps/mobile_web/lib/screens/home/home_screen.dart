import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/dashboard/dashboard_models.dart';
import '../../models/follow_up/follow_up_models.dart';
import '../../models/history/task_history_models.dart';
import '../../models/notification/notification_models.dart';
import '../../models/reminder/reminder_models.dart';
import '../../models/task/task_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/client/client_service.dart';
import '../../services/dashboard/dashboard_service.dart';
import '../../services/follow_up/follow_up_service.dart';
import '../../services/notification/notification_service.dart';
import '../../services/recurring/recurring_task_service.dart';
import '../../services/reminder/reminder_service.dart';
import '../../services/report/report_service.dart';
import '../../services/task/task_service.dart';
import '../../services/template/task_template_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../activity/activity_screen.dart';
import '../clients/clients_screen.dart';
import '../follow_ups/follow_ups_screen.dart';
import '../next_actions/next_actions_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../recurring/recurring_tasks_screen.dart';
import '../reminders/reminders_screen.dart';
import '../reports/reports_screen.dart';
import '../tasks/task_create_screen.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_list_screen.dart';
import '../team/team_screen.dart';
import '../templates/task_templates_screen.dart';
import '../workflows/workflows_screen.dart';
import '../../providers/settings_provider.dart';
import '../settings/settings_screen.dart';

/// Production NextAction Dashboard, Productivity Analytics & Workload Intelligence Workspace.
class HomeScreen extends StatefulWidget {
  final AuthProvider authProvider;
  final TaskService taskService;
  final DashboardService? dashboardService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;
  final ReminderService? reminderService;
  final FollowUpService? followUpService;
  final NotificationService? notificationService;
  final TaskTemplateService? taskTemplateService;
  final RecurringTaskService? recurringTaskService;
  final ReportService? reportService;
  final SettingsProvider? settingsProvider;

  const HomeScreen({
    super.key,
    required this.authProvider,
    required this.taskService,
    this.dashboardService,
    this.clientService,
    this.workflowService,
    this.userService,
    this.reminderService,
    this.followUpService,
    this.notificationService,
    this.taskTemplateService,
    this.recurringTaskService,
    this.reportService,
    this.settingsProvider,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNavIndex = 0;

  late final DashboardService _dashboardService;
  late final ClientService _clientService;
  late final WorkflowService _workflowService;
  late final UserService _userService;
  late final ReminderService _reminderService;
  late final FollowUpService _followUpService;
  late final NotificationService _notificationService;
  late final TaskTemplateService _taskTemplateService;
  late final RecurringTaskService _recurringTaskService;
  late final ReportService _reportService;

  bool _isLoadingDashboard = false;
  String? _dashboardError;

  DashboardSummary? _dashboardSummary;
  DashboardTimeRange _selectedTimeRange = DashboardTimeRange.last7Days;

  List<Task> _tasks = [];
  List<FollowUp> _allFollowUps = [];
  List<FollowUp> _pendingFollowUps = [];
  List<Reminder> _reminders = [];
  List<TaskHistory> _recentActivities = [];
  List<AppNotification> _recentNotifications = [];
  int _unreadNotificationsCount = 0;
  int _totalClientsCount = 0;
  int _activeWorkflowsCount = 0;
  int _totalTeamCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.settingsProvider?.settings?.defaultDashboardTimeRange != null) {
      _selectedTimeRange = DashboardTimeRange.fromApiValue(
        widget.settingsProvider!.settings!.defaultDashboardTimeRange,
      );
    }
    _dashboardService = widget.dashboardService ?? DashboardService(apiClient: widget.taskService.apiClient);
    _clientService = widget.clientService ?? ClientService(apiClient: widget.taskService.apiClient);
    _workflowService = widget.workflowService ?? WorkflowService(apiClient: widget.taskService.apiClient);
    _userService = widget.userService ?? UserService(apiClient: widget.taskService.apiClient);
    _reminderService = widget.reminderService ?? ReminderService(apiClient: widget.taskService.apiClient);
    _followUpService = widget.followUpService ?? FollowUpService(apiClient: widget.taskService.apiClient);
    _notificationService = widget.notificationService ?? NotificationService(apiClient: widget.taskService.apiClient);
    _taskTemplateService = widget.taskTemplateService ?? TaskTemplateService(apiClient: widget.taskService.apiClient);
    _recurringTaskService = widget.recurringTaskService ?? RecurringTaskService(apiClient: widget.taskService.apiClient);
    _reportService = widget.reportService ?? ReportService(apiClient: widget.taskService.apiClient);
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoadingDashboard = true;
      _dashboardError = null;
    });

    try {
      // 1. Fetch server-aggregated Dashboard Summary with selected time range
      DashboardSummary? summary;
      try {
        summary = await _dashboardService.getDashboardSummary(timeRange: _selectedTimeRange.apiValue);
      } catch (_) {
        // Fallback gracefully for environments where only specific endpoints are mocked
      }

      // 2. Concurrently fetch complementary entities for list previews and organization tabs
      final results = await Future.wait([
        widget.taskService.getTasks(page: 1, pageSize: 100),
        _followUpService.getFollowUps(),
        _reminderService.getReminders(),
        widget.taskService.getRecentActivity(limit: 15),
        _clientService.getClients(pageSize: 1),
        _workflowService.getWorkflows(isActive: true, pageSize: 1),
        _userService.getUsers(isActive: true, pageSize: 1),
        _notificationService
            .getNotifications(unreadOnly: false, page: 1, pageSize: 5)
            .catchError((_) => const NotificationListResponse(items: [], total: 0, unreadCount: 0, page: 1, pageSize: 5)),
      ]);

      if (!mounted) return;

      final taskResponse = results[0] as TaskListResponse;
      final followUps = results[1] as List<FollowUp>;
      final reminders = results[2] as List<Reminder>;
      final activities = results[3] as List<TaskHistory>;
      final clientResponse = results[4] as ClientListResponse;
      final workflowResponse = results[5] as WorkflowListResponse;
      final userResponse = results[6] as UserListResponse;
      final notificationResponse = results[7] as NotificationListResponse;

      setState(() {
        _dashboardSummary = summary;
        _tasks = taskResponse.items;
        _allFollowUps = followUps;
        _pendingFollowUps = followUps.where((f) => !f.isCompleted).toList();
        _reminders = reminders;
        _recentActivities = summary?.recentActivities.isNotEmpty == true ? summary!.recentActivities : activities;
        _recentNotifications = summary?.recentNotifications.isNotEmpty == true ? summary!.recentNotifications : notificationResponse.items;
        _unreadNotificationsCount = summary?.kpis.unreadNotifications ?? notificationResponse.unreadCount;
        _totalClientsCount = clientResponse.total;
        _activeWorkflowsCount = workflowResponse.total;
        _totalTeamCount = userResponse.total;
        _isLoadingDashboard = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDashboard = false;
          _dashboardError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDashboard = false;
          _dashboardError = 'Failed to load dashboard data: $e';
        });
      }
    }
  }

  void _navigateToFilteredList({
    String? status,
    TaskSmartFilter? smartFilter,
    String? priority,
    String? assignedUserId,
    String? assigneeFilter,
    String? clientId,
    String? workflowId,
    bool? overdue,
    bool? dueToday,
    bool? upcoming,
    bool? nearMaxAttempts,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskListScreen(
          taskService: widget.taskService,
          userService: _userService,
          clientService: _clientService,
          workflowService: _workflowService,
          initialStatus: status,
          initialSmartFilter: smartFilter,
          initialPriority: priority,
          initialAssignedUserId: assignedUserId,
          currentUserId: widget.authProvider.currentUser?.id,
          initialAssigneeFilter: assigneeFilter,
          initialClientId: clientId,
          initialWorkflowId: workflowId,
          initialOverdue: overdue,
          initialDueToday: dueToday,
          initialUpcoming: upcoming,
          initialNearMaxAttempts: nearMaxAttempts,
        ),
      ),
    ).then((_) => _loadDashboardData());
  }

  void _openTaskDetail(String taskId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          taskService: widget.taskService,
          taskId: taskId,
        ),
      ),
    ).then((_) => _loadDashboardData());
  }

  void _createNewTask() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskCreateScreen(
          taskService: widget.taskService,
          settingsProvider: widget.settingsProvider,
        ),
      ),
    );

    if (created == true) {
      _loadDashboardData();
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'NextAction',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        notificationService: _notificationService,
                        taskService: widget.taskService,
                      ),
                    ),
                  ).then((_) => _loadDashboardData());
                },
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_unreadNotificationsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'User Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    authProvider: widget.authProvider,
                    userService: _userService,
                    taskService: widget.taskService,
                  ),
                ),
              ).then((_) => _loadDashboardData());
            },
          ),
          IconButton(
            tooltip: 'Refresh Dashboard',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingDashboard ? null : _loadDashboardData,
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out of NextAction?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await widget.authProvider.logout();
              }
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white,
                    child: Text(
                      user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user?.name ?? 'NextAction Workspace',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedNavIndex = 0);
                _loadDashboardData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined, color: Colors.indigo),
              title: const Text('Notification Center'),
              trailing: _unreadNotificationsCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_unreadNotificationsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationsScreen(
                      notificationService: _notificationService,
                      taskService: widget.taskService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline, color: Color(0xFF1E88E5)),
              title: const Text('Next Actions Workspace'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NextActionsScreen(
                      taskService: widget.taskService,
                      clientService: _clientService,
                      workflowService: _workflowService,
                      userService: _userService,
                      authProvider: widget.authProvider,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text('Tasks'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedNavIndex = 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.alarm_outlined, color: Colors.amber),
              title: const Text('Reminders Center'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RemindersScreen(
                      reminderService: _reminderService,
                      taskService: widget.taskService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.repeat, color: Colors.teal),
              title: const Text('Follow-ups Center'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FollowUpsScreen(
                      followUpService: _followUpService,
                      taskService: widget.taskService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.timeline, color: Colors.indigo),
              title: const Text('Activity Timeline'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActivityScreen(
                      taskService: widget.taskService,
                      userService: _userService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.assessment_outlined, color: Colors.blueAccent),
              title: const Text('Reports & Insights'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportsScreen(
                      reportService: _reportService,
                      taskService: widget.taskService,
                      clientService: _clientService,
                      workflowService: _workflowService,
                      userService: _userService,
                      settingsProvider: widget.settingsProvider,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bookmark_outline, color: Colors.deepPurple),
              title: const Text('Task Templates'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskTemplatesScreen(
                      templateService: _taskTemplateService,
                      taskService: widget.taskService,
                      clientService: _clientService,
                      workflowService: _workflowService,
                      userService: _userService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.autorenew, color: Colors.deepOrange),
              title: const Text('Recurring Tasks'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecurringTasksScreen(
                      recurringService: _recurringTaskService,
                      taskService: widget.taskService,
                      templateService: _taskTemplateService,
                      clientService: _clientService,
                      workflowService: _workflowService,
                      userService: _userService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('Clients'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedNavIndex = 2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Workflows'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedNavIndex = 3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outlined),
              title: const Text('Team'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedNavIndex = 4);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      authProvider: widget.authProvider,
                      userService: _userService,
                      taskService: widget.taskService,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                final sProvider = widget.settingsProvider ?? SettingsProvider();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      settingsProvider: sProvider,
                      authProvider: widget.authProvider,
                    ),
                  ),
                ).then((_) => _loadDashboardData());
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedNavIndex = index);
          if (index == 0) {
            _loadDashboardData();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'Workflows',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outlined),
            selectedIcon: Icon(Icons.people),
            label: 'Team',
          ),
        ],
      ),
      floatingActionButton: _selectedNavIndex == 0 || _selectedNavIndex == 1
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New Task'),
              onPressed: _createNewTask,
            )
          : null,
      body: _selectedNavIndex == 1
          ? TaskListScreen(
              taskService: widget.taskService,
              userService: _userService,
              clientService: _clientService,
              workflowService: _workflowService,
              currentUserId: user?.id,
            )
          : _selectedNavIndex == 2
              ? ClientsScreen(clientService: _clientService, taskService: widget.taskService)
              : _selectedNavIndex == 3
                  ? WorkflowsScreen(workflowService: _workflowService, taskService: widget.taskService)
                  : _selectedNavIndex == 4
                      ? TeamScreen(
                          userService: _userService,
                          taskService: widget.taskService,
                          currentUserId: user?.id,
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDashboardData,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1040),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // User Profile Header Card
                                    _buildUserHeaderCard(theme, user),
                                    const SizedBox(height: 16),

                                    // Time Range Selector Bar
                                    _buildTimeRangeSelector(theme),
                                    const SizedBox(height: 20),

                                    // Error State Banner
                                    if (_dashboardError != null) ...[
                                      _buildErrorBanner(theme, _dashboardError!),
                                      const SizedBox(height: 20),
                                    ],

                                    // Loading Skeleton / Spinner Indicator
                                    if (_isLoadingDashboard && _tasks.isEmpty && _dashboardSummary == null) ...[
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 40),
                                        child: Center(
                                          child: Column(
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(height: 16),
                                              Text('Loading workspace intelligence...'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      // 1. Core KPIs Overview (Server-aggregated)
                                      _buildOverviewCardsSection(theme),
                                      const SizedBox(height: 24),

                                      // 2. Attention & Urgent Operational Summary
                                      _buildAttentionSummaryBanner(theme),
                                      const SizedBox(height: 24),

                                      // 3. Productivity & Activity Trends
                                      _buildTrendsSection(theme),
                                      const SizedBox(height: 24),

                                      // 4. Workload Breakdown (Assignee, Client, Workflow)
                                      _buildWorkloadBreakdownSection(theme),
                                      const SizedBox(height: 24),

                                      // 5. Attempt Pressure Analytics
                                      _buildAttemptPressureSection(theme),
                                      const SizedBox(height: 24),

                                      // 6. Action Scheduling & Follow-up Center
                                      _buildActionSchedulingSection(theme),
                                      const SizedBox(height: 24),

                                      // 7. Organization Workspace Cards
                                      _buildOrganizationWorkspaceSection(theme),
                                      const SizedBox(height: 24),

                                      // 8. Task Status & Priority Distribution
                                      _buildDistributionSummarySection(theme),
                                      const SizedBox(height: 24),

                                      // 9. Tasks Due Today Section
                                      _buildDueTodaySection(theme),
                                      const SizedBox(height: 24),

                                      // 10. Overdue Tasks Section
                                      _buildOverdueSection(theme),
                                      const SizedBox(height: 24),

                                      // 11. Upcoming Tasks Section
                                      _buildUpcomingSection(theme),
                                      const SizedBox(height: 24),

                                      // 12. Needs Attention Section
                                      _buildNeedsAttentionSection(theme),
                                      const SizedBox(height: 24),

                                      // 13. Notifications & Smart Alerts
                                      _buildNotificationsAlertsSection(theme),
                                      const SizedBox(height: 24),

                                      // 14. Pending Follow-ups Section
                                      _buildPendingFollowUpsSection(theme),
                                      const SizedBox(height: 24),

                                      // 15. Recent Activity Audit Timeline
                                      _buildRecentActivitySection(theme),
                                      const SizedBox(height: 40),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
    );
  }

  // =========================================================================
  // Time Range Selector Bar
  // =========================================================================
  Widget _buildTimeRangeSelector(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.date_range, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Time Range:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: DashboardTimeRange.values.map((range) {
                    final isSelected = _selectedTimeRange == range;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(range.label),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                        ),
                        selected: isSelected,
                        selectedColor: theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.surface,
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) {
                          if (selected && _selectedTimeRange != range) {
                            setState(() => _selectedTimeRange = range);
                            _loadDashboardData();
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // User Header Card
  // =========================================================================
  Widget _buildUserHeaderCard(ThemeData theme, dynamic user) {
    final overrideName = widget.settingsProvider?.settings?.displayNameOverride;
    final userName = (overrideName != null && overrideName.trim().isNotEmpty)
        ? overrideName.trim()
        : (user != null && user.name != null && user.name.isNotEmpty
            ? user.name as String
            : 'Team Member');
    final userEmail = user?.email as String? ?? 'user@nextaction.local';

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                authProvider: widget.authProvider,
                userService: _userService,
                taskService: widget.taskService,
              ),
            ),
          ).then((_) => _loadDashboardData());
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getGreeting()}, $userName',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      userEmail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'JWT AUTHENTICATED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'View Profile →',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Error Banner
  // =========================================================================
  Widget _buildErrorBanner(ThemeData theme, String errorMessage) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error loading dashboard',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    errorMessage,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              onPressed: _loadDashboardData,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 1. Overview KPI Cards (Overdue, Due Today, Upcoming, Near Max, Total Open, Completed, Follow-ups, Reminders)
  // =========================================================================
  Widget _buildOverviewCardsSection(ThemeData theme) {
    final kpis = _dashboardSummary?.kpis;

    final openCount = kpis?.totalOpenTasks ?? _tasks.where((t) => !t.isCompleted && !t.isCancelled).length;
    final overdueCount = kpis?.overdueTasks ?? _tasks.where((t) => t.isOverdue).length;
    final dueTodayCount = kpis?.dueTodayTasks ?? _tasks.where((t) => t.isDueToday).length;
    final upcomingCount = kpis?.upcomingTasks ??
        _tasks
            .where((t) =>
                t.dueDate != null &&
                !t.isOverdue &&
                !t.isDueToday &&
                !t.isCompleted &&
                !t.isCancelled)
            .length;
    final completedInRange = kpis?.completedInRange ?? _tasks.where((t) => t.isCompleted).length;
    final nearMaxCount = kpis?.nearMaxAttempts ??
        _tasks
            .where((t) => (t.hasReachedMaxAttempts || t.isApproachingMaxAttempts) && !t.isCompleted && !t.isCancelled)
            .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              "Today's Overview",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Aggregated Overview (${_selectedTimeRange.label})',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Overdue',
                    count: overdueCount,
                    icon: Icons.warning_amber_rounded,
                    color: Colors.red.shade700,
                    backgroundColor: Colors.red.shade50,
                    onTap: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.overdue, overdue: true),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Due Today',
                    count: dueTodayCount,
                    icon: Icons.today,
                    color: Colors.orange.shade800,
                    backgroundColor: Colors.orange.shade50,
                    onTap: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.dueToday, dueToday: true),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Upcoming',
                    count: upcomingCount,
                    icon: Icons.calendar_month,
                    color: Colors.blue.shade700,
                    backgroundColor: Colors.blue.shade50,
                    onTap: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.upcoming, upcoming: true),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Near Max Attempts',
                    count: nearMaxCount,
                    icon: Icons.priority_high,
                    color: Colors.purple.shade700,
                    backgroundColor: Colors.purple.shade50,
                    onTap: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.needsAction, nearMaxAttempts: true),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Total Open Tasks',
                    count: openCount,
                    icon: Icons.pending_actions,
                    color: Colors.indigo.shade700,
                    backgroundColor: Colors.indigo.shade50,
                    onTap: () => _navigateToFilteredList(status: 'pending'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Completed (${_selectedTimeRange.label})',
                    count: completedInRange,
                    icon: Icons.check_circle_outline,
                    color: Colors.green.shade700,
                    backgroundColor: Colors.green.shade50,
                    onTap: () => _navigateToFilteredList(status: 'completed'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required ThemeData theme,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.3), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 22),
                  const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 2. Attention & Urgent Operational Summary Banner
  // =========================================================================
  Widget _buildAttentionSummaryBanner(ThemeData theme) {
    final attention = _dashboardSummary?.attention;
    final urgentCount = attention?.urgentCount ??
        (_tasks.where((t) => t.isOverdue || t.hasReachedMaxAttempts).length +
            _allFollowUps.where((f) => !f.isCompleted && f.scheduledAt.isBefore(DateTime.now())).length);
    final todayCount = attention?.todayCount ??
        (_tasks.where((t) => t.isDueToday).length +
            _reminders.where((r) => !r.isSent).length);

    return Card(
      elevation: 0,
      color: urgentCount > 0 ? Colors.red.shade50 : Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: urgentCount > 0 ? Colors.red.shade200 : Colors.blue.shade200,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 450;
            final content = Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: urgentCount > 0 ? Colors.red.shade100 : Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    urgentCount > 0 ? Icons.error_outline : Icons.check_circle_outline,
                    color: urgentCount > 0 ? Colors.red.shade800 : Colors.blue.shade800,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        urgentCount > 0 ? 'Urgent Attention Needed' : 'Operational Workspace Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: urgentCount > 0 ? Colors.red.shade900 : Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        urgentCount > 0
                            ? '$urgentCount urgent item(s) (overdue tasks, max attempts, overdue follow-ups) & $todayCount scheduled today'
                            : 'All deadlines are on schedule. $todayCount task(s) and reminder(s) scheduled for today.',
                        style: TextStyle(
                          fontSize: 11,
                          color: urgentCount > 0 ? Colors.red.shade800 : Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (isNarrow || urgentCount == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  if (urgentCount > 0) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.overdue, overdue: true),
                        child: const Text('Review Urgent', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.overdue, overdue: true),
                  child: const Text('Review Urgent', style: TextStyle(fontSize: 12)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // =========================================================================
  // 3. Productivity & Activity Trends (Created vs Completed per Day)
  // =========================================================================
  Widget _buildTrendsSection(ThemeData theme) {
    final trends = _dashboardSummary?.trends ?? [];

    return SectionCard(
      title: 'Productivity & Activity Trends',
      subtitle: 'Daily task creation vs completion history over ${_selectedTimeRange.label}',
      icon: Icons.trending_up,
      iconColor: Colors.teal.shade700,
      child: trends.isEmpty
          ? _buildEmptyState(
              icon: Icons.show_chart,
              message: 'No trend activity recorded for the selected period.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chart Legend
                Row(
                  children: [
                    _buildLegendItem('Created', Colors.blue.shade600),
                    const SizedBox(width: 16),
                    _buildLegendItem('Completed', Colors.green.shade600),
                    const SizedBox(width: 16),
                    _buildLegendItem('Overdue', Colors.red.shade600),
                  ],
                ),
                const SizedBox(height: 16),
                // Daily Bars visualization
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: trends.map((point) {
                      final maxVal = trends.fold<int>(1, (max, p) {
                        final localMax = [p.createdCount, p.completedCount, p.overdueCount].reduce((a, b) => a > b ? a : b);
                        return localMax > max ? localMax : max;
                      });

                      final createdHeight = ((point.createdCount / maxVal) * 80).clamp(4.0, 80.0);
                      final completedHeight = ((point.completedCount / maxVal) * 80).clamp(4.0, 80.0);
                      final overdueHeight = ((point.overdueCount / maxVal) * 80).clamp(4.0, 80.0);

                      final dateLabel = point.date.length >= 10 ? point.date.substring(5) : point.date;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Heights indicator
                            SizedBox(
                              height: 90,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Created bar
                                  Tooltip(
                                    message: '${point.date}: ${point.createdCount} created',
                                    child: Container(
                                      width: 10,
                                      height: point.createdCount > 0 ? createdHeight : 3,
                                      decoration: BoxDecoration(
                                        color: point.createdCount > 0 ? Colors.blue.shade600 : Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  // Completed bar
                                  Tooltip(
                                    message: '${point.date}: ${point.completedCount} completed',
                                    child: Container(
                                      width: 10,
                                      height: point.completedCount > 0 ? completedHeight : 3,
                                      decoration: BoxDecoration(
                                        color: point.completedCount > 0 ? Colors.green.shade600 : Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  // Overdue bar
                                  Tooltip(
                                    message: '${point.date}: ${point.overdueCount} overdue',
                                    child: Container(
                                      width: 10,
                                      height: point.overdueCount > 0 ? overdueHeight : 3,
                                      decoration: BoxDecoration(
                                        color: point.overdueCount > 0 ? Colors.red.shade600 : Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dateLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // =========================================================================
  // 4. Workload Breakdown (Assignees, Clients, Workflows)
  // =========================================================================
  Widget _buildWorkloadBreakdownSection(ThemeData theme) {
    final workload = _dashboardSummary?.workload;
    final assignees = workload?.byAssignee ?? [];
    final clients = workload?.byClient ?? [];
    final workflows = workload?.byWorkflow ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        final assigneeCard = SectionCard(
          title: 'Assignee Workload',
          subtitle: 'Operational task loads across team members',
          icon: Icons.badge_outlined,
          iconColor: Colors.indigo,
          child: assignees.isEmpty
              ? _buildEmptyState(icon: Icons.person_outline, message: 'No assignee workload data.')
              : Column(
                  children: assignees.take(6).map((item) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          item.userName.isNotEmpty ? item.userName[0].toUpperCase() : 'U',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                        ),
                      ),
                      title: Text(item.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        'Open: ${item.openTasks} • Due Today: ${item.dueToday} • Overdue: ${item.overdue} • Done: ${item.completed}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 16),
                      onTap: () {
                        if (item.userId != null) {
                          _navigateToFilteredList(assignedUserId: item.userId);
                        } else {
                          _navigateToFilteredList(assigneeFilter: 'unassigned');
                        }
                      },
                    );
                  }).toList(),
                ),
        );

        final clientCard = SectionCard(
          title: 'Client Workload',
          subtitle: 'Tasks distributed across clients',
          icon: Icons.business,
          iconColor: Colors.blue.shade700,
          child: clients.isEmpty
              ? _buildEmptyState(icon: Icons.business_outlined, message: 'No client workload data.')
              : Column(
                  children: clients.take(6).map((item) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.blue.shade50,
                        child: Icon(Icons.business, size: 14, color: Colors.blue.shade700),
                      ),
                      title: Text(item.clientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        'Open: ${item.openTasks} • Due Today: ${item.dueToday} • Overdue: ${item.overdue}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 16),
                      onTap: () {
                        _navigateToFilteredList(clientId: item.clientId);
                      },
                    );
                  }).toList(),
                ),
        );

        final workflowCard = SectionCard(
          title: 'Workflow Workload',
          subtitle: 'Tasks distributed across active workflows',
          icon: Icons.account_tree,
          iconColor: Colors.teal.shade700,
          child: workflows.isEmpty
              ? _buildEmptyState(icon: Icons.account_tree_outlined, message: 'No workflow workload data.')
              : Column(
                  children: workflows.take(6).map((item) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.account_tree, size: 14, color: Colors.teal.shade700),
                      ),
                      title: Text(item.workflowName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        'Open: ${item.openTasks} • Due Today: ${item.dueToday} • Overdue: ${item.overdue}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 16),
                      onTap: () {
                        _navigateToFilteredList(workflowId: item.workflowId);
                      },
                    );
                  }).toList(),
                ),
        );

        if (isWide) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: assigneeCard),
                  const SizedBox(width: 16),
                  Expanded(child: clientCard),
                ],
              ),
              const SizedBox(height: 16),
              workflowCard,
            ],
          );
        }

        return Column(
          children: [
            assigneeCard,
            const SizedBox(height: 16),
            clientCard,
            const SizedBox(height: 16),
            workflowCard,
          ],
        );
      },
    );
  }

  // =========================================================================
  // 5. Attempt Pressure Analytics
  // =========================================================================
  Widget _buildAttemptPressureSection(ThemeData theme) {
    final pressure = _dashboardSummary?.attemptPressure;
    final zeroAttempts = pressure?.zeroAttempts ?? _tasks.where((t) => t.attemptCount == 0 && !t.isCompleted).length;
    final oneAttempt = pressure?.oneAttempt ?? _tasks.where((t) => t.attemptCount == 1 && !t.isCompleted).length;
    final nearMax = pressure?.nearMax ?? _tasks.where((t) => t.isApproachingMaxAttempts && !t.isCompleted).length;
    final maxReached = pressure?.maxReached ?? _tasks.where((t) => t.hasReachedMaxAttempts && !t.isCompleted).length;

    return SectionCard(
      title: 'Attempt Pressure & Blockage Analytics',
      subtitle: 'Distribution of execution attempts on active tasks',
      icon: Icons.speed,
      iconColor: Colors.deepPurple,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildPressureChip('0 Attempts (Untouched)', zeroAttempts, Colors.blue.shade700,
              () => _navigateToFilteredList()),
          _buildPressureChip('1 Attempt (In Motion)', oneAttempt, Colors.teal.shade700,
              () => _navigateToFilteredList()),
          _buildPressureChip('Approaching Limit', nearMax, Colors.orange.shade800,
              () => _navigateToFilteredList(smartFilter: TaskSmartFilter.needsAction, nearMaxAttempts: true)),
          _buildPressureChip('Max Limit Reached', maxReached, Colors.purple.shade700,
              () => _navigateToFilteredList(smartFilter: TaskSmartFilter.needsAction, nearMaxAttempts: true)),
        ],
      ),
    );
  }

  Widget _buildPressureChip(String label, int count, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
            Text(
              '$count',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 6. Action Scheduling & Follow-up Center (Next Actions, Follow-ups, Reminders)
  // =========================================================================
  Widget _buildActionSchedulingSection(ThemeData theme) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final sched = _dashboardSummary?.scheduling;

    final nextActionsToday = _tasks
        .where((t) =>
            t.nextActionDate != null &&
            t.nextActionDate!.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
            t.nextActionDate!.isBefore(todayEnd) &&
            !t.isCompleted)
        .length;

    final overdueFollowUps = sched?.followUps.overdue ??
        _allFollowUps.where((f) => !f.isCompleted && f.scheduledAt.isBefore(todayStart)).length;

    final todayReminders = sched?.reminders.dueToday ??
        _reminders
            .where((r) =>
                !r.isSent &&
                r.remindAt.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
                r.remindAt.isBefore(todayEnd))
            .length;

    final upcomingFollowUps = sched?.followUps.upcoming ??
        _allFollowUps.where((f) => !f.isCompleted && f.scheduledAt.isAfter(todayEnd)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Action Scheduling Hub',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.play_circle_fill, size: 14, color: Color(0xFF1E88E5)),
                  label: const Text('Next Actions', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NextActionsScreen(
                          taskService: widget.taskService,
                          clientService: _clientService,
                          workflowService: _workflowService,
                          userService: _userService,
                          authProvider: widget.authProvider,
                        ),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.alarm, size: 14, color: Colors.amber),
                  label: const Text('Reminders', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RemindersScreen(
                          reminderService: _reminderService,
                          taskService: widget.taskService,
                        ),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.repeat, size: 14, color: Colors.teal),
                  label: const Text('Follow-ups', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FollowUpsScreen(
                          followUpService: _followUpService,
                          taskService: widget.taskService,
                        ),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.bookmark_outline, size: 14, color: Colors.deepPurple),
                  label: const Text('Templates', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskTemplatesScreen(
                          templateService: _taskTemplateService,
                          taskService: widget.taskService,
                          clientService: _clientService,
                          workflowService: _workflowService,
                          userService: _userService,
                        ),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.autorenew, size: 14, color: Colors.deepOrange),
                  label: const Text('Recurring', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecurringTasksScreen(
                          recurringService: _recurringTaskService,
                          taskService: widget.taskService,
                          templateService: _taskTemplateService,
                          clientService: _clientService,
                          workflowService: _workflowService,
                          userService: _userService,
                        ),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Next Actions Today',
                    count: nextActionsToday,
                    icon: Icons.play_circle_outline,
                    color: const Color(0xFF1565C0),
                    backgroundColor: const Color(0xFFE3F2FD),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NextActionsScreen(
                            taskService: widget.taskService,
                            clientService: _clientService,
                            workflowService: _workflowService,
                            userService: _userService,
                            authProvider: widget.authProvider,
                          ),
                        ),
                      ).then((_) => _loadDashboardData());
                    },
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Overdue Follow-ups',
                    count: overdueFollowUps,
                    icon: Icons.warning_amber_rounded,
                    color: Colors.red.shade800,
                    backgroundColor: Colors.red.shade50,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FollowUpsScreen(
                            followUpService: _followUpService,
                            taskService: widget.taskService,
                          ),
                        ),
                      ).then((_) => _loadDashboardData());
                    },
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: "Today's Reminders",
                    count: todayReminders,
                    icon: Icons.alarm,
                    color: Colors.amber.shade900,
                    backgroundColor: Colors.amber.shade50,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RemindersScreen(
                            reminderService: _reminderService,
                            taskService: widget.taskService,
                          ),
                        ),
                      ).then((_) => _loadDashboardData());
                    },
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildKpiCard(
                    theme: theme,
                    title: 'Upcoming Follow-ups',
                    count: upcomingFollowUps,
                    icon: Icons.repeat_one,
                    color: Colors.teal.shade800,
                    backgroundColor: Colors.teal.shade50,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FollowUpsScreen(
                            followUpService: _followUpService,
                            taskService: widget.taskService,
                          ),
                        ),
                      ).then((_) => _loadDashboardData());
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // =========================================================================
  // 7. Organization Workspace Cards (Active Clients, Workflows, My Tasks, Team)
  // =========================================================================
  Widget _buildOrganizationWorkspaceSection(ThemeData theme) {
    final currentUserId = widget.authProvider.currentUser?.id;
    final myTasksCount = currentUserId != null
        ? _tasks.where((t) => t.assignedUserId == currentUserId && !t.isCompleted).length
        : 0;
    final unassignedCount = _tasks.where((t) => t.assignedUserId == null && !t.isCompleted).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        final myTasksCard = Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _navigateToFilteredList(assignedUserId: currentUserId),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.assignment_ind, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Tasks',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$myTasksCount Assigned to You',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );

        final unassignedCard = Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _navigateToFilteredList(assigneeFilter: 'unassigned'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.amber.shade50,
                    foregroundColor: Colors.amber.shade900,
                    child: const Icon(Icons.person_off_outlined, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unassigned Tasks',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$unassignedCount Awaiting Assignment',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );

        final clientsCard = Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selectedNavIndex = 2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.business, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Clients',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_totalClientsCount Clients',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );

        final workflowsCard = Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selectedNavIndex = 3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.teal.shade50,
                    foregroundColor: Colors.teal.shade800,
                    child: const Icon(Icons.account_tree, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Workflows',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_activeWorkflowsCount Active Pipelines',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );

        final teamCard = Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selectedNavIndex = 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.indigo.shade50,
                    foregroundColor: Colors.indigo.shade800,
                    child: const Icon(Icons.people, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team Members',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_totalTeamCount Active Members',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );

        if (isWide) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: myTasksCard),
                  const SizedBox(width: 16),
                  Expanded(child: unassignedCard),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: clientsCard),
                  const SizedBox(width: 16),
                  Expanded(child: workflowsCard),
                  const SizedBox(width: 16),
                  Expanded(child: teamCard),
                ],
              ),
            ],
          );
        }

        return Column(
          children: [
            myTasksCard,
            const SizedBox(height: 12),
            unassignedCard,
            const SizedBox(height: 12),
            clientsCard,
            const SizedBox(height: 12),
            workflowsCard,
            const SizedBox(height: 12),
            teamCard,
          ],
        );
      },
    );
  }

  // =========================================================================
  // 8. Task Status & Priority Distribution Summary
  // =========================================================================
  Widget _buildDistributionSummarySection(ThemeData theme) {
    final statusDist = _dashboardSummary?.statusDistribution;
    final pendingCount = statusDist?.pending ?? _tasks.where((t) => t.status == 'pending').length;
    final inProgressCount = statusDist?.inProgress ?? _tasks.where((t) => t.status == 'in_progress').length;
    final completedCount = statusDist?.completed ?? _tasks.where((t) => t.status == 'completed').length;
    final cancelledCount = statusDist?.cancelled ?? _tasks.where((t) => t.status == 'cancelled').length;

    final prioDist = _dashboardSummary?.priorityDistribution;
    final urgentCount = prioDist?.urgent ?? _tasks.where((t) => t.priority == 'urgent' && !t.isCompleted).length;
    final highCount = prioDist?.high ?? _tasks.where((t) => t.priority == 'high' && !t.isCompleted).length;
    final mediumCount = prioDist?.medium ?? _tasks.where((t) => t.priority == 'medium' && !t.isCompleted).length;
    final lowCount = prioDist?.low ?? _tasks.where((t) => t.priority == 'low' && !t.isCompleted).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        final statusWidget = SectionCard(
          title: 'Task Status Overview',
          subtitle: 'Real-time task state distribution',
          icon: Icons.donut_large,
          iconColor: theme.colorScheme.primary,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDistributionChip('Pending', pendingCount, Colors.amber.shade700,
                  () => _navigateToFilteredList(status: 'pending')),
              _buildDistributionChip('In Progress', inProgressCount, Colors.blue.shade700,
                  () => _navigateToFilteredList(status: 'in_progress')),
              _buildDistributionChip('Completed', completedCount, Colors.green.shade700,
                  () => _navigateToFilteredList(status: 'completed')),
              _buildDistributionChip('Cancelled', cancelledCount, Colors.grey.shade600,
                  () => _navigateToFilteredList(status: 'cancelled')),
            ],
          ),
        );

        final priorityWidget = SectionCard(
          title: 'Priority Overview (Active)',
          subtitle: 'Active workload breakdown by urgency',
          icon: Icons.flag,
          iconColor: Colors.deepOrange,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDistributionChip('Urgent', urgentCount, Colors.red.shade700,
                  () => _navigateToFilteredList(priority: 'urgent')),
              _buildDistributionChip('High', highCount, Colors.orange.shade800,
                  () => _navigateToFilteredList(priority: 'high')),
              _buildDistributionChip('Medium', mediumCount, Colors.blue.shade700,
                  () => _navigateToFilteredList(priority: 'medium')),
              _buildDistributionChip('Low', lowCount, Colors.teal.shade700,
                  () => _navigateToFilteredList(priority: 'low')),
            ],
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: statusWidget),
              const SizedBox(width: 16),
              Expanded(child: priorityWidget),
            ],
          );
        }

        return Column(
          children: [
            statusWidget,
            const SizedBox(height: 16),
            priorityWidget,
          ],
        );
      },
    );
  }

  Widget _buildDistributionChip(
    String label,
    int count,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 9. Today's Tasks
  // =========================================================================
  Widget _buildDueTodaySection(ThemeData theme) {
    final dueTodayTasks = _tasks.where((t) => t.isDueToday).toList();

    return SectionCard(
      title: "Today's Tasks",
      subtitle: '${dueTodayTasks.length} task(s) scheduled for today',
      icon: Icons.today,
      iconColor: Colors.orange.shade800,
      trailing: dueTodayTasks.isNotEmpty
          ? TextButton(
              onPressed: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.dueToday, dueToday: true),
              child: const Text('View all'),
            )
          : null,
      child: dueTodayTasks.isEmpty
          ? _buildEmptyState(
              icon: Icons.check_circle_outline,
              message: "No tasks due today. You're on track!",
            )
          : Column(
              children: dueTodayTasks.map((task) => _buildDashboardTaskTile(theme, task)).toList(),
            ),
    );
  }

  // =========================================================================
  // 10. Overdue Tasks
  // =========================================================================
  Widget _buildOverdueSection(ThemeData theme) {
    final overdueTasks = _tasks.where((t) => t.isOverdue).toList();

    return SectionCard(
      title: 'Overdue Tasks',
      subtitle: '${overdueTasks.length} task(s) past scheduled due date',
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.red.shade700,
      trailing: overdueTasks.isNotEmpty
          ? TextButton(
              onPressed: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.overdue, overdue: true),
              child: const Text('View all overdue'),
            )
          : null,
      child: overdueTasks.isEmpty
          ? _buildEmptyState(
              icon: Icons.sentiment_satisfied_alt,
              message: 'No overdue tasks. Great work!',
            )
          : Column(
              children: overdueTasks.take(5).map((task) => _buildDashboardTaskTile(theme, task)).toList(),
            ),
    );
  }

  // =========================================================================
  // 11. Upcoming Tasks
  // =========================================================================
  Widget _buildUpcomingSection(ThemeData theme) {
    final upcomingTasks = _tasks
        .where((t) =>
            t.dueDate != null &&
            !t.isOverdue &&
            !t.isDueToday &&
            !t.isCompleted &&
            !t.isCancelled)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    return SectionCard(
      title: 'Upcoming Tasks',
      subtitle: '${upcomingTasks.length} task(s) scheduled soon',
      icon: Icons.upcoming,
      iconColor: Colors.blue.shade700,
      trailing: upcomingTasks.isNotEmpty
          ? TextButton(
              onPressed: () => _navigateToFilteredList(smartFilter: TaskSmartFilter.upcoming, upcoming: true),
              child: const Text('View all upcoming'),
            )
          : null,
      child: upcomingTasks.isEmpty
          ? _buildEmptyState(
              icon: Icons.calendar_today_outlined,
              message: 'No upcoming tasks scheduled in the near future.',
            )
          : Column(
              children: upcomingTasks.take(5).map((task) => _buildDashboardTaskTile(theme, task)).toList(),
            ),
    );
  }

  // =========================================================================
  // 12. Needs Attention (Near Max Attempts / Blocked)
  // =========================================================================
  Widget _buildNeedsAttentionSection(ThemeData theme) {
    final attentionTasks = _tasks
        .where((t) =>
            (t.hasReachedMaxAttempts || t.isApproachingMaxAttempts || t.status == 'blocked') &&
            !t.isOverdue &&
            !t.isDueToday &&
            !t.isCompleted &&
            !t.isCancelled)
        .toList();

    return SectionCard(
      title: 'Needs Attention',
      subtitle: 'Tasks at max attempts, approaching limit, or blocked',
      icon: Icons.priority_high,
      iconColor: Colors.purple.shade700,
      child: attentionTasks.isEmpty
          ? _buildEmptyState(
              icon: Icons.thumb_up_outlined,
              message: 'No tasks currently require urgent intervention.',
            )
          : Column(
              children: attentionTasks.map((task) => _buildDashboardTaskTile(theme, task, highlightAttention: true)).toList(),
            ),
    );
  }

  // =========================================================================
  // 13. Pending Follow-ups
  // =========================================================================
  Widget _buildPendingFollowUpsSection(ThemeData theme) {
    return SectionCard(
      title: 'Pending Follow-ups',
      subtitle: '${_pendingFollowUps.length} follow-up action(s) scheduled',
      icon: Icons.repeat,
      iconColor: Colors.teal.shade700,
      child: _pendingFollowUps.isEmpty
          ? _buildEmptyState(
              icon: Icons.event_available,
              message: 'No pending follow-ups requiring attention.',
            )
          : Column(
              children: _pendingFollowUps.map((followUp) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: Colors.teal.shade50.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.teal.shade200),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.shade100,
                      child: Icon(Icons.repeat, color: Colors.teal.shade800, size: 20),
                    ),
                    title: Text(
                      followUp.notes != null && followUp.notes!.isNotEmpty
                          ? followUp.notes!
                          : 'Scheduled Follow-up Action',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          'Scheduled: ${AppDateFormat.formatDate(followUp.scheduledAt)}',
                          style: TextStyle(fontSize: 11, color: Colors.teal.shade900),
                        ),
                        Text(
                          'Task ID: ${followUp.taskId}',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _openTaskDetail(followUp.taskId),
                  ),
                );
              }).toList(),
            ),
    );
  }

  // =========================================================================
  // 14. Notifications & Smart Attention Alert Panel
  // =========================================================================
  Widget _buildNotificationsAlertsSection(ThemeData theme) {
    return SectionCard(
      title: 'Attention & Recent Alerts',
      subtitle: _unreadNotificationsCount > 0
          ? '$_unreadNotificationsCount unread notification(s) requiring your attention'
          : 'All alerts and notifications are up to date',
      icon: Icons.notifications_active_outlined,
      iconColor: Colors.indigo,
      trailing: TextButton.icon(
        icon: const Icon(Icons.arrow_forward, size: 14),
        label: const Text('View all'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationsScreen(
                notificationService: _notificationService,
                taskService: widget.taskService,
              ),
            ),
          ).then((_) => _loadDashboardData());
        },
      ),
      child: _recentNotifications.isEmpty
          ? _buildEmptyState(
              icon: Icons.notifications_none,
              message: 'No notifications or alerts. You are completely caught up!',
            )
          : Column(
              children: _recentNotifications.take(4).map((notif) {
                final isUnread = !notif.isRead;
                final meta = _getNotificationMeta(notif.type);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: isUnread ? meta.color.withOpacity(0.06) : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isUnread ? meta.color.withOpacity(0.35) : theme.colorScheme.outlineVariant,
                      width: isUnread ? 1.2 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: meta.color.withOpacity(0.12),
                      child: Icon(meta.icon, color: meta.color, size: 18),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                              color: isUnread ? meta.color.shade800 : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: meta.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          notif.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: meta.color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                meta.label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: meta.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppDateFormat.formatRelativeDate(notif.createdAt),
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () async {
                      if (!notif.isRead) {
                        try {
                          await _notificationService.markAsRead(notif.id);
                        } catch (_) {}
                      }
                      if (notif.taskId != null && mounted) {
                        _openTaskDetail(notif.taskId!);
                      } else if (mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationsScreen(
                              notificationService: _notificationService,
                              taskService: widget.taskService,
                            ),
                          ),
                        ).then((_) => _loadDashboardData());
                      }
                    },
                  ),
                );
              }).toList(),
            ),
    );
  }

  // =========================================================================
  // 15. Recent Activity Audit Timeline
  // =========================================================================
  Widget _buildRecentActivitySection(ThemeData theme) {
    return SectionCard(
      title: 'Recent Activity',
      subtitle: 'Real-time audit history across all tasks',
      icon: Icons.history,
      iconColor: Colors.blueGrey,
      trailing: TextButton.icon(
        icon: const Icon(Icons.arrow_forward, size: 14),
        label: const Text('View all'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ActivityScreen(
                taskService: widget.taskService,
                userService: _userService,
              ),
            ),
          ).then((_) => _loadDashboardData());
        },
      ),
      child: _recentActivities.isEmpty
          ? _buildEmptyState(
              icon: Icons.history_toggle_off,
              message: 'No activity recorded yet in the audit log.',
            )
          : Column(
              children: _recentActivities.take(10).map((activity) {
                final categoryColor = activity.categoryColor;
                final categoryIcon = activity.categoryIcon;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: categoryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(categoryIcon, color: categoryColor, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    activity.formattedAction,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                Text(
                                  AppDateFormat.formatRelativeDate(activity.createdAt),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                            if (activity.taskTitle != null && activity.taskTitle!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Task: ${activity.taskTitle}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              'By ${activity.displayActor} • ${AppDateFormat.formatDate(activity.createdAt)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                              ),
                            ),
                            if (activity.reason != null && activity.reason!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Reason: ${activity.reason}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (activity.taskId != null)
                        IconButton(
                          icon: const Icon(Icons.arrow_outward, size: 16),
                          tooltip: 'Open Task',
                          onPressed: () => _openTaskDetail(activity.taskId!),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  // =========================================================================
  // Task Tile & Helpers
  // =========================================================================
  Widget _buildDashboardTaskTile(ThemeData theme, Task task, {bool highlightAttention = false}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: highlightAttention
          ? Colors.purple.shade50.withOpacity(0.6)
          : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlightAttention ? Colors.purple.shade300 : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTaskDetail(task.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(status: task.status),
                ],
              ),
              if (task.subjectLine != null && task.subjectLine!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.subjectLine!,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PriorityBadge(priority: task.priority),
                  AttemptBadge(
                    attemptCount: task.attemptCount,
                    maxAttempts: task.maxAttempts,
                    isCompleted: task.isCompleted,
                  ),
                  if (task.dueDate != null)
                    DueDateBadge(
                      dueDate: task.dueDate,
                      isCompleted: task.isCompleted,
                    ),
                  if (task.nextActionDate != null && !task.isCompleted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alarm, size: 10, color: Colors.blue.shade800),
                          const SizedBox(width: 4),
                          Text(
                            'Next: ${AppDateFormat.formatDate(task.nextActionDate)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, IconData icon, MaterialColor color}) _getNotificationMeta(String type) {
    switch (type) {
      case 'task_assigned':
        return (label: 'Assigned', icon: Icons.person_add, color: Colors.blue);
      case 'task_reassigned':
        return (label: 'Reassigned', icon: Icons.swap_horiz, color: Colors.lightBlue);
      case 'reminder_due':
        return (label: 'Reminder', icon: Icons.alarm, color: Colors.amber);
      case 'follow_up_due':
        return (label: 'Follow-up', icon: Icons.repeat, color: Colors.teal);
      case 'next_action_due':
        return (label: 'Next Action', icon: Icons.play_circle_fill, color: Colors.indigo);
      case 'task_overdue':
        return (label: 'Overdue', icon: Icons.warning_amber_rounded, color: Colors.red);
      case 'attempt_limit_reached':
        return (label: 'Max Attempts', icon: Icons.priority_high, color: Colors.purple);
      case 'task_completed':
        return (label: 'Completed', icon: Icons.check_circle, color: Colors.green);
      case 'task_reopened':
        return (label: 'Reopened', icon: Icons.replay, color: Colors.orange);
      default:
        return (label: 'Alert', icon: Icons.notifications, color: Colors.blueGrey);
    }
  }
}
