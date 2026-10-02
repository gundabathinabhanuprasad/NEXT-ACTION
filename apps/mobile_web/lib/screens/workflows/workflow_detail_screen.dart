import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/task/task_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../services/task/task_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_create_screen.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_list_screen.dart';

/// Screen displaying complete details for a Workflow, including status breakdown,
/// related tasks, editing, and task creation.
class WorkflowDetailScreen extends StatefulWidget {
  final String workflowId;
  final Workflow? initialWorkflow;
  final WorkflowService workflowService;
  final TaskService taskService;

  const WorkflowDetailScreen({
    super.key,
    required this.workflowId,
    this.initialWorkflow,
    required this.workflowService,
    required this.taskService,
  });

  @override
  State<WorkflowDetailScreen> createState() => _WorkflowDetailScreenState();
}

class _WorkflowDetailScreenState extends State<WorkflowDetailScreen> {
  Workflow? _workflow;
  List<Task> _relatedTasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _workflow = widget.initialWorkflow;
    _loadWorkflowAndTasks();
  }

  Future<void> _loadWorkflowAndTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        widget.workflowService.getWorkflow(widget.workflowId),
        widget.taskService.getTasks(workflowId: widget.workflowId, pageSize: 100),
      ]);

      if (mounted) {
        setState(() {
          _workflow = results[0] as Workflow;
          _relatedTasks = (results[1] as TaskListResponse).items;
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
          _errorMessage = 'Failed to load workflow details: $e';
        });
      }
    }
  }

  void _openTaskDetail(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          taskId: task.id,
          initialTask: task,
          taskService: widget.taskService,
        ),
      ),
    ).then((_) => _loadWorkflowAndTasks());
  }

  void _createTaskInWorkflow() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskCreateScreen(
          taskService: widget.taskService,
          initialWorkflowId: widget.workflowId,
        ),
      ),
    );

    if (created == true) {
      _loadWorkflowAndTasks();
    }
  }

  Future<void> _showEditWorkflowDialog() async {
    if (_workflow == null) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _workflow!.name);
    final descController = TextEditingController(text: _workflow!.description ?? '');
    bool isActive = _workflow!.isActive;
    bool isSaving = false;
    String? dialogError;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.edit, color: Color(0xFF1E88E5)),
                  SizedBox(width: 8),
                  Text('Edit Workflow'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (dialogError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              dialogError!,
                              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Workflow Name *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Workflow name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descController,
                          decoration: const InputDecoration(
                            labelText: 'Description / Process Notes',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.description_outlined),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Active Workflow'),
                          value: isActive,
                          onChanged: (val) => setDialogState(() => isActive = val),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });
                          try {
                            await widget.workflowService.updateWorkflow(
                              widget.workflowId,
                              WorkflowUpdateRequest(
                                name: nameController.text.trim(),
                                description: descController.text.trim().isNotEmpty
                                    ? descController.text.trim()
                                    : null,
                                isActive: isActive,
                              ),
                            );
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx, true);
                            }
                          } on ApiException catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              dialogError = e.message;
                            });
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              dialogError = 'Failed to update workflow: $e';
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workflow updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadWorkflowAndTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workflow = _workflow;

    final pendingTasks = _relatedTasks.where((t) => t.status == 'pending').length;
    final inProgressTasks = _relatedTasks.where((t) => t.status == 'in_progress').length;
    final completedTasks = _relatedTasks.where((t) => t.status == 'completed').length;
    final totalTasks = _relatedTasks.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(workflow != null ? workflow.name : 'Workflow Detail'),
        actions: [
          if (workflow != null)
            IconButton(
              tooltip: 'Edit Workflow',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _showEditWorkflowDialog,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadWorkflowAndTasks,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_task),
        label: const Text('New Task in Workflow'),
        onPressed: _createTaskInWorkflow,
      ),
      body: _isLoading && workflow == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading workflow information...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadWorkflowAndTasks,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null) ...[
                          Card(
                            color: Colors.red.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(color: Colors.red.shade900),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _loadWorkflowAndTasks,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Workflow Information Card
                        if (workflow != null)
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: workflow.isActive
                                            ? Colors.teal.shade50
                                            : Colors.grey.shade200,
                                        foregroundColor: workflow.isActive
                                            ? Colors.teal.shade800
                                            : Colors.grey.shade600,
                                        child: Icon(
                                          workflow.isActive
                                              ? Icons.account_tree
                                              : Icons.account_tree_outlined,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              workflow.name,
                                              style: theme.textTheme.titleLarge?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: workflow.isActive
                                                    ? Colors.green.shade50
                                                    : Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: workflow.isActive
                                                      ? Colors.green.shade300
                                                      : Colors.grey.shade400,
                                                ),
                                              ),
                                              child: Text(
                                                workflow.isActive ? 'Active Pipeline' : 'Inactive Pipeline',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: workflow.isActive
                                                      ? Colors.green.shade800
                                                      : Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (workflow.description != null &&
                                      workflow.description!.isNotEmpty) ...[
                                    const Divider(height: 24),
                                    Text(
                                      'Description',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      workflow.description!,
                                      style: TextStyle(color: Colors.grey.shade800, height: 1.4),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 20),

                        // Task Breakdown Metrics
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                theme,
                                label: 'Total Tasks',
                                value: '$totalTasks',
                                icon: Icons.assignment_outlined,
                                color: const Color(0xFF1E88E5),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                theme,
                                label: 'Pending',
                                value: '$pendingTasks',
                                icon: Icons.pending_actions,
                                color: Colors.orange.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                theme,
                                label: 'In Progress',
                                value: '$inProgressTasks',
                                icon: Icons.play_circle_outline,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                theme,
                                label: 'Completed',
                                value: '$completedTasks',
                                icon: Icons.check_circle_outline,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Related Tasks Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Workflow Tasks ($totalTasks)',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TaskListScreen(
                                          taskService: widget.taskService,
                                          workflowService: widget.workflowService,
                                          initialWorkflowId: widget.workflowId,
                                        ),
                                      ),
                                    ).then((_) => _loadWorkflowAndTasks());
                                  },
                                  icon: const Icon(Icons.list_alt, size: 16),
                                  label: const Text('View All Tasks'),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: _createTaskInWorkflow,
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Task'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_relatedTasks.isEmpty)
                          Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.account_tree_outlined, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No tasks assigned to this workflow yet',
                                      style: TextStyle(color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.tonalIcon(
                                      onPressed: _createTaskInWorkflow,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Task to Workflow'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _relatedTasks.length,
                            itemBuilder: (context, index) {
                              final task = _relatedTasks[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: StatusBadge(status: task.status),
                                  title: Text(
                                    task.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Row(
                                    children: [
                                      PriorityBadge(priority: task.priority),
                                      const SizedBox(width: 8),
                                      if (task.dueDate != null)
                                        Text(
                                          'Due: ${task.dueDate!.toLocal().toString().substring(0, 10)}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openTaskDetail(task),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
