import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/client/client_models.dart';
import '../../models/template/task_template_models.dart';
import '../../models/workflow/workflow_models.dart';
import '../../services/client/client_service.dart';
import '../../services/template/task_template_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';

/// Screen allowing creation or editing of a reusable TaskTemplate blueprint.
class TaskTemplateCreateScreen extends StatefulWidget {
  final TaskTemplateService templateService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;
  final TaskTemplate? templateToEdit;

  const TaskTemplateCreateScreen({
    super.key,
    required this.templateService,
    this.clientService,
    this.workflowService,
    this.userService,
    this.templateToEdit,
  });

  @override
  State<TaskTemplateCreateScreen> createState() => _TaskTemplateCreateScreenState();
}

class _TaskTemplateCreateScreenState extends State<TaskTemplateCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _subjectLineController;
  late final TextEditingController _maxAttemptsController;
  late final TextEditingController _dueOffsetController;
  late final TextEditingController _nextActionOffsetController;

  late final ClientService _clientService;
  late final WorkflowService _workflowService;
  late final UserService _userService;

  List<Client> _clients = [];
  List<Workflow> _workflows = [];
  List<User> _users = [];
  bool _isLoadingAssociations = false;

  String? _selectedClientId;
  String? _selectedWorkflowId;
  String? _selectedAssignedUserId;

  String _priority = 'medium';
  bool _isActive = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.templateToEdit != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.templateToEdit;
    _nameController = TextEditingController(text: edit?.name ?? '');
    _descriptionController = TextEditingController(text: edit?.description ?? '');
    _subjectLineController = TextEditingController(text: edit?.subjectLine ?? '');
    _maxAttemptsController = TextEditingController(text: edit != null ? edit.maxAttempts.toString() : '2');
    _dueOffsetController = TextEditingController(text: edit?.defaultDueOffsetDays?.toString() ?? '');
    _nextActionOffsetController = TextEditingController(text: edit?.defaultNextActionOffsetDays?.toString() ?? '');

    _priority = edit?.priority ?? 'medium';
    _isActive = edit?.isActive ?? true;
    _selectedClientId = edit?.clientId;
    _selectedWorkflowId = edit?.workflowId;
    _selectedAssignedUserId = edit?.assignedUserId;

    _clientService = widget.clientService ?? ClientService(apiClient: widget.templateService.apiClient);
    _workflowService = widget.workflowService ?? WorkflowService(apiClient: widget.templateService.apiClient);
    _userService = widget.userService ?? UserService(apiClient: widget.templateService.apiClient);

    _loadAssociations();
  }

  Future<void> _loadAssociations() async {
    setState(() => _isLoadingAssociations = true);
    try {
      final results = await Future.wait([
        _clientService.getClients(pageSize: 100),
        _workflowService.getWorkflows(pageSize: 100),
        _userService.getUsers(isActive: true, pageSize: 100),
      ]);
      if (mounted) {
        setState(() {
          _clients = (results[0] as ClientListResponse).items;
          _workflows = (results[1] as WorkflowListResponse).items;
          _users = (results[2] as UserListResponse).items;
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
    _nameController.dispose();
    _descriptionController.dispose();
    _subjectLineController.dispose();
    _maxAttemptsController.dispose();
    _dueOffsetController.dispose();
    _nextActionOffsetController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final maxAttempts = int.tryParse(_maxAttemptsController.text.trim()) ?? 2;
    final dueOffset = _dueOffsetController.text.trim().isNotEmpty
        ? int.tryParse(_dueOffsetController.text.trim())
        : null;
    final nextActionOffset = _nextActionOffsetController.text.trim().isNotEmpty
        ? int.tryParse(_nextActionOffsetController.text.trim())
        : null;

    try {
      if (_isEditing) {
        await widget.templateService.updateTemplate(
          templateId: widget.templateToEdit!.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          subjectLine: _subjectLineController.text.trim().isNotEmpty ? _subjectLineController.text.trim() : null,
          clientId: _selectedClientId,
          workflowId: _selectedWorkflowId,
          assignedUserId: _selectedAssignedUserId,
          priority: _priority,
          maxAttempts: maxAttempts,
          defaultDueOffsetDays: dueOffset,
          defaultNextActionOffsetDays: nextActionOffset,
          isActive: _isActive,
        );
      } else {
        await widget.templateService.createTemplate(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          subjectLine: _subjectLineController.text.trim().isNotEmpty ? _subjectLineController.text.trim() : null,
          clientId: _selectedClientId,
          workflowId: _selectedWorkflowId,
          assignedUserId: _selectedAssignedUserId,
          priority: _priority,
          maxAttempts: maxAttempts,
          defaultDueOffsetDays: dueOffset,
          defaultNextActionOffsetDays: nextActionOffset,
          isActive: _isActive,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isSubmitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Task Template' : 'New Task Template'),
      ),
      body: _isLoadingAssociations
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: ErrorStateWidget(
                              message: _errorMessage!,
                              onRetry: _loadAssociations,
                            ),
                          ),

                        // Template Name
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Template Name *',
                            hintText: 'e.g., Standard Client Onboarding',
                            prefixIcon: Icon(Icons.bookmark_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a template name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Subject Line
                        TextFormField(
                          controller: _subjectLineController,
                          decoration: const InputDecoration(
                            labelText: 'Default Email Subject Line',
                            hintText: 'e.g., Welcome to NextAction Onboarding',
                            prefixIcon: Icon(Icons.subject),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Description
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Template Description / Checklist',
                            hintText: 'Detail standard steps to be copied into instantiated tasks...',
                            prefixIcon: Icon(Icons.description_outlined),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Priority Selector
                        Text('Default Priority', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: ['low', 'medium', 'high', 'urgent'].map((p) {
                            return ChoiceChip(
                              label: Text(p.toUpperCase()),
                              selected: _priority == p,
                              onSelected: (selected) {
                                if (selected) setState(() => _priority = p);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Offsets Row
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _dueOffsetController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Due In (Days)',
                                  hintText: 'e.g., 7',
                                  prefixIcon: Icon(Icons.event_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _nextActionOffsetController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Next Action In (Days)',
                                  hintText: 'e.g., 2',
                                  prefixIcon: Icon(Icons.alarm_on),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Max Attempts
                        TextFormField(
                          controller: _maxAttemptsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Attempts *',
                            hintText: '2',
                            prefixIcon: Icon(Icons.repeat),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Please enter max attempts';
                            final parsed = int.tryParse(value.trim());
                            if (parsed == null || parsed < 1) return 'Max attempts must be >= 1';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Client Selector
                        DropdownButtonFormField<String>(
                          value: _selectedClientId,
                          decoration: const InputDecoration(
                            labelText: 'Default Client (Optional)',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('None / Any Client')),
                            ..._clients.map((c) => DropdownMenuItem<String>(
                                  value: c.id,
                                  child: Text('${c.name}${c.company != null ? " (${c.company})" : ""}'),
                                )),
                          ],
                          onChanged: (val) => setState(() => _selectedClientId = val),
                        ),
                        const SizedBox(height: 16),

                        // Workflow Selector
                        DropdownButtonFormField<String>(
                          value: _selectedWorkflowId,
                          decoration: const InputDecoration(
                            labelText: 'Default Workflow (Optional)',
                            prefixIcon: Icon(Icons.account_tree_outlined),
                          ),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('None / Any Workflow')),
                            ..._workflows.map((w) => DropdownMenuItem<String>(
                                  value: w.id,
                                  child: Text(w.name),
                                )),
                          ],
                          onChanged: (val) => setState(() => _selectedWorkflowId = val),
                        ),
                        const SizedBox(height: 16),

                        // Assignee Selector
                        DropdownButtonFormField<String>(
                          value: _selectedAssignedUserId,
                          decoration: const InputDecoration(
                            labelText: 'Default Assignee (Optional)',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('Unassigned')),
                            ..._users.map((u) => DropdownMenuItem<String>(
                                  value: u.id,
                                  child: Text('${u.name} (${u.email})'),
                                )),
                          ],
                          onChanged: (val) => setState(() => _selectedAssignedUserId = val),
                        ),
                        const SizedBox(height: 16),

                        // Active Switch
                        SwitchListTile(
                          title: const Text('Active Template'),
                          subtitle: const Text('Inactive templates cannot be used to generate tasks'),
                          value: _isActive,
                          onChanged: (val) => setState(() => _isActive = val),
                        ),
                        const SizedBox(height: 28),

                        // Action Submit Button
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_isEditing ? 'Save Template Changes' : 'Create Task Template'),
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
