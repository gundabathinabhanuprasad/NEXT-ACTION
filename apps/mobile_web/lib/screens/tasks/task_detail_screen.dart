import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/follow_up/follow_up_models.dart';
import '../../models/history/task_history_models.dart';
import '../../models/reminder/reminder_models.dart';
import '../../models/task/task_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../services/client/client_service.dart';
import '../../services/follow_up/follow_up_service.dart';
import '../../services/reminder/reminder_service.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../clients/client_detail_screen.dart';
import '../workflows/workflow_detail_screen.dart';

/// Comprehensive, production-grade TaskDetailScreen featuring the full 10-section
/// workflow for NextAction tasks, attempts, overrides, postponements, reminders,
/// follow-ups, and audit history.
class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  final Task? initialTask;
  final TaskService taskService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;

  const TaskDetailScreen({
    super.key,
    required this.taskId,
    this.initialTask,
    required this.taskService,
    this.clientService,
    this.workflowService,
    this.userService,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  Task? _task;
  List<TaskHistory> _history = [];
  List<Reminder> _reminders = [];
  List<FollowUp> _followUps = [];

  Client? _assignedClient;
  Workflow? _assignedWorkflow;
  User? _assignedUser;
  late final ClientService _clientService;
  late final WorkflowService _workflowService;
  late final UserService _userService;

  bool _isLoading = false;
  bool _isActionLoading = false;
  String? _errorMessage;
  bool _hasMutated = false;
  String _historyFilter = 'all';

  List<TaskHistory> get _filteredHistory {
    if (_historyFilter == 'all') return _history;
    return _history.where((h) => h.actionCategory == _historyFilter).toList();
  }

  @override
  void initState() {
    super.initState();
    _clientService = widget.clientService ?? ClientService(apiClient: widget.taskService.apiClient);
    _workflowService = widget.workflowService ?? WorkflowService(apiClient: widget.taskService.apiClient);
    _userService = widget.userService ?? UserService(apiClient: widget.taskService.apiClient);
    _task = widget.initialTask;
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final taskFuture = widget.taskService.getTask(widget.taskId);
      final historyFuture = widget.taskService.getTaskHistory(widget.taskId);
      final remindersFuture = widget.taskService.getTaskReminders(widget.taskId);
      final followUpsFuture = widget.taskService.getTaskFollowUps(widget.taskId);

      final results = await Future.wait([
        taskFuture,
        historyFuture,
        remindersFuture,
        followUpsFuture,
      ]);

      final loadedTask = results[0] as Task;
      Client? clientObj;
      Workflow? workflowObj;
      User? userObj;

      if (loadedTask.clientId != null) {
        try {
          clientObj = await _clientService.getClient(loadedTask.clientId!);
        } catch (_) {}
      }

      if (loadedTask.workflowId != null) {
        try {
          workflowObj = await _workflowService.getWorkflow(loadedTask.workflowId!);
        } catch (_) {}
      }

      if (loadedTask.assignedUserId != null) {
        try {
          userObj = await _userService.getUser(loadedTask.assignedUserId!);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _task = loadedTask;
          _history = results[1] as List<TaskHistory>;
          _reminders = results[2] as List<Reminder>;
          _followUps = results[3] as List<FollowUp>;
          _assignedClient = clientObj;
          _assignedWorkflow = workflowObj;
          _assignedUser = userObj;
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
          _errorMessage = 'Failed to load task details: $e';
        });
      }
    }
  }

  void _showSuccessSnackBar(String message, [Color? color]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // =========================================================================
  // Section 1: Edit Details (Title, Description, Subject Line)
  // =========================================================================

  Future<void> _handleEditDetails() async {
    final titleController = TextEditingController(text: _task?.title);
    final descController = TextEditingController(text: _task?.description);
    final subjectController = TextEditingController(text: _task?.subjectLine);
    final formKey = GlobalKey<FormState>();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Task Details'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Title cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject Line',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.updateTask(
        widget.taskId,
        TaskUpdateRequest(
          title: titleController.text.trim(),
          description: descController.text.trim(),
          subjectLine: subjectController.text.trim(),
        ),
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Task updated successfully.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 2: Change Status
  // =========================================================================

  Future<void> _handleChangeStatus() async {
    String selectedStatus = _task?.status ?? 'pending';
    final reasonController = TextEditingController();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Change Task Status'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedStatus = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason / Notes (Optional)',
                    border: OutlineInputBorder(),
                  ),
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
                child: const Text('Update Status'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.changeStatus(
        widget.taskId,
        status: selectedStatus,
        reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Status changed to ${selectedStatus.toUpperCase()}.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 3: Change Priority
  // =========================================================================

  Future<void> _handleChangePriority() async {
    String selectedPriority = _task?.priority ?? 'medium';
    final reasonController = TextEditingController();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Change Priority'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPriority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedPriority = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (Optional)',
                    border: OutlineInputBorder(),
                  ),
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
                child: const Text('Update Priority'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.changePriority(
        widget.taskId,
        priority: selectedPriority,
        reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Priority updated to ${selectedPriority.toUpperCase()}.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 4: Assign / Reassign Task
  // =========================================================================

  Future<void> _handleAssignTask() async {
    String? selectedUserId = _task?.assignedUserId;
    List<User> availableUsers = [];
    try {
      final userResp = await _userService.getUsers(isActive: true);
      availableUsers = userResp.items;
    } catch (_) {}

    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Assign / Reassign Task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a team member to assign this task, or choose Unassigned.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: selectedUserId,
                  decoration: const InputDecoration(
                    labelText: 'Assignee',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No user assigned (Unassigned)'),
                    ),
                    ...availableUsers.map((u) => DropdownMenuItem<String?>(
                          value: u.id,
                          child: Text(
                            '${u.name} (${u.email})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (val) {
                    setDialogState(() => selectedUserId = val);
                  },
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
                child: const Text('Save Assignment'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.assignTask(
        widget.taskId,
        assignedUserId: selectedUserId,
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar(
        selectedUserId != null ? 'Task assigned successfully.' : 'Task unassigned successfully.',
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 5: Postpone Due Date & Change Next Action Date
  // =========================================================================

  Future<void> _handlePostpone() async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 2));

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Postpone Due Date'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text('New Due Date: ${AppDateFormat.formatDate(selectedDate)}'),
                      trailing: TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                23,
                                59,
                              );
                            });
                          }
                        },
                        child: const Text('Change Date'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Reason for Postponement *',
                        hintText: 'e.g., Client requested follow-up next Tuesday',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Postponement reason is mandatory';
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
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Postpone'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.postponeTask(
        widget.taskId,
        newDueDate: selectedDate,
        reason: reasonController.text.trim(),
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Task due date postponed.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleChangeNextActionDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _task?.nextActionDate ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_task?.nextActionDate ?? now),
      );

      final combined = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? 9,
        pickedTime?.minute ?? 0,
      );

      setState(() => _isActionLoading = true);
      try {
        final updated = await widget.taskService.updateNextActionDate(
          widget.taskId,
          nextActionDate: combined,
        );
        _hasMutated = true;
        _task = updated;
        await _refreshAll();
        _showSuccessSnackBar('Next action date updated.');
      } on ApiException catch (e) {
        if (mounted) setState(() => _errorMessage = e.message);
      } finally {
        if (mounted) setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _handleClearNextActionDate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Next Action Date'),
        content: const Text('Are you sure you want to clear the next action date for this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Date'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.updateNextActionDate(
        widget.taskId,
        nextActionDate: null,
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Next action date cleared.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 6: Attempt & Authorized Override Workflow
  // =========================================================================

  Future<void> _handleNormalAttempt() async {
    final notesController = TextEditingController();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Work Attempt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current attempts: ${_task?.attemptCount ?? 0} / ${_task?.maxAttempts ?? 2}'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                hintText: 'e.g., Called client, left voicemail.',
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
            child: const Text('Record Attempt'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.recordAttempt(
        widget.taskId,
        notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Attempt ${updated.attemptCount}/${updated.maxAttempts} recorded.');
    } on ApiException catch (e) {
      if (mounted) {
        if (e.errorCode == 'MAX_ATTEMPTS_REACHED') {
          _showMaxAttemptsDialog(e.message);
        } else {
          setState(() => _errorMessage = e.message);
        }
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showMaxAttemptsDialog(String backendMessage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Text('Maximum Attempts Reached'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(backendMessage),
            const SizedBox(height: 12),
            const Text(
              'A normal attempt cannot be recorded. An authorized override with mandatory business justification is required to proceed.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Use Authorized Override'),
            onPressed: () {
              Navigator.pop(ctx);
              _handleAuthorizedOverride();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleAuthorizedOverride() async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authorized Attempt Override'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This task has reached its maximum attempts. Provide a mandatory business justification to perform an authorized override attempt.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Override Reason *',
                  hintText: 'e.g., Client requested additional discussion via manager.',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Override justification reason is required';
                  }
                  return null;
                },
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
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Confirm Override'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.recordOverrideAttempt(
        widget.taskId,
        reason: reasonController.text.trim(),
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar(
        'Authorized override recorded! (Attempts: ${updated.attemptCount}/${updated.maxAttempts})',
        Colors.orange.shade800,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 7: Completion & Reopen
  // =========================================================================

  Future<void> _handleComplete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Task'),
        content: const Text('Are you sure you want to mark this task as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.completeTask(widget.taskId);
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Task marked as completed!');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleReopen() async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Task'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a mandatory justification reason to reopen this task:'),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reopen Reason *',
                  hintText: 'e.g., Client requested additional scope review.',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Reopen reason is mandatory';
                  }
                  return null;
                },
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Reopen Task'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final updated = await widget.taskService.reopenTask(
        widget.taskId,
        reason: reasonController.text.trim(),
      );
      _hasMutated = true;
      _task = updated;
      await _refreshAll();
      _showSuccessSnackBar('Task reopened successfully.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 8: Reminders (Add Reminder & Send Reminder)
  // =========================================================================

  Future<void> _handleAddReminder() async {
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime selectedTime = DateTime.now().add(const Duration(hours: 2));

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Task Reminder'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active),
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
                        hintText: 'e.g., Send follow-up email before 3 PM',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Reminder message is required';
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
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Add Reminder'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await widget.taskService.createReminder(
        ReminderCreateRequest(
          taskId: widget.taskId,
          remindAt: selectedTime,
          message: messageController.text.trim(),
        ),
      );
      _hasMutated = true;
      await _refreshAll();
      _showSuccessSnackBar('Reminder created. (Attempt invariant preserved)');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleSendReminder(String reminderId) async {
    setState(() => _isActionLoading = true);
    try {
      await widget.taskService.sendReminder(reminderId);
      _hasMutated = true;
      await _refreshAll();
      _showSuccessSnackBar('Reminder marked as sent.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
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

    setState(() => _isActionLoading = true);
    try {
      final reminderService = ReminderService(apiClient: widget.taskService.apiClient);
      await reminderService.deleteReminder(reminderId);
      _hasMutated = true;
      await _refreshAll();
      _showSuccessSnackBar('Reminder deleted.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Section 9: Follow-ups (Add Follow-up & Complete Follow-up)
  // =========================================================================

  Future<void> _handleAddFollowUp() async {
    final notesController = TextEditingController();
    DateTime scheduledDate = DateTime.now().add(const Duration(days: 3));

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Schedule Follow-up'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.repeat),
                    title: Text('Scheduled: ${AppDateFormat.formatDate(scheduledDate)}'),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: scheduledDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            scheduledDate = picked;
                          });
                        }
                      },
                      child: const Text('Change Date'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'e.g., Check if signature received.',
                      border: OutlineInputBorder(),
                    ),
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
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Schedule'),
              ),
            ],
          );
        },
      ),
    );

    if (proceed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await widget.taskService.createFollowUp(
        FollowUpCreateRequest(
          taskId: widget.taskId,
          scheduledAt: scheduledDate,
          notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
        ),
      );
      _hasMutated = true;
      await _refreshAll();
      _showSuccessSnackBar('Follow-up scheduled.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleCompleteFollowUp(String followUpId) async {
    final notesController = TextEditingController();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Follow-up'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mark this follow-up as completed?'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Completion Notes (Optional)',
                border: OutlineInputBorder(),
              ),
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

    setState(() => _isActionLoading = true);
    try {
      await widget.taskService.completeFollowUp(
        followUpId,
        notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
      );
      _hasMutated = true;
      await _refreshAll();
      _showSuccessSnackBar('Follow-up completed.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
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

    setState(() => _isActionLoading = true);
    try {
      final followUpService = FollowUpService(apiClient: widget.taskService.apiClient);
      await followUpService.deleteFollowUp(followUpId);
      _hasMutated = true;
      await _refreshAll();
      _showSuccessSnackBar('Follow-up deleted.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // =========================================================================
  // Build Method
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = _task;

    return PopScope(
      canPop: true,
      onPopInvoked: (_) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Task Management'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _hasMutated),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh All',
              onPressed: _isLoading || _isActionLoading ? null : _refreshAll,
            ),
          ],
        ),
        body: _isLoading && task == null
            ? const Center(child: CircularProgressIndicator())
            : task == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_errorMessage ?? 'Task not found'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _refreshAll,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _buildContent(theme, task),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, Task task) {
    final isMaxed = task.hasReachedMaxAttempts;
    final isCompleted = task.isCompleted;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null)
                ErrorBanner(
                  message: _errorMessage!,
                  onDismiss: () => setState(() => _errorMessage = null),
                ),

              // =============================================================
              // Section 1: Task Information
              // =============================================================
              SectionCard(
                title: 'Task Information',
                icon: Icons.info_outline,
                trailing: TextButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Details'),
                  onPressed: _isActionLoading ? null : _handleEditDetails,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (task.subjectLine != null && task.subjectLine!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Subject: ${task.subjectLine}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (task.description != null && task.description!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(task.description!, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (task.templateId != null)
                          Chip(
                            avatar: const Icon(Icons.bookmark_outline, size: 16, color: Colors.blue),
                            label: const Text('Source: Template'),
                            backgroundColor: Colors.blue.shade50,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )
                        else if (task.recurringTaskId != null)
                          Chip(
                            avatar: const Icon(Icons.autorenew, size: 16, color: Colors.teal),
                            label: const Text('Source: Recurrence'),
                            backgroundColor: Colors.teal.shade50,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )
                        else
                          const Chip(
                            avatar: Icon(Icons.touch_app_outlined, size: 16, color: Colors.grey),
                            label: Text('Source: Manual'),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Task UUID: ${task.id}',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // =============================================================
              // Section: Client & Workflow Organization
              // =============================================================
              SectionCard(
                title: 'Client & Workflow Organization',
                icon: Icons.hub_outlined,
                child: Column(
                  children: [
                    // Client Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.business_outlined, size: 20, color: Color(0xFF1E88E5)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Client', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              if (_assignedClient != null)
                                Text(
                                  _assignedClient!.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                )
                              else if (task.clientId != null)
                                Text(
                                  'Client ID: ${task.clientId}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontFamily: 'monospace'),
                                )
                              else
                                Text(
                                  'No client assigned',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                        ),
                        if (task.clientId != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('View Client'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ClientDetailScreen(
                                    clientId: task.clientId!,
                                    initialClient: _assignedClient,
                                    clientService: _clientService,
                                    taskService: widget.taskService,
                                  ),
                                ),
                              ).then((_) => _refreshAll());
                            },
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    // Workflow Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_tree_outlined, size: 20, color: Colors.teal),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Workflow Pipeline', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              if (_assignedWorkflow != null)
                                Row(
                                  children: [
                                    Text(
                                      _assignedWorkflow!.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _assignedWorkflow!.isActive ? Colors.green.shade50 : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _assignedWorkflow!.isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _assignedWorkflow!.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else if (task.workflowId != null)
                                Text(
                                  'Workflow ID: ${task.workflowId}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontFamily: 'monospace'),
                                )
                              else
                                Text(
                                  'No workflow assigned',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                        ),
                        if (task.workflowId != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('View Workflow'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WorkflowDetailScreen(
                                    workflowId: task.workflowId!,
                                    initialWorkflow: _assignedWorkflow,
                                    workflowService: _workflowService,
                                    taskService: widget.taskService,
                                  ),
                                ),
                              ).then((_) => _refreshAll());
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // =============================================================
              // Section 2 & 3 & 4: Status, Priority, Assignment Controls
              // =============================================================
              SectionCard(
                title: 'Lifecycle & Assignment',
                icon: Icons.tune,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('Status: ', style: TextStyle(fontWeight: FontWeight.w500)),
                            StatusBadge(status: task.status),
                          ],
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: const Text('Change Status'),
                          onPressed: _isActionLoading ? null : _handleChangeStatus,
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('Priority: ', style: TextStyle(fontWeight: FontWeight.w500)),
                            PriorityBadge(priority: task.priority),
                          ],
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.flag_outlined, size: 16),
                          label: const Text('Change Priority'),
                          onPressed: _isActionLoading ? null : _handleChangePriority,
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_outline, size: 20, color: Color(0xFF1E88E5)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Assigned To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              if (_assignedUser != null) ...[
                                Text(
                                  _assignedUser!.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  _assignedUser!.email,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ] else if (task.assignedUserId != null) ...[
                                Text(
                                  'User ID: ${task.assignedUserId}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontFamily: 'monospace'),
                                ),
                              ] else ...[
                                Text(
                                  'No user assigned',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_pin_outlined, size: 16),
                          label: const Text('Reassign'),
                          onPressed: _isActionLoading ? null : _handleAssignTask,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // =============================================================
              // Section 5: Dates & Scheduling
              // =============================================================
              SectionCard(
                title: 'Dates & Scheduling',
                icon: Icons.calendar_month,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Due Date:', style: TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(AppDateFormat.formatDateTime(task.dueDate)),
                            if (task.dueDate != null) ...[
                              const SizedBox(height: 4),
                              DueDateBadge(dueDate: task.dueDate, isCompleted: isCompleted),
                            ],
                          ],
                        ),
                        if (!isCompleted)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.schedule, size: 16),
                            label: const Text('Postpone'),
                            onPressed: _isActionLoading ? null : _handlePostpone,
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Next Action Date:', style: TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(AppDateFormat.formatDateTime(task.nextActionDate)),
                          ],
                        ),
                        if (!isCompleted)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit_calendar, size: 16),
                                label: const Text('Update Next Action'),
                                onPressed: _isActionLoading ? null : _handleChangeNextActionDate,
                              ),
                              if (task.nextActionDate != null) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                                  tooltip: 'Clear Next Action Date',
                                  onPressed: _isActionLoading ? null : _handleClearNextActionDate,
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                    if (task.completedAt != null) ...[
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Completed At:', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            AppDateFormat.formatDateTime(task.completedAt),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // =============================================================
              // Section 6: Attempt Workflow & Max Attempts / Override
              // =============================================================
              SectionCard(
                title: 'Work Attempts Workflow',
                icon: Icons.repeat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Attempts: ${task.attemptCount} / ${task.maxAttempts}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isMaxed ? Colors.red.shade900 : null,
                          ),
                        ),
                        AttemptBadge(
                          attemptCount: task.attemptCount,
                          maxAttempts: task.maxAttempts,
                          isCompleted: isCompleted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (task.attemptCount / (task.maxAttempts > 0 ? task.maxAttempts : 1))
                            .clamp(0.0, 1.0),
                        minHeight: 8,
                        color: isMaxed ? Colors.red : Colors.blue,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (isMaxed && !isCompleted)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade800),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Max attempts reached. A standard attempt cannot be recorded; an authorized override with justification is required.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          icon: _isActionLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow),
                          label: const Text('Record Work Attempt'),
                          onPressed: _isActionLoading || isCompleted || isMaxed
                              ? null
                              : _handleNormalAttempt,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.shield_outlined),
                          label: const Text('Authorized Override'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isMaxed ? Colors.orange.shade900 : null,
                            side: isMaxed ? BorderSide(color: Colors.orange.shade800, width: 1.5) : null,
                          ),
                          onPressed: _isActionLoading || isCompleted
                              ? null
                              : _handleAuthorizedOverride,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // =============================================================
              // Section 7: Task Lifecycle Bar (Complete / Reopen)
              // =============================================================
              SectionCard(
                title: 'Task Lifecycle Actions',
                icon: Icons.check_circle_outline,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    if (!isCompleted)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Complete Task'),
                        onPressed: _isActionLoading ? null : _handleComplete,
                      )
                    else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey),
                        icon: const Icon(Icons.replay),
                        label: const Text('Reopen Task'),
                        onPressed: _isActionLoading ? null : _handleReopen,
                      ),
                  ],
                ),
              ),

              // =============================================================
              // Section 8: Reminders (Invariant: Never increments attempt count)
              // =============================================================
              SectionCard(
                title: 'Reminders (${_reminders.length})',
                icon: Icons.notifications_active_outlined,
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Reminder'),
                  onPressed: _isActionLoading ? null : _handleAddReminder,
                ),
                child: _reminders.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No reminders scheduled for this task.\n(Note: Creating and sending reminders will never increment attempt count).',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _reminders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final rem = _reminders[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              rem.isSent ? Icons.check_circle : Icons.alarm,
                              color: rem.isSent ? Colors.green : Colors.amber.shade800,
                            ),
                            title: Text(rem.message, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              'Remind at: ${AppDateFormat.formatDateTime(rem.remindAt)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (rem.isSent)
                                  const Chip(
                                    label: Text('SENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    backgroundColor: Color(0xFFE8F5E9),
                                  )
                                else
                                  FilledButton.tonal(
                                    onPressed: _isActionLoading ? null : () => _handleSendReminder(rem.id),
                                    child: const Text('Send Now', style: TextStyle(fontSize: 11)),
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                  tooltip: 'Delete Reminder',
                                  onPressed: _isActionLoading ? null : () => _handleDeleteReminder(rem.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // =============================================================
              // Section 9: Follow-ups
              // =============================================================
              SectionCard(
                title: 'Follow-ups (${_followUps.length})',
                icon: Icons.repeat_one,
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Schedule Follow-up'),
                  onPressed: _isActionLoading ? null : _handleAddFollowUp,
                ),
                child: _followUps.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No follow-ups scheduled for this task.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _followUps.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final f = _followUps[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              f.isCompleted ? Icons.check_circle : Icons.schedule,
                              color: f.isCompleted ? Colors.green : Colors.teal,
                            ),
                            title: Text(
                              f.notes ?? 'Scheduled Follow-up',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              'Scheduled: ${AppDateFormat.formatDate(f.scheduledAt)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (f.isCompleted)
                                  const Chip(
                                    label: Text('COMPLETED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    backgroundColor: Color(0xFFE8F5E9),
                                  )
                                else
                                  FilledButton.tonal(
                                    onPressed: _isActionLoading ? null : () => _handleCompleteFollowUp(f.id),
                                    child: const Text('Complete', style: TextStyle(fontSize: 11)),
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                  tooltip: 'Delete Follow-up',
                                  onPressed: _isActionLoading ? null : () => _handleDeleteFollowUp(f.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // =============================================================
              // Section 10: Chronological Audit History Timeline
              // =============================================================
              SectionCard(
                title: 'Audit History Timeline (${_history.length})',
                icon: Icons.history,
                child: _history.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No history records found for this task.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Filter Chips Bar
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildHistoryFilterChip('all', 'All (${_history.length})', theme),
                                const SizedBox(width: 6),
                                _buildHistoryFilterChip('status', 'Status', theme),
                                const SizedBox(width: 6),
                                _buildHistoryFilterChip('priority', 'Priority', theme),
                                const SizedBox(width: 6),
                                _buildHistoryFilterChip('assignment', 'Assignment', theme),
                                const SizedBox(width: 6),
                                _buildHistoryFilterChip('attempt', 'Attempts', theme),
                                const SizedBox(width: 6),
                                _buildHistoryFilterChip('scheduling', 'Scheduling', theme),
                                const SizedBox(width: 6),
                                _buildHistoryFilterChip('creation', 'Source', theme),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (_filteredHistory.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: Column(
                                  children: [
                                    const Icon(Icons.filter_list_off, size: 28, color: Colors.grey),
                                    const SizedBox(height: 6),
                                    Text(
                                      'No history records match "$_historyFilter".',
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() => _historyFilter = 'all'),
                                      child: const Text('Show All Events', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredHistory.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = _filteredHistory[index];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: item.actionColor.withOpacity(0.15),
                                            child: Icon(
                                              item.actionIcon,
                                              size: 14,
                                              color: item.actionColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item.formattedAction,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ),
                                          Text(
                                            AppDateFormat.formatDateTime(item.createdAt),
                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.person_outline, size: 12, color: theme.colorScheme.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            'By ${item.displayActor}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (item.actorEmail != null && item.actorEmail!.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              '(${item.actorEmail})',
                                              style: const TextStyle(fontSize: 10, color: Colors.black45),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (item.reason != null && item.reason!.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amber.shade300, width: 0.5),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.notes, size: 12, color: Colors.amber.shade900),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  'Reason: ${item.reason}',
                                                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (item.hasDiff) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Change: ${item.formattedOldValue} → ${item.formattedNewValue}',
                                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryFilterChip(String category, String label, ThemeData theme) {
    final isSelected = _historyFilter == category;
    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        ),
      ),
      selectedColor: theme.colorScheme.primary,
      checkmarkColor: theme.colorScheme.onPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) {
        setState(() {
          _historyFilter = category;
        });
      },
    );
  }
}
