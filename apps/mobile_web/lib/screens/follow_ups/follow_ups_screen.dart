import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/follow_up/follow_up_models.dart';
import '../../models/task/task_models.dart';
import '../../services/follow_up/follow_up_service.dart';
import '../../services/task/task_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';

/// Follow-up Center Screen for managing, tracking, and completing task follow-up action items.
class FollowUpsScreen extends StatefulWidget {
  final FollowUpService followUpService;
  final TaskService taskService;

  const FollowUpsScreen({
    super.key,
    required this.followUpService,
    required this.taskService,
  });

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<FollowUp> _followUps = [];
  Map<String, Task> _taskCache = {};
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _fetchFollowUps();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFollowUps() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final followUps = await widget.followUpService.getFollowUps();
      final taskIds = followUps.map((f) => f.taskId).toSet();
      final Map<String, Task> loadedTasks = {};

      for (final taskId in taskIds) {
        try {
          final task = await widget.taskService.getTask(taskId);
          loadedTasks[taskId] = task;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _followUps = followUps;
          _taskCache = loadedTasks;
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
          _errorMessage = 'Failed to load follow-ups: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleCompleteFollowUp(FollowUp followUp) async {
    final notesController = TextEditingController(text: followUp.notes ?? '');

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Follow-up'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mark this follow-up as completed? (Task status remains separate)'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Completion Notes (Optional)',
                hintText: 'e.g., Follow-up call finished, client agreed on terms.',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Completed'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    try {
      await widget.followUpService.completeFollowUp(
        followUp.id,
        notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up completed. Attempt invariant preserved.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchFollowUps();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDeleteFollowUp(String followUpId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Follow-up'),
        content: const Text('Are you sure you want to delete this follow-up?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.followUpService.deleteFollowUp(followUpId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up deleted.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchFollowUps();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleCreateFollowUp() async {
    final notesController = TextEditingController();
    DateTime scheduledDate = DateTime.now().add(const Duration(days: 2));
    String? selectedTaskId;

    List<Task> availableTasks = [];
    try {
      final taskList = await widget.taskService.getTasks(pageSize: 50);
      availableTasks = taskList.items.where((t) => t.status != 'completed').toList();
      if (availableTasks.isNotEmpty) {
        selectedTaskId = availableTasks.first.id;
      }
    } catch (_) {}

    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Schedule New Follow-up'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (availableTasks.isNotEmpty) ...[
                    const Text('Select Task *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedTaskId,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: availableTasks
                          .map((t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(t.title, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) => setDialogState(() => selectedTaskId = val),
                    ),
                    const SizedBox(height: 14),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, color: Color(0xFF1E88E5)),
                    title: Text('Scheduled: ${AppDateFormat.formatDate(scheduledDate)}'),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: scheduledDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => scheduledDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Follow-up Notes',
                      hintText: 'e.g., Check status of client document signing',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedTaskId != null) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Schedule Follow-up'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true || selectedTaskId == null) return;

    try {
      await widget.followUpService.createFollowUp(
        FollowUpCreateRequest(
          taskId: selectedTaskId!,
          scheduledAt: scheduledDate,
          notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up scheduled successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchFollowUps();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<FollowUp> _filterFollowUpsByTab(int tabIndex) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    List<FollowUp> list;
    switch (tabIndex) {
      case 1: // Overdue (scheduledAt < todayStart and !isCompleted)
        list = _followUps.where((f) => !f.isCompleted && f.scheduledAt.isBefore(todayStart)).toList();
        break;
      case 2: // Today (scheduledAt is today and !isCompleted)
        list = _followUps
            .where((f) =>
                !f.isCompleted &&
                f.scheduledAt.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
                f.scheduledAt.isBefore(todayEnd))
            .toList();
        break;
      case 3: // Upcoming (scheduledAt > todayEnd and !isCompleted)
        list = _followUps.where((f) => !f.isCompleted && f.scheduledAt.isAfter(todayEnd)).toList();
        break;
      case 4: // Completed
        list = _followUps.where((f) => f.isCompleted).toList();
        break;
      case 0: // All
      default:
        list = _followUps;
        break;
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((f) {
        final notesMatch = (f.notes ?? '').toLowerCase().contains(_searchQuery);
        final task = _taskCache[f.taskId];
        final taskMatch = task != null && task.title.toLowerCase().contains(_searchQuery);
        return notesMatch || taskMatch;
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final overdueCount = _followUps.where((f) => !f.isCompleted && f.scheduledAt.isBefore(todayStart)).length;
    final completedCount = _followUps.where((f) => f.isCompleted).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow-ups Center'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'All (${_followUps.length})'),
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
            const Tab(text: 'Today'),
            const Tab(text: 'Upcoming'),
            Tab(text: 'Completed ($completedCount)'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_task),
        label: const Text('Schedule Follow-up'),
        onPressed: _handleCreateFollowUp,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search follow-ups or tasks...',
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
                              onPressed: _fetchFollowUps,
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFollowUpList(0),
                          _buildFollowUpList(1),
                          _buildFollowUpList(2),
                          _buildFollowUpList(3),
                          _buildFollowUpList(4),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpList(int tabIndex) {
    final filtered = _filterFollowUpsByTab(tabIndex);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No follow-ups match your search'
                  : 'No follow-ups in this category',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFollowUps,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final followUp = filtered[index];
          final task = _taskCache[followUp.taskId];
          final isOverdue = !followUp.isCompleted &&
              followUp.scheduledAt.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isOverdue
                    ? Colors.red.shade300
                    : followUp.isCompleted
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
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
                      taskId: followUp.taskId,
                      taskService: widget.taskService,
                    ),
                  ),
                ).then((_) => _fetchFollowUps());
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: status chip & action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              followUp.isCompleted
                                  ? Icons.check_circle
                                  : isOverdue
                                      ? Icons.warning_amber_rounded
                                      : Icons.schedule,
                              size: 18,
                              color: followUp.isCompleted
                                  ? Colors.green
                                  : isOverdue
                                      ? Colors.red.shade700
                                      : Colors.teal.shade700,
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: followUp.isCompleted
                                    ? Colors.green.shade50
                                    : isOverdue
                                        ? Colors.red.shade50
                                        : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: followUp.isCompleted
                                      ? Colors.green.shade300
                                      : isOverdue
                                          ? Colors.red.shade300
                                          : Colors.teal.shade300,
                                ),
                              ),
                              child: Text(
                                followUp.isCompleted
                                    ? 'COMPLETED'
                                    : isOverdue
                                        ? 'OVERDUE'
                                        : 'SCHEDULED',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: followUp.isCompleted
                                      ? Colors.green.shade900
                                      : isOverdue
                                          ? Colors.red.shade900
                                          : Colors.teal.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (!followUp.isCompleted)
                              FilledButton.tonal(
                                onPressed: () => _handleCompleteFollowUp(followUp),
                                child: const Text('Complete', style: TextStyle(fontSize: 12)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                              tooltip: 'Delete Follow-up',
                              onPressed: () => _handleDeleteFollowUp(followUp.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Notes / Description
                    Text(
                      followUp.notes?.isNotEmpty == true
                          ? followUp.notes!
                          : 'General Follow-up Action',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),

                    // Associated Task
                    if (task != null) ...[
                      Row(
                        children: [
                          Icon(Icons.task_alt, size: 14, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],

                    // Scheduled Date and Completed Timestamp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 13, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              'Scheduled: ${AppDateFormat.formatDate(followUp.scheduledAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isOverdue ? Colors.red.shade700 : Colors.grey.shade700,
                                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        if (followUp.completedAt != null)
                          Text(
                            'Completed: ${AppDateFormat.formatDate(followUp.completedAt)}',
                            style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
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
