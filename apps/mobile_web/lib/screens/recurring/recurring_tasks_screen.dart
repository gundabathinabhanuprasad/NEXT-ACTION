import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/recurring/recurring_task_models.dart';
import '../../services/client/client_service.dart';
import '../../services/recurring/recurring_task_service.dart';
import '../../services/task/task_service.dart';
import '../../services/template/task_template_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';

/// Screen for managing Recurring Task schedules, evaluation triggers, and automated workflows.
class RecurringTasksScreen extends StatefulWidget {
  final RecurringTaskService recurringService;
  final TaskService taskService;
  final TaskTemplateService? templateService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;

  const RecurringTasksScreen({
    super.key,
    required this.recurringService,
    required this.taskService,
    this.templateService,
    this.clientService,
    this.workflowService,
    this.userService,
  });

  @override
  State<RecurringTasksScreen> createState() => _RecurringTasksScreenState();
}

class _RecurringTasksScreenState extends State<RecurringTasksScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isLoading = false;
  bool _isEvaluating = false;
  String? _errorMessage;

  List<RecurringTask> _recurringTasks = [];
  int _total = 0;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool? _filterIsActive;

  @override
  void initState() {
    super.initState();
    _loadRecurringTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecurringTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.recurringService.getRecurringTasks(
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        isActive: _filterIsActive,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          _recurringTasks = response.items;
          _total = response.total;
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load recurring tasks.';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _currentPage = 1;
      _loadRecurringTasks();
    });
  }

  Future<void> _evaluateRecurrences() async {
    setState(() => _isEvaluating = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.recurringService.evaluateRecurringTasks();
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Evaluated ${result.evaluatedDefinitions} definition(s), created ${result.tasksCreated} task instance(s).',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _loadRecurringTasks();
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Evaluation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isEvaluating = false);
    }
  }

  Future<void> _deleteRecurringTask(RecurringTask rec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recurring Schedule'),
        content: Text('Are you sure you want to delete recurring schedule "${rec.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.recurringService.deleteRecurringTask(rec.id);
        _loadRecurringTasks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String recurrenceType = 'daily';
    int interval = 1;
    String priority = 'medium';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Recurring Schedule'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Schedule Name *', hintText: 'e.g., Daily Invoice Sweep'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description (Optional)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: recurrenceType,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (val) => setDialogState(() => recurrenceType = val ?? 'daily'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    ],
                    onChanged: (val) => setDialogState(() => priority = val ?? 'medium'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  await widget.recurringService.createRecurringTask(
                    name: nameController.text.trim(),
                    description: descriptionController.text.trim().isNotEmpty ? descriptionController.text.trim() : null,
                    startDate: DateTime.now().toUtc(),
                    recurrenceType: recurrenceType,
                    interval: interval,
                    priority: priority,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx, true);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to create: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Create Schedule'),
            ),
          ],
        ),
      ),
    );

    if (created == true) _loadRecurringTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? 'Recurring Task Schedules ($_total)' : 'Recurring Task Schedules'),
        actions: [
          IconButton(
            icon: _isEvaluating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.flash_on),
            tooltip: 'Evaluate Due Recurrences',
            onPressed: _isEvaluating ? null : _evaluateRecurrences,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadRecurringTasks,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Recurring Task'),
      ),
      body: Column(
        children: [
          // Search and Evaluate banner
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search recurring tasks...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _currentPage = 1;
                                _loadRecurringTasks();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isEvaluating ? null : _evaluateRecurrences,
                  icon: const Icon(Icons.play_circle_filled, size: 18),
                  label: const Text('Evaluate Now'),
                ),
              ],
            ),
          ),

          if (_isLoading) const LinearProgressIndicator(),

          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _loadRecurringTasks, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : _recurringTasks.isEmpty && !_isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.autorenew, size: 56, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No recurring schedules configured.',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            const Text('Set up periodic automated tasks for daily, weekly, or monthly routines.'),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _openCreateDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Create Recurring Schedule'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        itemCount: _recurringTasks.length,
                        itemBuilder: (context, index) {
                          final rec = _recurringTasks[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12.0),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rec.name,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            if (rec.subjectLine != null && rec.subjectLine!.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4.0),
                                                child: Text(
                                                  'Subject: ${rec.subjectLine}',
                                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      PriorityBadge(priority: rec.priority),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: rec.isActive ? Colors.green.shade50 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: rec.isActive ? Colors.green.shade400 : Colors.grey.shade400,
                                          ),
                                        ),
                                        child: Text(
                                          rec.isActive ? 'ACTIVE' : 'INACTIVE',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: rec.isActive ? Colors.green.shade800 : Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  if (rec.description != null && rec.description!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      rec.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.grey.shade800),
                                    ),
                                  ],

                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Chip(
                                        avatar: const Icon(Icons.schedule, size: 16),
                                        label: Text('Frequency: ${rec.recurrenceType.toUpperCase()} (every ${rec.interval})'),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      Chip(
                                        avatar: const Icon(Icons.next_plan, size: 16),
                                        label: Text('Next Run: ${rec.nextRunAt.toLocal().toString().split('.')[0]}'),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      if (rec.lastRunAt != null)
                                        Chip(
                                          avatar: const Icon(Icons.history, size: 16),
                                          label: Text('Last Run: ${rec.lastRunAt!.toLocal().toString().split('.')[0]}'),
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                    ],
                                  ),

                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Schedule ID: ${rec.id.length >= 8 ? rec.id.substring(0, 8) : rec.id}...',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                        tooltip: 'Delete Schedule',
                                        onPressed: () => _deleteRecurringTask(rec),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
