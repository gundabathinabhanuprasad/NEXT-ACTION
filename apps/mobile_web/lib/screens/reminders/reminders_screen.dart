import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/reminder/reminder_models.dart';
import '../../models/task/task_models.dart';
import '../../services/reminder/reminder_service.dart';
import '../../services/task/task_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';

/// Reminder Center Screen for managing all task notifications and alerts.
class RemindersScreen extends StatefulWidget {
  final ReminderService reminderService;
  final TaskService taskService;

  const RemindersScreen({
    super.key,
    required this.reminderService,
    required this.taskService,
  });

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Reminder> _reminders = [];
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
    _fetchReminders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchReminders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final reminders = await widget.reminderService.getReminders();
      // Fetch associated tasks for titles
      final taskIds = reminders.map((r) => r.taskId).toSet();
      final Map<String, Task> loadedTasks = {};

      for (final taskId in taskIds) {
        try {
          final task = await widget.taskService.getTask(taskId);
          loadedTasks[taskId] = task;
        } catch (_) {
          // If task lookup fails, continue gracefully
        }
      }

      if (mounted) {
        setState(() {
          _reminders = reminders;
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
          _errorMessage = 'Failed to load reminders: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSendReminder(String reminderId) async {
    try {
      await widget.reminderService.sendReminder(reminderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder marked as sent. Attempt count unchanged.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchReminders();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDeleteReminder(String reminderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure you want to delete this reminder?'),
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
      await widget.reminderService.deleteReminder(reminderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder deleted.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchReminders();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleCreateReminder() async {
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime selectedTime = DateTime.now().add(const Duration(hours: 2));
    String? selectedTaskId;

    // Load available tasks
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
            title: const Text('Create New Reminder'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
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
                      leading: const Icon(Icons.notifications_active, color: Color(0xFF1E88E5)),
                      title: Text('Remind At: ${AppDateFormat.formatDateTime(selectedTime)}'),
                      trailing: TextButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: ctx,
                            initialDate: selectedTime,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (pickedDate != null) {
                            if (!ctx.mounted) return;
                            final pickedTime = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(selectedTime),
                            );
                            setDialogState(() {
                              selectedTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime?.hour ?? 9,
                                pickedTime?.minute ?? 0,
                              );
                            });
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        labelText: 'Reminder Message *',
                        hintText: 'e.g., Call client regarding proposal feedback',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Message is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate() && selectedTaskId != null) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Create Reminder'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true || selectedTaskId == null) return;

    try {
      await widget.reminderService.createReminder(
        ReminderCreateRequest(
          taskId: selectedTaskId!,
          remindAt: selectedTime,
          message: messageController.text.trim(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder created successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchReminders();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Reminder> _filterRemindersByTab(int tabIndex) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    List<Reminder> list;
    switch (tabIndex) {
      case 1: // Due / Overdue (remindAt <= now and !isSent)
        list = _reminders.where((r) => !r.isSent && r.remindAt.isBefore(now)).toList();
        break;
      case 2: // Today (remindAt is today and !isSent)
        list = _reminders
            .where((r) =>
                !r.isSent &&
                r.remindAt.isAfter(todayStart) &&
                r.remindAt.isBefore(todayEnd))
            .toList();
        break;
      case 3: // Upcoming (remindAt > todayEnd and !isSent)
        list = _reminders.where((r) => !r.isSent && r.remindAt.isAfter(now)).toList();
        break;
      case 4: // Sent
        list = _reminders.where((r) => r.isSent).toList();
        break;
      case 0: // All
      default:
        list = _reminders;
        break;
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((r) {
        final msgMatch = r.message.toLowerCase().contains(_searchQuery);
        final task = _taskCache[r.taskId];
        final taskMatch = task != null && task.title.toLowerCase().contains(_searchQuery);
        return msgMatch || taskMatch;
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final dueCount = _reminders.where((r) => !r.isSent && r.remindAt.isBefore(DateTime.now())).length;
    final sentCount = _reminders.where((r) => r.isSent).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders Center'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'All (${_reminders.length})'),
            Tab(
              child: Row(
                children: [
                  const Text('Due / Overdue'),
                  if (dueCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$dueCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Today'),
            const Tab(text: 'Upcoming'),
            Tab(text: 'Sent ($sentCount)'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.alarm_add),
        label: const Text('Add Reminder'),
        onPressed: _handleCreateReminder,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search reminders or tasks...',
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
                              onPressed: _fetchReminders,
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildReminderList(0),
                          _buildReminderList(1),
                          _buildReminderList(2),
                          _buildReminderList(3),
                          _buildReminderList(4),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderList(int tabIndex) {
    final filtered = _filterRemindersByTab(tabIndex);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No reminders match your search'
                  : 'No reminders in this category',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchReminders,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final reminder = filtered[index];
          final task = _taskCache[reminder.taskId];
          final isPastDue = !reminder.isSent && reminder.remindAt.isBefore(DateTime.now());

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isPastDue
                    ? Colors.red.shade300
                    : reminder.isSent
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
                width: isPastDue ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => TaskDetailScreen(
                      taskId: reminder.taskId,
                      taskService: widget.taskService,
                    ),
                  ),
                ).then((_) => _fetchReminders());
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
                              reminder.isSent
                                  ? Icons.check_circle
                                  : isPastDue
                                      ? Icons.warning_amber_rounded
                                      : Icons.alarm,
                              size: 18,
                              color: reminder.isSent
                                  ? Colors.green
                                  : isPastDue
                                      ? Colors.red.shade700
                                      : Colors.amber.shade900,
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: reminder.isSent
                                    ? Colors.green.shade50
                                    : isPastDue
                                        ? Colors.red.shade50
                                        : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: reminder.isSent
                                      ? Colors.green.shade300
                                      : isPastDue
                                          ? Colors.red.shade300
                                          : Colors.amber.shade300,
                                ),
                              ),
                              child: Text(
                                reminder.isSent
                                    ? 'SENT'
                                    : isPastDue
                                        ? 'OVERDUE'
                                        : 'PENDING',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: reminder.isSent
                                      ? Colors.green.shade900
                                      : isPastDue
                                          ? Colors.red.shade900
                                          : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (!reminder.isSent)
                              TextButton.icon(
                                icon: const Icon(Icons.send, size: 15),
                                label: const Text('Send Now', style: TextStyle(fontSize: 12)),
                                onPressed: () => _handleSendReminder(reminder.id),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                              tooltip: 'Delete Reminder',
                              onPressed: () => _handleDeleteReminder(reminder.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Reminder Message
                    Text(
                      reminder.message,
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

                    // Timestamp
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Remind: ${AppDateFormat.formatDateTime(reminder.remindAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isPastDue ? Colors.red.shade700 : Colors.grey.shade700,
                            fontWeight: isPastDue ? FontWeight.w600 : FontWeight.normal,
                          ),
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
