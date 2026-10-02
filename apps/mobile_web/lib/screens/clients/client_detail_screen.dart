import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/client/client_models.dart';
import '../../models/task/task_models.dart';
import '../../services/client/client_service.dart';
import '../../services/task/task_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_create_screen.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_list_screen.dart';

/// Screen displaying complete details for a Client, including related tasks,
/// task counts, editing, and task creation.
class ClientDetailScreen extends StatefulWidget {
  final String clientId;
  final Client? initialClient;
  final ClientService clientService;
  final TaskService taskService;

  const ClientDetailScreen({
    super.key,
    required this.clientId,
    this.initialClient,
    required this.clientService,
    required this.taskService,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  Client? _client;
  List<Task> _relatedTasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = widget.initialClient;
    _loadClientAndTasks();
  }

  Future<void> _loadClientAndTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        widget.clientService.getClient(widget.clientId),
        widget.taskService.getTasks(clientId: widget.clientId, pageSize: 100),
      ]);

      if (mounted) {
        setState(() {
          _client = results[0] as Client;
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
          _errorMessage = 'Failed to load client details: $e';
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
    ).then((_) => _loadClientAndTasks());
  }

  void _createTaskForClient() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskCreateScreen(
          taskService: widget.taskService,
          initialClientId: widget.clientId,
        ),
      ),
    );

    if (created == true) {
      _loadClientAndTasks();
    }
  }

  Future<void> _showEditClientDialog() async {
    if (_client == null) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _client!.name);
    final companyController = TextEditingController(text: _client!.company ?? '');
    final emailController = TextEditingController(text: _client!.email ?? '');
    final phoneController = TextEditingController(text: _client!.phone ?? '');
    final notesController = TextEditingController(text: _client!.notes ?? '');
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
                  Text('Edit Client'),
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
                            labelText: 'Client / Contact Name *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: companyController,
                          decoration: const InputDecoration(
                            labelText: 'Company / Organization',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          maxLines: 2,
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
                            await widget.clientService.updateClient(
                              widget.clientId,
                              ClientUpdateRequest(
                                name: nameController.text.trim(),
                                company: companyController.text.trim().isNotEmpty
                                    ? companyController.text.trim()
                                    : null,
                                email: emailController.text.trim().isNotEmpty
                                    ? emailController.text.trim()
                                    : null,
                                phone: phoneController.text.trim().isNotEmpty
                                    ? phoneController.text.trim()
                                    : null,
                                notes: notesController.text.trim().isNotEmpty
                                    ? notesController.text.trim()
                                    : null,
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
                              dialogError = 'Failed to update client: $e';
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
            content: Text('Client updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadClientAndTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = _client;

    final pendingTasks = _relatedTasks.where((t) => t.status == 'pending').length;
    final inProgressTasks = _relatedTasks.where((t) => t.status == 'in_progress').length;
    final completedTasks = _relatedTasks.where((t) => t.status == 'completed').length;
    final totalTasks = _relatedTasks.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(client != null ? client.name : 'Client Detail'),
        actions: [
          if (client != null)
            IconButton(
              tooltip: 'Edit Client',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _showEditClientDialog,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadClientAndTasks,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_task),
        label: const Text('New Task for Client'),
        onPressed: _createTaskForClient,
      ),
      body: _isLoading && client == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading client information...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadClientAndTasks,
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
                                    onPressed: _loadClientAndTasks,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Client Information Card
                        if (client != null)
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
                                        radius: 26,
                                        backgroundColor: theme.colorScheme.primaryContainer,
                                        foregroundColor: theme.colorScheme.primary,
                                        child: Text(
                                          client.name.isNotEmpty ? client.name[0].toUpperCase() : 'C',
                                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              client.name,
                                              style: theme.textTheme.titleLarge?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (client.company != null && client.company!.isNotEmpty)
                                              Text(
                                                client.company!,
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  if (client.email != null && client.email!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.email_outlined, size: 18, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(client.email!),
                                        ],
                                      ),
                                    ),
                                  if (client.phone != null && client.phone!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.phone_outlined, size: 18, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(client.phone!),
                                        ],
                                      ),
                                    ),
                                  if (client.notes != null && client.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Notes',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(client.notes!),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 20),

                        // Task Summary Metrics
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
                              'Related Tasks ($totalTasks)',
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
                                          clientService: widget.clientService,
                                          initialClientId: widget.clientId,
                                        ),
                                      ),
                                    ).then((_) => _loadClientAndTasks());
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
                                  onPressed: _createTaskForClient,
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
                                    Icon(Icons.assignment_outlined, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No tasks assigned to this client yet',
                                      style: TextStyle(color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.tonalIcon(
                                      onPressed: _createTaskForClient,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Create First Task'),
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
