import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/report/report_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../services/client/client_service.dart';
import '../../services/report/report_service.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';

/// Production-quality Reports & Management Insights Workspace for NextAction.
class ReportsScreen extends StatefulWidget {
  final ReportService reportService;
  final TaskService taskService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;
  final dynamic settingsProvider;

  const ReportsScreen({
    super.key,
    required this.reportService,
    required this.taskService,
    this.clientService,
    this.workflowService,
    this.userService,
    this.settingsProvider,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ClientService _clientService;
  late final WorkflowService _workflowService;
  late final UserService _userService;

  ReportType _selectedReportType = ReportType.taskSummary;
  ReportFilters _filters = const ReportFilters();

  bool _isLoading = false;
  String? _errorMessage;

  // Report Data States
  TaskSummaryReport? _taskSummary;
  TaskDetailReportResponse? _taskDetail;
  ProductivityReportResponse? _productivity;
  WorkloadReportResponse? _workload;
  ActivityReportResponse? _activity;
  ReminderFollowUpReportResponse? _scheduling;

  // Filter Dropdown Options
  List<Client> _clients = [];
  List<Workflow> _workflows = [];
  List<User> _users = [];

  // Pagination for Task Detail & Activity
  int _currentPage = 1;
  static const int _pageSize = 20;
  final String _sortBy = 'created_at';
  final String _sortOrder = 'desc';

  // Search Debouncing
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.settingsProvider != null && widget.settingsProvider.settings?.defaultReportType != null) {
      try {
        _selectedReportType = ReportType.fromApiValue(widget.settingsProvider.settings.defaultReportType as String);
      } catch (_) {}
    }

    _clientService = widget.clientService ?? ClientService(apiClient: widget.reportService.apiClient);
    _workflowService = widget.workflowService ?? WorkflowService(apiClient: widget.reportService.apiClient);
    _userService = widget.userService ?? UserService(apiClient: widget.reportService.apiClient);

    _loadFilterOptions();
    _fetchCurrentReport();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final results = await Future.wait([
        _clientService.getClients(pageSize: 100),
        _workflowService.getWorkflows(isActive: true, pageSize: 100),
        _userService.getUsers(isActive: true, pageSize: 100),
      ]);

      if (mounted) {
        setState(() {
          _clients = (results[0] as ClientListResponse).items;
          _workflows = (results[1] as WorkflowListResponse).items;
          _users = (results[2] as UserListResponse).items;
        });
      }
    } catch (_) {
      // Graceful fallback if filter metadata fails
    }
  }

  Future<void> _fetchCurrentReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      switch (_selectedReportType) {
        case ReportType.taskSummary:
          final summary = await widget.reportService.getTaskSummaryReport(filters: _filters);
          if (mounted) setState(() => _taskSummary = summary);
          break;

        case ReportType.taskDetail:
          final detail = await widget.reportService.getTaskDetailReport(
            filters: _filters,
            page: _currentPage,
            pageSize: _pageSize,
            sortBy: _sortBy,
            sortOrder: _sortOrder,
          );
          if (mounted) setState(() => _taskDetail = detail);
          break;

        case ReportType.productivity:
          final prod = await widget.reportService.getProductivityReport(
            dateFrom: _filters.dateFrom,
            dateTo: _filters.dateTo,
            filters: _filters,
          );
          if (mounted) setState(() => _productivity = prod);
          break;

        case ReportType.workload:
          final wl = await widget.reportService.getWorkloadReport(filters: _filters);
          if (mounted) setState(() => _workload = wl);
          break;

        case ReportType.activity:
          final act = await widget.reportService.getActivityReport(
            dateFrom: _filters.dateFrom,
            dateTo: _filters.dateTo,
            search: _filters.search,
            page: _currentPage,
            pageSize: _pageSize,
          );
          if (mounted) setState(() => _activity = act);
          break;

        case ReportType.remindersFollowups:
          final sched = await widget.reportService.getRemindersFollowupsReport(filters: _filters);
          if (mounted) setState(() => _scheduling = sched);
          break;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to load report: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerExport(ExportFormat format) async {
    try {
      final exportData = await widget.reportService.exportReport(
        reportType: _selectedReportType,
        format: format,
        filters: _filters,
      );

      if (!mounted) return;

      final previewSnippet = exportData.length > 300 ? '${exportData.substring(0, 300)}...' : exportData;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                format == ExportFormat.csv ? Icons.table_chart : Icons.data_object,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Export ${format.displayName} Generated',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_selectedReportType.displayName} exported successfully (${exportData.length} characters).',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    previewSnippet,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('OK'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${format.displayName} generated for ${_selectedReportType.displayName}'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
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
    ).then((_) => _fetchCurrentReport());
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final todayEnd = DateTime.utc(now.year, now.month, now.day, 23, 59, 59);

    DateTime? from;
    DateTime? to;

    switch (preset) {
      case 'today':
        from = todayStart;
        to = todayEnd;
        break;
      case 'last_7_days':
        from = todayStart.subtract(const Duration(days: 6));
        to = todayEnd;
        break;
      case 'last_30_days':
        from = todayStart.subtract(const Duration(days: 29));
        to = todayEnd;
        break;
      case 'this_month':
        from = DateTime.utc(now.year, now.month, 1);
        to = todayEnd;
        break;
      case 'all':
      default:
        from = null;
        to = null;
        break;
    }

    setState(() {
      _filters = _filters.copyWith(
        dateFrom: from,
        dateTo: to,
        clearDateFrom: from == null,
        clearDateTo: to == null,
      );
    });
    _fetchCurrentReport();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.assessment_outlined),
            SizedBox(width: 8),
            Text('Reports & Insights', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: _isLoading ? null : () => _triggerExport(ExportFormat.csv),
          ),
          IconButton(
            tooltip: 'Export JSON',
            icon: const Icon(Icons.code_outlined),
            onPressed: _isLoading ? null : () => _triggerExport(ExportFormat.json),
          ),
          IconButton(
            tooltip: 'Refresh Report',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchCurrentReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Report Type Selector Tabs
                _buildReportTypeSelector(theme),
                const SizedBox(height: 16),

                // 2. Filter & Controls Panel
                _buildFilterControlsPanel(theme),
                const SizedBox(height: 16),

                // 3. Error State Banner
                if (_errorMessage != null) ...[
                  _buildErrorBanner(theme, _errorMessage!),
                  const SizedBox(height: 16),
                ],

                // 4. Loading State Spinner
                if (_isLoading) ...[
                  const LoadingStateWidget(message: 'Generating report summary...'),
                ] else ...[
                  // 5. Active Report Content View
                  _buildActiveReportView(theme),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. Report Type Selector
  // ===========================================================================
  Widget _buildReportTypeSelector(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ReportType.values.map((type) {
              final isSelected = _selectedReportType == type;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(type.displayName),
                  selected: isSelected,
                  avatar: Icon(
                    _getReportIcon(type),
                    size: 16,
                    color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
                  ),
                  selectedColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? theme.colorScheme.onPrimary : null,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (selected) {
                    if (selected && _selectedReportType != type) {
                      setState(() {
                        _selectedReportType = type;
                        _currentPage = 1;
                      });
                      _fetchCurrentReport();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  IconData _getReportIcon(ReportType type) {
    switch (type) {
      case ReportType.taskSummary:
        return Icons.pie_chart_outline;
      case ReportType.taskDetail:
        return Icons.table_rows_outlined;
      case ReportType.productivity:
        return Icons.trending_up;
      case ReportType.workload:
        return Icons.group_work_outlined;
      case ReportType.activity:
        return Icons.timeline;
      case ReportType.remindersFollowups:
        return Icons.schedule_outlined;
    }
  }

  // ===========================================================================
  // 2. Filter Controls Panel
  // ===========================================================================
  Widget _buildFilterControlsPanel(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.filter_list, color: theme.colorScheme.primary),
        title: Text(
          'Report Filter Controls',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Reset Filters', style: TextStyle(fontSize: 11)),
              onPressed: () {
                _searchController.clear();
                setState(() => _filters = const ReportFilters());
                _fetchCurrentReport();
              },
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick Date Range Presets
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Date Range:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    _buildDateChip('All Time', 'all'),
                    _buildDateChip('Today', 'today'),
                    _buildDateChip('Last 7 Days', 'last_7_days'),
                    _buildDateChip('Last 30 Days', 'last_30_days'),
                    _buildDateChip('This Month', 'this_month'),
                  ],
                ),
                const SizedBox(height: 12),

                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search title, client, workflow, assignee...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filters = _filters.copyWith(search: '', clearSearch: true));
                              _fetchCurrentReport();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (val) {
                    setState(() => _filters = _filters.copyWith(search: val));
                    _fetchCurrentReport();
                  },
                ),
                const SizedBox(height: 12),

                // Secondary Filter Dropdowns: Client, Workflow, Assignee
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    // Client Dropdown
                    if (_clients.isNotEmpty)
                      DropdownButton<String?>(
                        value: _filters.clientId,
                        hint: const Text('All Clients', style: TextStyle(fontSize: 12)),
                        isDense: true,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Clients', style: TextStyle(fontSize: 12))),
                          ..._clients.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (val) {
                          setState(() => _filters = _filters.copyWith(clientId: val, clearClientId: val == null));
                          _fetchCurrentReport();
                        },
                      ),

                    // Workflow Dropdown
                    if (_workflows.isNotEmpty)
                      DropdownButton<String?>(
                        value: _filters.workflowId,
                        hint: const Text('All Workflows', style: TextStyle(fontSize: 12)),
                        isDense: true,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Workflows', style: TextStyle(fontSize: 12))),
                          ..._workflows.map((w) => DropdownMenuItem<String?>(value: w.id, child: Text(w.name, style: const TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (val) {
                          setState(() => _filters = _filters.copyWith(workflowId: val, clearWorkflowId: val == null));
                          _fetchCurrentReport();
                        },
                      ),

                    // Assignee Dropdown
                    if (_users.isNotEmpty)
                      DropdownButton<String?>(
                        value: _filters.assignedUserId,
                        hint: const Text('All Assignees', style: TextStyle(fontSize: 12)),
                        isDense: true,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Assignees', style: TextStyle(fontSize: 12))),
                          ..._users.map((u) => DropdownMenuItem<String?>(value: u.id, child: Text(u.name, style: const TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (val) {
                          setState(() => _filters = _filters.copyWith(assignedUserId: val, clearAssignedUserId: val == null));
                          _fetchCurrentReport();
                        },
                      ),

                    // Status Filter
                    DropdownButton<String?>(
                      value: _filters.status,
                      hint: const Text('All Statuses', style: TextStyle(fontSize: 12)),
                      isDense: true,
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('All Statuses', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'pending', child: Text('Pending', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'in_progress', child: Text('In Progress', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'completed', child: Text('Completed', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'cancelled', child: Text('Cancelled', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) {
                        setState(() => _filters = _filters.copyWith(status: val, clearStatus: val == null));
                        _fetchCurrentReport();
                      },
                    ),

                    // Priority Filter
                    DropdownButton<String?>(
                      value: _filters.priority,
                      hint: const Text('All Priorities', style: TextStyle(fontSize: 12)),
                      isDense: true,
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('All Priorities', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'urgent', child: Text('Urgent', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'high', child: Text('High', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'medium', child: Text('Medium', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem<String?>(value: 'low', child: Text('Low', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) {
                        setState(() => _filters = _filters.copyWith(priority: val, clearPriority: val == null));
                        _fetchCurrentReport();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Attention Toggles
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('Overdue Only', style: TextStyle(fontSize: 11)),
                      selected: _filters.overdue == true,
                      onSelected: (val) {
                        setState(() => _filters = _filters.copyWith(overdue: val ? true : null, clearOverdue: !val));
                        _fetchCurrentReport();
                      },
                    ),
                    FilterChip(
                      label: const Text('Due Today', style: TextStyle(fontSize: 11)),
                      selected: _filters.dueToday == true,
                      onSelected: (val) {
                        setState(() => _filters = _filters.copyWith(dueToday: val ? true : null, clearDueToday: !val));
                        _fetchCurrentReport();
                      },
                    ),
                    FilterChip(
                      label: const Text('Unassigned', style: TextStyle(fontSize: 11)),
                      selected: _filters.unassigned == true,
                      onSelected: (val) {
                        setState(() => _filters = _filters.copyWith(unassigned: val ? true : null, clearUnassigned: !val));
                        _fetchCurrentReport();
                      },
                    ),
                    FilterChip(
                      label: const Text('Near/Max Attempts', style: TextStyle(fontSize: 11)),
                      selected: _filters.nearMaxAttempts == true,
                      onSelected: (val) {
                        setState(() => _filters = _filters.copyWith(nearMaxAttempts: val ? true : null, clearNearMaxAttempts: !val));
                        _fetchCurrentReport();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, String preset) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _setDatePreset(preset),
    );
  }

  // ===========================================================================
  // 3. Active Report Views
  // ===========================================================================
  Widget _buildActiveReportView(ThemeData theme) {
    switch (_selectedReportType) {
      case ReportType.taskSummary:
        return _buildTaskSummaryView(theme);
      case ReportType.taskDetail:
        return _buildTaskDetailView(theme);
      case ReportType.productivity:
        return _buildProductivityView(theme);
      case ReportType.workload:
        return _buildWorkloadView(theme);
      case ReportType.activity:
        return _buildActivityView(theme);
      case ReportType.remindersFollowups:
        return _buildSchedulingView(theme);
    }
  }

  // ---------------------------------------------------------------------------
  // 3.1 Task Summary View
  // ---------------------------------------------------------------------------
  Widget _buildTaskSummaryView(ThemeData theme) {
    final s = _taskSummary;
    if (s == null) return const Center(child: Text('No summary data available.'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary KPI Grid
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            _buildMetricCard(theme, 'Total Tasks', '${s.totalTasks}', Icons.task_alt, Colors.blue),
            _buildMetricCard(theme, 'Open Workload', '${s.openTasks}', Icons.play_arrow, Colors.indigo),
            _buildMetricCard(theme, 'Completed', '${s.completedTasks}', Icons.check_circle, Colors.green),
            _buildMetricCard(theme, 'Overdue Tasks', '${s.overdueTasks}', Icons.warning_amber_rounded, Colors.red),
            _buildMetricCard(theme, 'Due Today', '${s.dueTodayTasks}', Icons.today, Colors.orange),
            _buildMetricCard(theme, 'Upcoming', '${s.upcomingTasks}', Icons.calendar_today, Colors.teal),
            _buildMetricCard(theme, 'Near Max Attempts', '${s.nearMaxAttempts}', Icons.priority_high, Colors.deepOrange),
            _buildMetricCard(theme, 'Cancelled', '${s.cancelledTasks}', Icons.cancel, Colors.grey),
          ],
        ),
        const SizedBox(height: 20),

        // Status & Priority Distribution Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status Breakdown', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildDistributionRow('Pending', s.statusBreakdown.pending, Colors.orange),
                      _buildDistributionRow('In Progress', s.statusBreakdown.inProgress, Colors.blue),
                      _buildDistributionRow('Completed', s.statusBreakdown.completed, Colors.green),
                      _buildDistributionRow('Cancelled', s.statusBreakdown.cancelled, Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Priority Distribution', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildDistributionRow('Urgent', s.priorityBreakdown.urgent, Colors.red),
                      _buildDistributionRow('High', s.priorityBreakdown.high, Colors.deepOrange),
                      _buildDistributionRow('Medium', s.priorityBreakdown.medium, Colors.amber),
                      _buildDistributionRow('Low', s.priorityBreakdown.low, Colors.blueGrey),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDistributionRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3.2 Task Detail Report View
  // ---------------------------------------------------------------------------
  Widget _buildTaskDetailView(ThemeData theme) {
    final d = _taskDetail;
    if (d == null || d.items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No matching tasks found for report criteria.')));
    }

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Task Records (${d.total} total)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text('Page $currentPage of $totalPages', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                columns: const [
                  DataColumn(label: Text('Title', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Priority', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Client', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Workflow', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Assignee', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Attempts', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: d.items.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(
                        InkWell(
                          onTap: () => _openTaskDetail(item.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              if (item.subjectLine != null)
                                Text(item.subjectLine!, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                      DataCell(_buildStatusBadge(item.status)),
                      DataCell(_buildPriorityBadge(item.priority)),
                      DataCell(Text(item.clientName ?? '-', style: const TextStyle(fontSize: 11))),
                      DataCell(Text(item.workflowName ?? '-', style: const TextStyle(fontSize: 11))),
                      DataCell(Text(item.assignedUserName ?? 'Unassigned', style: const TextStyle(fontSize: 11))),
                      DataCell(Text('${item.attemptCount}/${item.maxAttempts}', style: const TextStyle(fontSize: 11))),
                      DataCell(Text(item.dueDate != null ? dateFormat.format(item.dueDate!.toLocal()) : '-', style: const TextStyle(fontSize: 11))),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios, size: 14),
                          onPressed: () => _openTaskDetail(item.id),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Pagination Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchCurrentReport();
                        }
                      : null,
                ),
                Text('$_currentPage', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: (_currentPage * _pageSize) < d.total
                      ? () {
                          setState(() => _currentPage++);
                          _fetchCurrentReport();
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int get currentPage => _currentPage;
  int get totalPages => ((_taskDetail?.total ?? 1) / _pageSize).ceil();

  // ---------------------------------------------------------------------------
  // 3.3 Productivity Report View
  // ---------------------------------------------------------------------------
  Widget _buildProductivityView(ThemeData theme) {
    final p = _productivity;
    if (p == null) return const Center(child: Text('No productivity data available.'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Metrics
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            _buildMetricCard(theme, 'Created in Range', '${p.totalCreated}', Icons.add_task, Colors.blue),
            _buildMetricCard(theme, 'Completed in Range', '${p.totalCompleted}', Icons.check_circle_outline, Colors.green),
            _buildMetricCard(theme, 'Overdue Count', '${p.totalOverdue}', Icons.alarm_off, Colors.red),
            _buildMetricCard(theme, 'Overall Completion Rate', '${p.overallCompletionRate}%', Icons.percent, Colors.teal),
          ],
        ),
        const SizedBox(height: 20),

        // Daily Time-Series Table
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Daily Productivity Time Series (Zero-Preserved)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 38,
                    columns: const [
                      DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Created', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Completed', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Overdue', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Completion Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: p.dailyTrends.map((pt) {
                      return DataRow(
                        cells: [
                          DataCell(Text(pt.date, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                          DataCell(Text('${pt.createdCount}', style: const TextStyle(fontSize: 12))),
                          DataCell(Text('${pt.completedCount}', style: const TextStyle(fontSize: 12, color: Colors.green))),
                          DataCell(Text('${pt.overdueCount}', style: TextStyle(fontSize: 12, color: pt.overdueCount > 0 ? Colors.red : Colors.grey))),
                          DataCell(
                            Row(
                              children: [
                                SizedBox(
                                  width: 60,
                                  child: LinearProgressIndicator(
                                    value: (pt.completionRate / 100.0).clamp(0.0, 1.0),
                                    color: Colors.teal,
                                    backgroundColor: Colors.teal.withOpacity(0.2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${pt.completionRate}%', style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3.4 Workload Analysis View
  // ---------------------------------------------------------------------------
  Widget _buildWorkloadView(ThemeData theme) {
    final w = _workload;
    if (w == null) return const Center(child: Text('No workload data available.'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary KPIs
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            _buildMetricCard(theme, 'Open Workload', '${w.totalOpenTasks}', Icons.work_outline, Colors.blue),
            _buildMetricCard(theme, 'Completed Tasks', '${w.totalCompletedTasks}', Icons.task_alt, Colors.green),
            _buildMetricCard(theme, 'Overdue Workload', '${w.totalOverdueTasks}', Icons.warning_amber, Colors.red),
          ],
        ),
        const SizedBox(height: 20),

        // Assignees Workload Table
        _buildWorkloadSection(theme, 'Workload by Assignee', w.byAssignee, Icons.person_outline),
        const SizedBox(height: 16),

        // Clients Workload Table
        _buildWorkloadSection(theme, 'Workload by Client', w.byClient, Icons.business_outlined),
        const SizedBox(height: 16),

        // Workflows Workload Table
        _buildWorkloadSection(theme, 'Workload by Workflow', w.byWorkflow, Icons.account_tree_outlined),
      ],
    );
  }

  Widget _buildWorkloadSection(ThemeData theme, String title, List<WorkloadReportItem> items, IconData icon) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('No workload data.', style: TextStyle(color: Colors.grey)))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 38,
                  columns: const [
                    DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Open', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Due Today', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Overdue', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Completed', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: items.map((item) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              if (item.email != null) Text(item.email!, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                        ),
                        DataCell(Text('${item.openTasks}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12))),
                        DataCell(Text('${item.dueTodayTasks}', style: const TextStyle(color: Colors.orange, fontSize: 12))),
                        DataCell(Text('${item.overdueTasks}', style: TextStyle(color: item.overdueTasks > 0 ? Colors.red : Colors.grey, fontSize: 12))),
                        DataCell(Text('${item.completedTasks}', style: const TextStyle(color: Colors.green, fontSize: 12))),
                        DataCell(Text('${item.totalTasks}', style: const TextStyle(fontSize: 12))),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3.5 Activity Audit Report View
  // ---------------------------------------------------------------------------
  Widget _buildActivityView(ThemeData theme) {
    final a = _activity;
    if (a == null || a.items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No activity history found for report criteria.')));
    }

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Audit Trail (${a.total} activities)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: a.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final act = a.items[idx];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.history, size: 14, color: theme.colorScheme.primary),
                  ),
                  title: Row(
                    children: [
                      Text(act.action.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(width: 8),
                      if (act.taskTitle != null)
                        Expanded(
                          child: InkWell(
                            onTap: act.taskId != null ? () => _openTaskDetail(act.taskId!) : null,
                            child: Text(
                              act.taskTitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: act.taskId != null ? theme.colorScheme.primary : null,
                                decoration: act.taskId != null ? TextDecoration.underline : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('By: ${act.actorName ?? 'System'} • ${dateFormat.format(act.createdAt.toLocal())}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      if (act.reason != null && act.reason!.isNotEmpty)
                        Text('Reason: ${act.reason}', style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3.6 Scheduling Queues View
  // ---------------------------------------------------------------------------
  Widget _buildSchedulingView(ThemeData theme) {
    final s = _scheduling;
    if (s == null) return const Center(child: Text('No scheduling data available.'));

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Reminders Summary
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reminders Queue (${s.summary.remindersTotal} total)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    Text('Due Now: ${s.summary.remindersDue}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('Sent: ${s.summary.remindersSent}', style: const TextStyle(color: Colors.green, fontSize: 12)),
                    Text('Pending: ${s.summary.remindersPending}', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                if (s.reminders.isEmpty)
                  const Text('No reminders in queue.', style: TextStyle(color: Colors.grey, fontSize: 11))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: s.reminders.length > 5 ? 5 : s.reminders.length,
                    itemBuilder: (context, idx) {
                      final r = s.reminders[idx];
                      return ListTile(
                        dense: true,
                        leading: Icon(r.isSent ? Icons.check_circle : Icons.alarm, size: 16, color: r.isSent ? Colors.green : Colors.amber),
                        title: Text(r.taskTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        subtitle: Text('${r.message} • Remind at: ${dateFormat.format(r.remindAt.toLocal())}', style: const TextStyle(fontSize: 10)),
                        onTap: () => _openTaskDetail(r.taskId),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Follow-ups Summary
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Follow-ups Queue (${s.summary.followUpsTotal} total)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    Text('Overdue: ${s.summary.followUpsOverdue}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('Due Today: ${s.summary.followUpsToday}', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                    Text('Upcoming: ${s.summary.followUpsUpcoming}', style: const TextStyle(color: Colors.blue, fontSize: 12)),
                    Text('Completed: ${s.summary.followUpsCompleted}', style: const TextStyle(color: Colors.green, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                if (s.followUps.isEmpty)
                  const Text('No follow-ups in queue.', style: TextStyle(color: Colors.grey, fontSize: 11))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: s.followUps.length > 5 ? 5 : s.followUps.length,
                    itemBuilder: (context, idx) {
                      final f = s.followUps[idx];
                      return ListTile(
                        dense: true,
                        leading: Icon(f.isCompleted ? Icons.check_circle : Icons.repeat, size: 16, color: f.isCompleted ? Colors.green : Colors.teal),
                        title: Text(f.taskTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        subtitle: Text('Scheduled: ${dateFormat.format(f.scheduledAt.toLocal())}${f.notes != null ? ' • ${f.notes}' : ''}', style: const TextStyle(fontSize: 10)),
                        onTap: () => _openTaskDetail(f.taskId),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Helper Widgets
  // ===========================================================================
  Widget _buildMetricCard(ThemeData theme, String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = Colors.grey.shade200;
    Color fg = Colors.grey.shade800;

    switch (status.toLowerCase()) {
      case 'pending':
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
      case 'in_progress':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        break;
      case 'completed':
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
      case 'cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color = Colors.grey;
    switch (priority.toLowerCase()) {
      case 'urgent':
        color = Colors.red;
        break;
      case 'high':
        color = Colors.deepOrange;
        break;
      case 'medium':
        color = Colors.amber.shade700;
        break;
      case 'low':
        color = Colors.blueGrey;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flag, size: 12, color: color),
        const SizedBox(width: 4),
        Text(priority.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12))),
        ],
      ),
    );
  }
}
