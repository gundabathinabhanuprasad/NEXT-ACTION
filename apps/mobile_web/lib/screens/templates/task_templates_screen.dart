import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/template/task_template_models.dart';
import '../../services/client/client_service.dart';
import '../../services/task/task_service.dart';
import '../../services/template/task_template_service.dart';
import '../../services/user/user_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';
import 'task_template_create_screen.dart';

/// Screen listing reusable Task Templates with search, filtering, and instant task generation.
class TaskTemplatesScreen extends StatefulWidget {
  final TaskTemplateService templateService;
  final TaskService taskService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final UserService? userService;

  const TaskTemplatesScreen({
    super.key,
    required this.templateService,
    required this.taskService,
    this.clientService,
    this.workflowService,
    this.userService,
  });

  @override
  State<TaskTemplatesScreen> createState() => _TaskTemplatesScreenState();
}

class _TaskTemplatesScreenState extends State<TaskTemplatesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isLoading = false;
  String? _errorMessage;

  List<TaskTemplate> _templates = [];
  int _total = 0;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool? _filterIsActive;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.templateService.getTemplates(
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        isActive: _filterIsActive,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          _templates = response.items;
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
          _errorMessage = 'Failed to load templates. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _currentPage = 1;
      _loadTemplates();
    });
  }

  Future<void> _useTemplate(TaskTemplate template) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final createdTask = await widget.templateService.createTaskFromTemplate(
        templateId: template.id,
      );

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Task "${createdTask.title}" created from template!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TaskDetailScreen(
              taskId: createdTask.id,
              taskService: widget.taskService,
              clientService: widget.clientService,
              workflowService: widget.workflowService,
              userService: widget.userService,
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: ${e.message}'), backgroundColor: Colors.red),
      );
    } catch (_) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Failed to instantiate task from template'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteTemplate(TaskTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "${template.name}"?'),
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
        await widget.templateService.deleteTemplate(template.id);
        _loadTemplates();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete template: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? 'Task Templates ($_total)' : 'Task Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadTemplates,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => TaskTemplateCreateScreen(
                templateService: widget.templateService,
                clientService: widget.clientService,
                workflowService: widget.workflowService,
                userService: widget.userService,
              ),
            ),
          );
          if (created == true) _loadTemplates();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search templates by name, keyword...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _currentPage = 1;
                                _loadTemplates();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: Text(_filterIsActive == true ? 'Active Only' : 'All Templates'),
                  selected: _filterIsActive == true,
                  onSelected: (selected) {
                    setState(() {
                      _filterIsActive = selected ? true : null;
                      _currentPage = 1;
                    });
                    _loadTemplates();
                  },
                ),
              ],
            ),
          ),

          if (_isLoading) const LinearProgressIndicator(),

          // Body Content
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
                          ElevatedButton(onPressed: _loadTemplates, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : _templates.isEmpty && !_isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.bookmark_border, size: 56, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No task templates found.',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            const Text('Create standard blueprints to accelerate routine task creation.'),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final created = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TaskTemplateCreateScreen(
                                      templateService: widget.templateService,
                                      clientService: widget.clientService,
                                      workflowService: widget.workflowService,
                                      userService: widget.userService,
                                    ),
                                  ),
                                );
                                if (created == true) _loadTemplates();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create First Template'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        itemCount: _templates.length,
                        itemBuilder: (context, index) {
                          final template = _templates[index];
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
                                              template.name,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            if (template.subjectLine != null && template.subjectLine!.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4.0),
                                                child: Text(
                                                  'Subject: ${template.subjectLine}',
                                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      PriorityBadge(priority: template.priority),
                                      const SizedBox(width: 8),
                                      if (!template.isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Inactive', style: TextStyle(fontSize: 11)),
                                        ),
                                    ],
                                  ),

                                  if (template.description != null && template.description!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      template.description!,
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
                                      if (template.defaultDueOffsetDays != null)
                                        Chip(
                                          avatar: const Icon(Icons.event_outlined, size: 16),
                                          label: Text('Due: +${template.defaultDueOffsetDays}d'),
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      if (template.defaultNextActionOffsetDays != null)
                                        Chip(
                                          avatar: const Icon(Icons.alarm_on, size: 16),
                                          label: Text('Action: +${template.defaultNextActionOffsetDays}d'),
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      Chip(
                                        avatar: const Icon(Icons.repeat, size: 16),
                                        label: Text('Max: ${template.maxAttempts}'),
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
                                        'Created ${template.createdAt.toLocal().toString().split(' ')[0]}',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 20),
                                            tooltip: 'Edit Template',
                                            onPressed: () async {
                                              final updated = await Navigator.push<bool>(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => TaskTemplateCreateScreen(
                                                    templateService: widget.templateService,
                                                    clientService: widget.clientService,
                                                    workflowService: widget.workflowService,
                                                    userService: widget.userService,
                                                    templateToEdit: template,
                                                  ),
                                                ),
                                              );
                                              if (updated == true) _loadTemplates();
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                            tooltip: 'Delete Template',
                                            onPressed: () => _deleteTemplate(template),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            onPressed: template.isActive ? () => _useTemplate(template) : null,
                                            icon: const Icon(Icons.play_arrow, size: 18),
                                            label: const Text('Use Template'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                          ),
                                        ],
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
