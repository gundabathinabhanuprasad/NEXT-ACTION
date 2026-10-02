import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/task/task_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../services/client/client_service.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import 'task_create_screen.dart';
import 'task_detail_screen.dart';

enum TaskSortOption {
  createdDesc('Created (Newest)', 'created_at', 'desc'),
  createdAsc('Created (Oldest)', 'created_at', 'asc'),
  dueDateAsc('Due Date (Earliest)', 'due_date', 'asc'),
  dueDateDesc('Due Date (Latest)', 'due_date', 'desc'),
  priorityDesc('Priority (Highest)', 'priority', 'desc'),
  priorityAsc('Priority (Lowest)', 'priority', 'asc'),
  nextActionAsc('Next Action (Earliest)', 'next_action_date', 'asc'),
  nextActionDesc('Next Action (Latest)', 'next_action_date', 'desc'),
  titleAsc('Title (A-Z)', 'title', 'asc'),
  titleDesc('Title (Z-A)', 'title', 'desc'),
  attemptDesc('Attempts (Most)', 'attempt_count', 'desc');

  final String label;
  final String sortBy;
  final String sortOrder;
  const TaskSortOption(this.label, this.sortBy, this.sortOrder);
}

enum TaskSmartFilter {
  all('All'),
  overdue('Overdue'),
  dueToday('Due Today'),
  upcoming('Upcoming'),
  highPriority('Urgent / High'),
  needsAction('Near / At Max Attempts'),
  nextActionOverdue('Next Action Overdue'),
  nextActionToday('Next Action Today'),
  nextActionUpcoming('Next Action Upcoming'),
  hasNextAction('Has Next Action'),
  noNextAction('No Next Action');

  final String label;
  const TaskSmartFilter(this.label);
}

enum TaskQuickPreset {
  all('All'),
  myOpen('Assigned to Me'),
  unassigned('Unassigned'),
  overdue('Overdue'),
  dueToday('Due Today'),
  upcoming('Upcoming'),
  highPriority('Urgent / High'),
  nearMaxAttempts('Near Max Attempts'),
  noNextAction('No Next Action');

  final String label;
  const TaskQuickPreset(this.label);
}

/// Rich, production-grade TaskListScreen with server-side advanced searching,
/// structured filtering, smart presets, custom date ranges, and sorting.
class TaskListScreen extends StatefulWidget {
  final TaskService taskService;
  final UserService? userService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final String? initialSearch;
  final String? initialStatus;
  final TaskSmartFilter? initialSmartFilter;
  final String? initialPriority;
  final TaskSortOption? initialSort;
  final String? initialClientId;
  final String? initialWorkflowId;
  final String? initialAssignedUserId;
  final String? currentUserId;
  final String? initialAssigneeFilter;
  final bool? initialOverdue;
  final bool? initialDueToday;
  final bool? initialUpcoming;
  final bool? initialNearMaxAttempts;
  final bool? initialNoNextAction;

  const TaskListScreen({
    super.key,
    required this.taskService,
    this.userService,
    this.clientService,
    this.workflowService,
    this.initialSearch,
    this.initialStatus,
    this.initialSmartFilter,
    this.initialPriority,
    this.initialSort,
    this.initialClientId,
    this.initialWorkflowId,
    this.initialAssignedUserId,
    this.currentUserId,
    this.initialAssigneeFilter,
    this.initialOverdue,
    this.initialDueToday,
    this.initialUpcoming,
    this.initialNearMaxAttempts,
    this.initialNoNextAction,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  late final UserService _userService;
  late final ClientService _clientService;
  late final WorkflowService _workflowService;

  bool _isLoading = false;
  String? _errorMessage;
  List<Task> _tasks = [];
  int _totalTasks = 0;
  int _currentPage = 1;
  static const int _pageSize = 20;

  Map<String, User> _userMap = {};
  List<User> _teamUsers = [];
  List<Client> _clients = [];
  List<Workflow> _workflows = [];

  // Filter States
  late TaskQuickPreset _selectedPreset;
  late String _selectedStatus;
  late String _selectedPriority;
  late TaskSortOption _selectedSort;
  String? _selectedClientId;
  String? _selectedWorkflowId;
  late String _selectedAssigneeFilter; // 'all', 'me', 'unassigned', or specific userId

  bool _isOverdue = false;
  bool _isDueToday = false;
  bool _isUpcoming = false;
  bool? _hasNextAction;
  bool? _noNextAction;
  bool _isNearMaxAttempts = false;

  DateTime? _dueFrom;
  DateTime? _dueTo;
  DateTime? _nextActionFrom;
  DateTime? _nextActionTo;

  @override
  void initState() {
    super.initState();
    _userService = widget.userService ?? UserService(apiClient: widget.taskService.apiClient);
    _clientService = widget.clientService ?? ClientService(apiClient: widget.taskService.apiClient);
    _workflowService = widget.workflowService ?? WorkflowService(apiClient: widget.taskService.apiClient);

    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchController.text = widget.initialSearch!;
    }

    _selectedStatus = widget.initialStatus ?? 'all';
    _selectedPriority = widget.initialPriority ?? 'all';
    _selectedSort = widget.initialSort ?? TaskSortOption.dueDateAsc;
    _selectedClientId = widget.initialClientId;
    _selectedWorkflowId = widget.initialWorkflowId;

    if (widget.initialAssigneeFilter != null) {
      _selectedAssigneeFilter = widget.initialAssigneeFilter!;
    } else if (widget.initialAssignedUserId != null) {
      if (widget.initialAssignedUserId == widget.currentUserId) {
        _selectedAssigneeFilter = 'me';
      } else {
        _selectedAssigneeFilter = widget.initialAssignedUserId!;
      }
    } else {
      _selectedAssigneeFilter = 'all';
    }

    // Initialize flags
    _isOverdue = widget.initialOverdue ?? false;
    _isDueToday = widget.initialDueToday ?? false;
    _isUpcoming = widget.initialUpcoming ?? false;
    _isNearMaxAttempts = widget.initialNearMaxAttempts ?? false;
    _noNextAction = widget.initialNoNextAction;

    // Smart filter mapping
    if (widget.initialSmartFilter != null) {
      _applySmartFilter(widget.initialSmartFilter!, triggerFetch: false);
    } else {
      _selectedPreset = TaskQuickPreset.all;
    }

    _loadSupportingData();
    _fetchTasks();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _currentPage = 1;
        });
        _fetchTasks();
      }
    });
  }

  Future<void> _loadSupportingData() async {
    try {
      final results = await Future.wait([
        _userService.getUsers(pageSize: 100),
        _clientService.getClients(pageSize: 100),
        _workflowService.getWorkflows(pageSize: 100),
      ]);

      if (mounted) {
        final userResponse = results[0] as UserListResponse;
        final clientResponse = results[1] as ClientListResponse;
        final workflowResponse = results[2] as WorkflowListResponse;

        final userMap = <String, User>{};
        for (final u in userResponse.items) {
          userMap[u.id] = u;
        }

        setState(() {
          _teamUsers = userResponse.items;
          _userMap = userMap;
          _clients = clientResponse.items;
          _workflows = workflowResponse.items;
        });
      }
    } catch (_) {
      // Non-blocking for task listing
    }
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? assignedUserIdParam;
      bool? unassignedParam;

      if (_selectedAssigneeFilter == 'me') {
        assignedUserIdParam = widget.currentUserId;
      } else if (_selectedAssigneeFilter == 'unassigned') {
        unassignedParam = true;
      } else if (_selectedAssigneeFilter != 'all') {
        assignedUserIdParam = _selectedAssigneeFilter;
      }

      final response = await widget.taskService.getTasks(
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        status: _selectedStatus != 'all' ? _selectedStatus : null,
        priority: _selectedPriority != 'all' ? _selectedPriority : null,
        assignedUserId: assignedUserIdParam,
        unassigned: unassignedParam,
        clientId: _selectedClientId != 'all' ? _selectedClientId : null,
        workflowId: _selectedWorkflowId != 'all' ? _selectedWorkflowId : null,
        dueFrom: _dueFrom,
        dueTo: _dueTo,
        nextActionFrom: _nextActionFrom,
        nextActionTo: _nextActionTo,
        overdue: _isOverdue ? true : null,
        dueToday: _isDueToday ? true : null,
        upcoming: _isUpcoming ? true : null,
        hasNextAction: _hasNextAction,
        noNextAction: _noNextAction,
        nearMaxAttempts: _isNearMaxAttempts ? true : null,
        sortBy: _selectedSort.sortBy,
        sortOrder: _selectedSort.sortOrder,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          _tasks = response.items;
          _totalTasks = response.total;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load tasks: $e';
        });
      }
    }
  }

  void _applySmartFilter(TaskSmartFilter filter, {bool triggerFetch = true}) {
    _resetFilterVariables();
    switch (filter) {
      case TaskSmartFilter.all:
        _selectedPreset = TaskQuickPreset.all;
        break;
      case TaskSmartFilter.overdue:
        _selectedPreset = TaskQuickPreset.overdue;
        _isOverdue = true;
        break;
      case TaskSmartFilter.dueToday:
        _selectedPreset = TaskQuickPreset.dueToday;
        _isDueToday = true;
        break;
      case TaskSmartFilter.upcoming:
        _selectedPreset = TaskQuickPreset.upcoming;
        _isUpcoming = true;
        break;
      case TaskSmartFilter.highPriority:
        _selectedPreset = TaskQuickPreset.highPriority;
        _selectedPriority = 'high';
        break;
      case TaskSmartFilter.needsAction:
        _selectedPreset = TaskQuickPreset.nearMaxAttempts;
        _isNearMaxAttempts = true;
        break;
      case TaskSmartFilter.nextActionOverdue:
      case TaskSmartFilter.nextActionToday:
      case TaskSmartFilter.nextActionUpcoming:
      case TaskSmartFilter.hasNextAction:
        _selectedPreset = TaskQuickPreset.all;
        _hasNextAction = true;
        break;
      case TaskSmartFilter.noNextAction:
        _selectedPreset = TaskQuickPreset.noNextAction;
        _noNextAction = true;
        break;
    }
    _currentPage = 1;
    if (triggerFetch) {
      _fetchTasks();
    }
  }

  void _applyQuickPreset(TaskQuickPreset preset) {
    _resetFilterVariables();
    _selectedPreset = preset;

    switch (preset) {
      case TaskQuickPreset.all:
        break;
      case TaskQuickPreset.myOpen:
        _selectedAssigneeFilter = 'me';
        break;
      case TaskQuickPreset.unassigned:
        _selectedAssigneeFilter = 'unassigned';
        break;
      case TaskQuickPreset.overdue:
        _isOverdue = true;
        break;
      case TaskQuickPreset.dueToday:
        _isDueToday = true;
        break;
      case TaskQuickPreset.upcoming:
        _isUpcoming = true;
        break;
      case TaskQuickPreset.highPriority:
        _selectedPriority = 'high';
        break;
      case TaskQuickPreset.nearMaxAttempts:
        _isNearMaxAttempts = true;
        break;
      case TaskQuickPreset.noNextAction:
        _noNextAction = true;
        break;
    }

    _currentPage = 1;
    setState(() {});
    _fetchTasks();
  }

  void _resetFilterVariables() {
    _selectedStatus = 'all';
    _selectedPriority = 'all';
    _selectedAssigneeFilter = 'all';
    _selectedClientId = null;
    _selectedWorkflowId = null;
    _isOverdue = false;
    _isDueToday = false;
    _isUpcoming = false;
    _hasNextAction = null;
    _noNextAction = null;
    _isNearMaxAttempts = false;
    _dueFrom = null;
    _dueTo = null;
    _nextActionFrom = null;
    _nextActionTo = null;
  }

  void _clearAllFilters() {
    _searchController.clear();
    _resetFilterVariables();
    _selectedPreset = TaskQuickPreset.all;
    _currentPage = 1;
    setState(() {});
    _fetchTasks();
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedPreset != TaskQuickPreset.all ||
        _selectedStatus != 'all' ||
        _selectedPriority != 'all' ||
        _selectedAssigneeFilter != 'all' ||
        _selectedClientId != null ||
        _selectedWorkflowId != null ||
        _isOverdue ||
        _isDueToday ||
        _isUpcoming ||
        _hasNextAction != null ||
        _noNextAction != null ||
        _isNearMaxAttempts ||
        _dueFrom != null ||
        _dueTo != null ||
        _nextActionFrom != null ||
        _nextActionTo != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & Discovery'),
        actions: [
          // Filter Panel Button with Active Filter Dot
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Advanced Filters',
                onPressed: _openFilterBottomSheet,
              ),
              if (_hasActiveFilters)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          // Sort Options Menu
          PopupMenuButton<TaskSortOption>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort Options',
            initialValue: _selectedSort,
            onSelected: (option) {
              setState(() {
                _selectedSort = option;
                _currentPage = 1;
              });
              _fetchTasks();
            },
            itemBuilder: (context) => TaskSortOption.values.map((option) {
              return PopupMenuItem<TaskSortOption>(
                value: option,
                child: Row(
                  children: [
                    if (_selectedSort == option) ...[
                      Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                    ] else
                      const SizedBox(width: 24),
                    Text(option.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchTasks,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => TaskCreateScreen(
                taskService: widget.taskService,
                userService: _userService,
                initialClientId: _selectedClientId,
                initialWorkflowId: _selectedWorkflowId,
              ),
            ),
          );
          if (created == true) {
            _fetchTasks();
          }
        },
      ),
      body: Column(
        children: [
          // Search Box with Debounce & Clear Action
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: theme.colorScheme.surface,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search tasks, clients, workflows, assignees...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),

          // Quick Presets Row
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: TaskQuickPreset.values.map((preset) {
                final isSelected = _selectedPreset == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(preset.label, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        _applyQuickPreset(preset);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Active Filter Chips Bar (with individual removal & Clear All)
          if (_hasActiveFilters) _buildActiveFilterChips(theme),

          // Result Summary & Pagination Controls
          _buildSummaryAndPaginationBar(theme),

          // Main Task List Body
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(64),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'Active Filters: ',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              InputChip(
                avatar: const Icon(Icons.search, size: 14),
                label: Text('Search: "${_searchController.text}"', style: const TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  _searchController.clear();
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_selectedStatus != 'all') ...[
              InputChip(
                label: Text('Status: ${_selectedStatus.toUpperCase()}', style: const TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedStatus = 'all');
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_selectedPriority != 'all') ...[
              InputChip(
                label: Text('Priority: ${_selectedPriority.toUpperCase()}', style: const TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedPriority = 'all');
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_selectedAssigneeFilter == 'me') ...[
              InputChip(
                avatar: const Icon(Icons.person, size: 14),
                label: const Text('Assignee: My Tasks', style: TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedAssigneeFilter = 'all');
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ] else if (_selectedAssigneeFilter == 'unassigned') ...[
              InputChip(
                avatar: const Icon(Icons.person_off, size: 14),
                label: const Text('Assignee: Unassigned', style: TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedAssigneeFilter = 'all');
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ] else if (_selectedAssigneeFilter != 'all') ...[
              InputChip(
                avatar: const Icon(Icons.person, size: 14),
                label: Text(
                  'Assignee: ${_userMap[_selectedAssigneeFilter]?.name ?? _selectedAssigneeFilter.substring(0, 8)}',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedAssigneeFilter = 'all');
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_selectedClientId != null) ...[
              InputChip(
                avatar: const Icon(Icons.business, size: 14),
                label: Text(
                  'Client: ${_clients.firstWhere((c) => c.id == _selectedClientId, orElse: () => Client(id: _selectedClientId!, name: 'Client', createdAt: DateTime.now(), updatedAt: DateTime.now())).name}',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedClientId = null);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_selectedWorkflowId != null) ...[
              InputChip(
                avatar: const Icon(Icons.account_tree, size: 14),
                label: Text(
                  'Workflow: ${_workflows.firstWhere((w) => w.id == _selectedWorkflowId, orElse: () => Workflow(id: _selectedWorkflowId!, name: 'Workflow', createdAt: DateTime.now(), updatedAt: DateTime.now())).name}',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: true,
                onDeleted: () {
                  setState(() => _selectedWorkflowId = null);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_isOverdue) ...[
              InputChip(
                label: const Text('Overdue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                selected: true,
                onDeleted: () {
                  setState(() => _isOverdue = false);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_isDueToday) ...[
              InputChip(
                label: const Text('Due Today', style: TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _isDueToday = false);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_isUpcoming) ...[
              InputChip(
                label: const Text('Upcoming', style: TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _isUpcoming = false);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_dueFrom != null || _dueTo != null) ...[
              InputChip(
                avatar: const Icon(Icons.calendar_today, size: 14),
                label: Text('Due: ${_formatDate(_dueFrom)} - ${_formatDate(_dueTo)}', style: const TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() {
                    _dueFrom = null;
                    _dueTo = null;
                  });
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_hasNextAction == true) ...[
              InputChip(
                label: const Text('Has Next Action', style: TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _hasNextAction = null);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_noNextAction == true) ...[
              InputChip(
                label: const Text('No Next Action', style: TextStyle(fontSize: 11)),
                selected: true,
                onDeleted: () {
                  setState(() => _noNextAction = null);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            if (_isNearMaxAttempts) ...[
              InputChip(
                label: const Text('Near Max Attempts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                selected: true,
                onDeleted: () {
                  setState(() => _isNearMaxAttempts = false);
                  _fetchTasks();
                },
              ),
              const SizedBox(width: 6),
            ],
            TextButton(
              onPressed: _clearAllFilters,
              child: const Text('Clear All', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryAndPaginationBar(ThemeData theme) {
    final startItem = _totalTasks == 0 ? 0 : (_currentPage - 1) * _pageSize + 1;
    final endItem = (_currentPage * _pageSize) > _totalTasks ? _totalTasks : _currentPage * _pageSize;
    final totalPages = (_totalTasks / _pageSize).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _totalTasks == 0
                ? '0 tasks found'
                : 'Showing $startItem–$endItem of $_totalTasks tasks',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (totalPages > 1)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchTasks();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  'Page $_currentPage of $totalPages',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchTasks();
                        }
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: ErrorStateWidget(
          message: _errorMessage!,
          onRetry: _fetchTasks,
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.filter_alt_off, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                'No Matching Tasks',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text('Try adjusting your search criteria or active filters.'),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.clear_all),
                label: const Text('Reset All Filters'),
                onPressed: _clearAllFilters,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchTasks,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          return _buildTaskCard(theme, task);
        },
      ),
    );
  }

  Widget _buildTaskCard(ThemeData theme, Task task) {
    final assigneeName = task.assignedUserId != null
        ? (_userMap[task.assignedUserId]?.name ?? 'Assigned')
        : 'Unassigned';

    final clientObj = task.clientId != null
        ? _clients.firstWhere((c) => c.id == task.clientId, orElse: () => Client(id: task.clientId!, name: 'Client', createdAt: DateTime.now(), updatedAt: DateTime.now()))
        : null;

    final workflowObj = task.workflowId != null
        ? _workflows.firstWhere((w) => w.id == task.workflowId, orElse: () => Workflow(id: task.workflowId!, name: 'Workflow', createdAt: DateTime.now(), updatedAt: DateTime.now()))
        : null;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: task.isOverdue
              ? theme.colorScheme.error.withAlpha(128)
              : (task.isNearMaxAttempts
                  ? Colors.amber.withAlpha(128)
                  : theme.colorScheme.outlineVariant),
          width: task.isOverdue || task.isNearMaxAttempts ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaskDetailScreen(
                taskId: task.id,
                taskService: widget.taskService,
                userService: _userService,
                clientService: _clientService,
                workflowService: _workflowService,
              ),
            ),
          );
          _fetchTasks();
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Priority, Status, Max Attempts Alert
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PriorityBadge(priority: task.priority),
                  const SizedBox(width: 8),
                  StatusBadge(status: task.status),
                  const Spacer(),
                  AttemptBadge(
                    attemptCount: task.attemptCount,
                    maxAttempts: task.maxAttempts,
                    isCompleted: task.isCompleted,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                task.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: task.status == 'completed' ? TextDecoration.lineThrough : null,
                ),
              ),

              // Subject Line / Description snippet
              if (task.subjectLine != null && task.subjectLine!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.subjectLine!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else if (task.description != null && task.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Organization Chips: Client, Workflow, Assignee
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (clientObj != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withAlpha(64),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.business, size: 12, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            clientObj.name,
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  if (workflowObj != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer.withAlpha(64),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree, size: 12, color: theme.colorScheme.secondary),
                          const SizedBox(width: 4),
                          Text(
                            workflowObj.name,
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.secondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          task.assignedUserId != null ? Icons.person : Icons.person_outline,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          assigneeName,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Dates: Due date & Next Action
              if (task.dueDate != null || task.nextActionDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (task.dueDate != null) ...[
                      Icon(
                        Icons.event,
                        size: 13,
                        color: task.isOverdue ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Due: ${_formatDate(task.dueDate)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: task.isOverdue ? FontWeight.bold : FontWeight.normal,
                          color: task.isOverdue ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (task.nextActionDate != null) ...[
                      Icon(Icons.bolt, size: 13, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Next: ${_formatDate(task.nextActionDate)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Advanced Task Filters',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _resetFilterVariables();
                              });
                            },
                            child: const Text('Reset All'),
                          ),
                        ],
                      ),
                      const Divider(),

                      // 1. Status Section
                      const SizedBox(height: 8),
                      const Text('STATUS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['all', 'pending', 'in_progress', 'completed', 'cancelled'].map((st) {
                          final isSelected = _selectedStatus == st;
                          return ChoiceChip(
                            label: Text(st == 'all' ? 'All' : st.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 12)),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setModalState(() => _selectedStatus = st);
                            },
                          );
                        }).toList(),
                      ),

                      // 2. Priority Section
                      const SizedBox(height: 16),
                      const Text('PRIORITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['all', 'low', 'medium', 'high', 'urgent'].map((pr) {
                          final isSelected = _selectedPriority == pr;
                          return ChoiceChip(
                            label: Text(pr == 'all' ? 'All' : pr.toUpperCase(), style: const TextStyle(fontSize: 12)),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setModalState(() => _selectedPriority = pr);
                            },
                          );
                        }).toList(),
                      ),

                      // 3. Assignment Section
                      const SizedBox(height: 16),
                      const Text('ASSIGNMENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedAssigneeFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('All Assignees')),
                          const DropdownMenuItem(value: 'me', child: Text('My Tasks (Assigned to Me)')),
                          const DropdownMenuItem(value: 'unassigned', child: Text('Unassigned Only')),
                          ..._teamUsers.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name))),
                        ],
                        onChanged: (val) {
                          if (val != null) setModalState(() => _selectedAssigneeFilter = val);
                        },
                      ),

                      // 4. Organization (Client & Workflow)
                      const SizedBox(height: 16),
                      const Text('CLIENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: _selectedClientId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Clients')),
                          ..._clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (val) {
                          setModalState(() => _selectedClientId = val);
                        },
                      ),

                      const SizedBox(height: 12),
                      const Text('WORKFLOW', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: _selectedWorkflowId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Workflows')),
                          ..._workflows.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))),
                        ],
                        onChanged: (val) {
                          setModalState(() => _selectedWorkflowId = val);
                        },
                      ),

                      // 5. Due Dates
                      const SizedBox(height: 16),
                      const Text('DUE DATES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Overdue', style: TextStyle(fontSize: 12)),
                            selected: _isOverdue,
                            onSelected: (val) => setModalState(() => _isOverdue = val),
                          ),
                          FilterChip(
                            label: const Text('Due Today', style: TextStyle(fontSize: 12)),
                            selected: _isDueToday,
                            onSelected: (val) => setModalState(() => _isDueToday = val),
                          ),
                          FilterChip(
                            label: const Text('Upcoming', style: TextStyle(fontSize: 12)),
                            selected: _isUpcoming,
                            onSelected: (val) => setModalState(() => _isUpcoming = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          _dueFrom != null || _dueTo != null
                              ? 'Custom Range: ${_formatDate(_dueFrom)} - ${_formatDate(_dueTo)}'
                              : 'Select Custom Due Date Range',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDateRange: _dueFrom != null && _dueTo != null
                                ? DateTimeRange(start: _dueFrom!, end: _dueTo!)
                                : null,
                          );
                          if (range != null) {
                            setModalState(() {
                              _dueFrom = range.start.toUtc();
                              _dueTo = range.end.toUtc();
                            });
                          }
                        },
                      ),

                      // 6. Next Action Filters
                      const SizedBox(height: 16),
                      const Text('NEXT ACTION DATES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Any Next Action', style: TextStyle(fontSize: 12)),
                            selected: _hasNextAction == null && _noNextAction == null,
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() {
                                  _hasNextAction = null;
                                  _noNextAction = null;
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Has Next Action', style: TextStyle(fontSize: 12)),
                            selected: _hasNextAction == true,
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() {
                                  _hasNextAction = true;
                                  _noNextAction = null;
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('No Next Action', style: TextStyle(fontSize: 12)),
                            selected: _noNextAction == true,
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() {
                                  _noNextAction = true;
                                  _hasNextAction = null;
                                });
                              }
                            },
                          ),
                        ],
                      ),

                      // 7. Attention Filter
                      const SizedBox(height: 16),
                      const Text('ATTENTION & LIMITS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('Near or At Max Attempts', style: TextStyle(fontSize: 13)),
                        subtitle: const Text('Tasks where attempt_count >= max_attempts - 1', style: TextStyle(fontSize: 11)),
                        value: _isNearMaxAttempts,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setModalState(() => _isNearMaxAttempts = val ?? false),
                      ),

                      const SizedBox(height: 24),
                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _currentPage = 1;
                            });
                            _fetchTasks();
                          },
                          child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
