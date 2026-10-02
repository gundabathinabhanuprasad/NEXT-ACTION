import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/task/task_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/client/client_service.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_list_screen.dart';

/// Next Actions Workspace Screen displaying scheduled next action tasks.
class NextActionsScreen extends StatefulWidget {
  final TaskService taskService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;
  final AuthProvider? authProvider;
  final String? currentUserId;

  const NextActionsScreen({
    super.key,
    required this.taskService,
    this.clientService,
    this.workflowService,
    this.userService,
    this.authProvider,
    this.currentUserId,
  });

  @override
  State<NextActionsScreen> createState() => _NextActionsScreenState();
}

class _NextActionsScreenState extends State<NextActionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Task> _tasks = [];
  Map<String, Client> _clientCache = {};
  Map<String, Workflow> _workflowCache = {};
  Map<String, User> _userCache = {};

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  bool _onlyMyNextActions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _fetchNextActionTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchNextActionTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch tasks with next action date set
      final response = await widget.taskService.getTasks(
        hasNextAction: true,
        pageSize: 100,
      );

      final tasks = response.items;

      // Populate related entity caches if services are provided
      if (widget.clientService != null) {
        try {
          final clientsRes = await widget.clientService!.getClients(pageSize: 100);
          _clientCache = {for (final c in clientsRes.items) c.id: c};
        } catch (_) {}
      }

      if (widget.workflowService != null) {
        try {
          final workflowsRes = await widget.workflowService!.getWorkflows(pageSize: 100);
          _workflowCache = {for (final w in workflowsRes.items) w.id: w};
        } catch (_) {}
      }

      if (widget.userService != null) {
        try {
          final usersRes = await widget.userService!.getUsers(pageSize: 100);
          _userCache = {for (final u in usersRes.items) u.id: u};
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load next actions: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Task> _filterTasksByTab(int tabIndex, String? currentUserId) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    List<Task> list = _tasks.where((t) => t.nextActionDate != null && t.status != 'completed').toList();

    if (_onlyMyNextActions && currentUserId != null) {
      list = list.where((t) => t.assignedUserId == currentUserId).toList();
    }

    switch (tabIndex) {
      case 1: // Overdue Next Actions (nextActionDate < todayStart)
        list = list.where((t) => t.nextActionDate!.isBefore(todayStart)).toList();
        break;
      case 2: // Today's Next Actions (nextActionDate >= todayStart && nextActionDate <= todayEnd)
        list = list
            .where((t) =>
                t.nextActionDate!.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
                t.nextActionDate!.isBefore(todayEnd))
            .toList();
        break;
      case 3: // Upcoming Next Actions (nextActionDate > todayEnd)
        list = list.where((t) => t.nextActionDate!.isAfter(todayEnd)).toList();
        break;
      case 0: // All Next Actions
      default:
        break;
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((t) {
        final titleMatch = t.title.toLowerCase().contains(_searchQuery);
        final descMatch = (t.description ?? '').toLowerCase().contains(_searchQuery);
        final client = t.clientId != null ? _clientCache[t.clientId] : null;
        final clientMatch = client != null && client.name.toLowerCase().contains(_searchQuery);
        return titleMatch || descMatch || clientMatch;
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.currentUserId ?? widget.authProvider?.currentUser?.id;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final activeTasks = _tasks.where((t) => t.nextActionDate != null && t.status != 'completed').toList();
    final scopedTasks = _onlyMyNextActions && currentUserId != null
        ? activeTasks.where((t) => t.assignedUserId == currentUserId).toList()
        : activeTasks;

    final overdueCount = scopedTasks.where((t) => t.nextActionDate!.isBefore(todayStart)).length;
    final todayCount = scopedTasks
        .where((t) =>
            t.nextActionDate!.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
            t.nextActionDate!.isBefore(todayEnd))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Next Actions Workspace'),
        actions: [
          // Filter toggle: My Next Actions vs All
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                _onlyMyNextActions ? Icons.person : Icons.group,
                size: 16,
                color: _onlyMyNextActions ? Colors.white : Colors.blue.shade900,
              ),
              label: Text(_onlyMyNextActions ? 'My Next Actions' : 'All Next Actions'),
              selected: _onlyMyNextActions,
              selectedColor: const Color(0xFF1E88E5),
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: _onlyMyNextActions ? Colors.white : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (val) => setState(() => _onlyMyNextActions = val),
            ),
          ),
          IconButton(
            tooltip: 'View in Task List',
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskListScreen(
                    taskService: widget.taskService,
                    clientService: widget.clientService,
                    workflowService: widget.workflowService,
                    userService: widget.userService,
                    currentUserId: currentUserId,
                    initialSmartFilter: TaskSmartFilter.hasNextAction,
                  ),
                ),
              ).then((_) => _fetchNextActionTasks());
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'All (${scopedTasks.length})'),
            Tab(
              child: Row(
                children: [
                  const Text('Overdue'),
                  if (overdueCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$overdueCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                children: [
                  const Text('Today'),
                  if (todayCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$todayCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Upcoming'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search & Scope Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search next action tasks...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              onPressed: _fetchNextActionTasks,
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTaskList(0, currentUserId),
                          _buildTaskList(1, currentUserId),
                          _buildTaskList(2, currentUserId),
                          _buildTaskList(3, currentUserId),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(int tabIndex, String? currentUserId) {
    final filtered = _filterTasksByTab(tabIndex, currentUserId);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No tasks match your search'
                  : _onlyMyNextActions
                      ? 'No next actions assigned to you in this category'
                      : 'No next actions scheduled in this category',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchNextActionTasks,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final task = filtered[index];
          final client = task.clientId != null ? _clientCache[task.clientId] : null;
          final workflow = task.workflowId != null ? _workflowCache[task.workflowId] : null;
          final assignee = task.assignedUserId != null ? _userCache[task.assignedUserId] : null;

          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final isOverdue = task.nextActionDate != null && task.nextActionDate!.isBefore(todayStart);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isOverdue ? Colors.red.shade300 : Colors.grey.shade300,
                width: isOverdue ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => TaskDetailScreen(
                      taskId: task.id,
                      taskService: widget.taskService,
                      clientService: widget.clientService,
                      workflowService: widget.workflowService,
                      userService: widget.userService,
                    ),
                  ),
                ).then((_) => _fetchNextActionTasks());
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: Next Action Date Badge, Priority Badge, Status Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.play_circle_outline,
                              size: 18,
                              color: isOverdue ? Colors.red.shade700 : const Color(0xFF1E88E5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Next Action: ${AppDateFormat.formatDateTime(task.nextActionDate)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isOverdue ? Colors.red.shade900 : const Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            PriorityBadge(priority: task.priority),
                            const SizedBox(width: 6),
                            StatusBadge(status: task.status),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Task Title
                    Text(
                      task.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (task.subjectLine?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Re: ${task.subjectLine}',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Client & Workflow Info
                    if (client != null || workflow != null) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (client != null)
                            Chip(
                              avatar: const Icon(Icons.business, size: 14, color: Color(0xFF1E88E5)),
                              label: Text(client.name, style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: Colors.blue.shade50,
                            ),
                          if (workflow != null)
                            Chip(
                              avatar: const Icon(Icons.account_tree_outlined, size: 14, color: Colors.indigo),
                              label: Text(workflow.name, style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: Colors.indigo.shade50,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    const Divider(height: 12),

                    // Footer row: Assignee, Attempts, Due Date
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 14, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Text(
                              assignee?.name ?? (task.assignedUserId != null ? 'Assigned' : 'Unassigned'),
                              style: TextStyle(
                                fontSize: 12,
                                color: task.assignedUserId == currentUserId
                                    ? Colors.blue.shade800
                                    : Colors.grey.shade800,
                                fontWeight: task.assignedUserId == currentUserId
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            AttemptBadge(
                              attemptCount: task.attemptCount,
                              maxAttempts: task.maxAttempts,
                              isCompleted: task.status == 'completed',
                            ),
                            if (task.dueDate != null) ...[
                              const SizedBox(width: 8),
                              DueDateBadge(dueDate: task.dueDate, isCompleted: task.status == 'completed'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
