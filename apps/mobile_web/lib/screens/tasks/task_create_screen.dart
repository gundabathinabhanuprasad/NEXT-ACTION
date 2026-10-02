import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/task/task_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../models/template/task_template_models.dart';
import '../../services/client/client_service.dart';
import '../../services/task/task_service.dart';
import '../../services/template/task_template_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/settings_provider.dart';

/// Screen allowing creation of a real new Task directly against FastAPI and PostgreSQL,
/// with integrated Client, Workflow, and Team User Assignee selection.
class TaskCreateScreen extends StatefulWidget {
  final TaskService taskService;
  final TaskTemplateService? templateService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;
  final String? initialClientId;
  final String? initialWorkflowId;
  final String? initialAssignedUserId;
  final TaskTemplate? initialTemplate;
  final String? initialPriority;
  final int? initialMaxAttempts;
  final SettingsProvider? settingsProvider;

  const TaskCreateScreen({
    super.key,
    required this.taskService,
    this.templateService,
    this.clientService,
    this.workflowService,
    this.userService,
    this.initialClientId,
    this.initialWorkflowId,
    this.initialAssignedUserId,
    this.initialTemplate,
    this.initialPriority,
    this.initialMaxAttempts,
    this.settingsProvider,
  });

  @override
  State<TaskCreateScreen> createState() => _TaskCreateScreenState();
}

class _TaskCreateScreenState extends State<TaskCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _subjectLineController = TextEditingController();
  late final TextEditingController _maxAttemptsController;

  late final ClientService _clientService;
  late final WorkflowService _workflowService;
  late final UserService _userService;
  late final TaskTemplateService _templateService;

  List<Client> _clients = [];
  List<Workflow> _workflows = [];
  List<User> _users = [];
  List<TaskTemplate> _templates = [];
  bool _isLoadingAssociations = false;

  String? _selectedClientId;
  String? _selectedWorkflowId;
  String? _selectedAssignedUserId;
  String? _appliedTemplateId;

  late String _priority;
  DateTime? _selectedDueDate;
  DateTime? _selectedNextActionDate;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final defaultPriority = widget.initialPriority ?? widget.settingsProvider?.settings?.defaultTaskPriority ?? 'medium';
    _priority = defaultPriority;

    final defaultAttempts = widget.initialMaxAttempts ?? widget.settingsProvider?.settings?.defaultMaxAttempts ?? 2;
    _maxAttemptsController = TextEditingController(text: defaultAttempts.toString());

    _clientService = widget.clientService ?? ClientService(apiClient: widget.taskService.apiClient);
    _workflowService = widget.workflowService ?? WorkflowService(apiClient: widget.taskService.apiClient);
    _userService = widget.userService ?? UserService(apiClient: widget.taskService.apiClient);
    _templateService = widget.templateService ?? TaskTemplateService(apiClient: widget.taskService.apiClient);
    _selectedClientId = widget.initialClientId;
    _selectedWorkflowId = widget.initialWorkflowId;
    _selectedAssignedUserId = widget.initialAssignedUserId;

    if (widget.initialTemplate != null) {
      _applyTemplate(widget.initialTemplate!);
    }

    _loadAssociations();
  }

  void _applyTemplate(TaskTemplate t) {
    setState(() {
      _appliedTemplateId = t.id;
      _titleController.text = t.name;
      if (t.description != null) _descriptionController.text = t.description!;
      if (t.subjectLine != null) _subjectLineController.text = t.subjectLine!;
      _priority = t.priority;
      _maxAttemptsController.text = t.maxAttempts.toString();
      if (t.clientId != null) _selectedClientId = t.clientId;
      if (t.workflowId != null) _selectedWorkflowId = t.workflowId;
      if (t.assignedUserId != null) _selectedAssignedUserId = t.assignedUserId;
      if (t.defaultDueOffsetDays != null) {
        _selectedDueDate = DateTime.now().add(Duration(days: t.defaultDueOffsetDays!));
      }
      if (t.defaultNextActionOffsetDays != null) {
        _selectedNextActionDate = DateTime.now().add(Duration(days: t.defaultNextActionOffsetDays!));
      }
    });
  }

  Future<void> _loadAssociations() async {
    setState(() => _isLoadingAssociations = true);
    try {
      final results = await Future.wait([
        _clientService.getClients(pageSize: 100),
        _workflowService.getWorkflows(pageSize: 100),
        _userService.getUsers(isActive: true, pageSize: 100),
        _templateService.getTemplates(isActive: true, pageSize: 100),
      ]);
      if (mounted) {
        setState(() {
          _clients = (results[0] as ClientListResponse).items;
          _workflows = (results[1] as WorkflowListResponse).items;
          _users = (results[2] as UserListResponse).items;
          _templates = (results[3] as TaskTemplateListResponse).items;
          _isLoadingAssociations = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAssociations = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _subjectLineController.dispose();
    _maxAttemptsController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final maxAttempts = int.tryParse(_maxAttemptsController.text.trim()) ?? 2;
    if (maxAttempts < 1) {
      setState(() {
        _errorMessage = 'Max attempts must be at least 1';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final request = TaskCreateRequest(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      subjectLine: _subjectLineController.text.trim().isNotEmpty
          ? _subjectLineController.text.trim()
          : null,
      clientId: _selectedClientId,
      workflowId: _selectedWorkflowId,
      assignedUserId: _selectedAssignedUserId,
      templateId: _appliedTemplateId,
      priority: _priority,
      dueDate: _selectedDueDate,
      nextActionDate: _selectedNextActionDate,
      maxAttempts: maxAttempts,
    );

    try {
      await widget.taskService.createTask(request);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to create task: $e';
        });
      }
    }
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDueDate ?? DateTime.now()),
      );
      if (time != null) {
        setState(() {
          _selectedDueDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _selectNextActionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedNextActionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedNextActionDate ?? DateTime.now()),
      );
      if (time != null) {
        setState(() {
          _selectedNextActionDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Task'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    ErrorStateWidget(
                      message: _errorMessage!,
                      onRetry: _loadAssociations,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_templates.isNotEmpty) ...[
                    Card(
                      color: Colors.blue.shade50,
                      margin: const EdgeInsets.only(bottom: 20.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_outline, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _appliedTemplateId,
                                  hint: const Text('Load settings from a Template...'),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Custom Blank Task')),
                                    ..._templates.map(
                                      (t) => DropdownMenuItem(
                                        value: t.id,
                                        child: Text('Template: ${t.name}'),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val == null) {
                                      setState(() => _appliedTemplateId = null);
                                    } else {
                                      final selected = _templates.firstWhere((t) => t.id == val);
                                      _applyTemplate(selected);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Title Field (Mandatory)
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Task Title *',
                      hintText: 'e.g., Follow up on contract review',
                      prefixIcon: Icon(Icons.title),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Task title is required';
                      }
                      if (value.trim().length > 255) {
                        return 'Title must be 255 characters or fewer';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Subject Line (Optional)
                  TextFormField(
                    controller: _subjectLineController,
                    decoration: const InputDecoration(
                      labelText: 'Subject Line (Optional)',
                      hintText: 'Email / Messaging subject summary',
                      prefixIcon: Icon(Icons.subject),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description Field (Optional)
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'Detailed requirements, context, or meeting notes...',
                      prefixIcon: Icon(Icons.notes),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Client & Workflow Selectors
                  if (_isLoadingAssociations)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: LinearProgressIndicator()),
                    )
                  else ...[
                    Row(
                      children: [
                        // Client Selector
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            value: _selectedClientId,
                            decoration: InputDecoration(
                              labelText: 'Client',
                              prefixIcon: const Icon(Icons.business_outlined),
                              border: const OutlineInputBorder(),
                              suffixIcon: _selectedClientId != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      tooltip: 'Clear Client',
                                      onPressed: () => setState(() => _selectedClientId = null),
                                    )
                                  : null,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No Client (Standalone)'),
                              ),
                              ..._clients.map((c) => DropdownMenuItem<String?>(
                                    value: c.id,
                                    child: Text(
                                      c.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                            ],
                            onChanged: (val) => setState(() => _selectedClientId = val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Workflow Selector
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            value: _selectedWorkflowId,
                            decoration: InputDecoration(
                              labelText: 'Workflow',
                              prefixIcon: const Icon(Icons.account_tree_outlined),
                              border: const OutlineInputBorder(),
                              suffixIcon: _selectedWorkflowId != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      tooltip: 'Clear Workflow',
                                      onPressed: () => setState(() => _selectedWorkflowId = null),
                                    )
                                  : null,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No Workflow (Direct Task)'),
                              ),
                              ..._workflows.map((w) => DropdownMenuItem<String?>(
                                    value: w.id,
                                    child: Text(
                                      w.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                            ],
                            onChanged: (val) => setState(() => _selectedWorkflowId = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // User Assignee Selector
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      value: _selectedAssignedUserId,
                      decoration: InputDecoration(
                        labelText: 'Assigned Team Member',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: _selectedAssignedUserId != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: 'Clear Assignee',
                                onPressed: () => setState(() => _selectedAssignedUserId = null),
                              )
                            : null,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Unassigned (No assignee)'),
                        ),
                        ..._users.map((u) => DropdownMenuItem<String?>(
                              value: u.id,
                              child: Text(
                                '${u.name} (${u.email})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (val) => setState(() => _selectedAssignedUserId = val),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Priority and Max Attempts Row
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _priority,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                            prefixIcon: Icon(Icons.flag_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(value: 'medium', child: Text('Medium')),
                            DropdownMenuItem(value: 'high', child: Text('High')),
                            DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _priority = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _maxAttemptsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Attempts',
                            hintText: '2',
                            prefixIcon: Icon(Icons.repeat),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Max attempts required';
                            }
                            final n = int.tryParse(value.trim());
                            if (n == null || n < 1) {
                              return 'Must be >= 1';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Dates Row
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: const Icon(Icons.event_outlined),
                          title: Text(
                            _selectedDueDate != null
                                ? 'Due: ${AppDateFormat.formatDateTime(_selectedDueDate)}'
                                : 'Set Due Date',
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: _selectedDueDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() => _selectedDueDate = null),
                                )
                              : const Icon(Icons.calendar_month, size: 20),
                          onTap: _selectDueDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: const Icon(Icons.alarm),
                          title: Text(
                            _selectedNextActionDate != null
                                ? 'Next: ${AppDateFormat.formatDateTime(_selectedNextActionDate)}'
                                : 'Next Action Date',
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: _selectedNextActionDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() => _selectedNextActionDate = null),
                                )
                              : const Icon(Icons.calendar_today, size: 20),
                          onTap: _selectNextActionDate,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),
                  FilledButton.icon(
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSubmitting ? 'Creating Task...' : 'Create Task'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isSubmitting ? null : _handleCreate,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
