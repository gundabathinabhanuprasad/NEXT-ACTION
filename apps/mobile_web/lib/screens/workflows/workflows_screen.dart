import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/workflow/workflow_models.dart';
import '../../services/task/task_service.dart';
import '../../services/workflow/workflow_service.dart';
import '../../widgets/common_widgets.dart';
import 'workflow_detail_screen.dart';

/// Screen displaying all workflows from PostgreSQL with search, status filtering,
/// pull-to-refresh, creation, and detail navigation.
class WorkflowsScreen extends StatefulWidget {
  final WorkflowService workflowService;
  final TaskService taskService;

  const WorkflowsScreen({
    super.key,
    required this.workflowService,
    required this.taskService,
  });

  @override
  State<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends State<WorkflowsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Workflow> _workflows = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool? _activeFilter; // null = all, true = active, false = inactive

  @override
  void initState() {
    super.initState();
    _fetchWorkflows();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchWorkflows() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.workflowService.getWorkflows(
        isActive: _activeFilter,
      );
      if (mounted) {
        setState(() {
          _workflows = response.items;
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
          _errorMessage = 'Failed to load workflows: $e';
        });
      }
    }
  }

  List<Workflow> get _filteredWorkflows {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _workflows;
    return _workflows.where((w) {
      final nameMatches = w.name.toLowerCase().contains(query);
      final descMatches = w.description?.toLowerCase().contains(query) ?? false;
      return nameMatches || descMatches;
    }).toList();
  }

  void _openWorkflowDetail(Workflow workflow) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkflowDetailScreen(
          workflowId: workflow.id,
          initialWorkflow: workflow,
          workflowService: widget.workflowService,
          taskService: widget.taskService,
        ),
      ),
    ).then((_) => _fetchWorkflows());
  }

  Future<void> _showCreateWorkflowDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isActive = true;
    bool isSaving = false;
    String? dialogError;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.account_tree_outlined, color: Color(0xFF1E88E5)),
                  SizedBox(width: 8),
                  Text('Create Workflow'),
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
                          subtitle: const Text('Available for task assignment'),
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
                            await widget.workflowService.createWorkflow(
                              WorkflowCreateRequest(
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
                              dialogError = 'Failed to create workflow: $e';
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create Workflow'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workflow created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _fetchWorkflows();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedWorkflows = _filteredWorkflows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workflows'),
        actions: [
          IconButton(
            tooltip: 'Refresh Workflows',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchWorkflows,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_chart),
        label: const Text('New Workflow'),
        onPressed: _showCreateWorkflowDialog,
      ),
      body: Column(
        children: [
          // Search & Filter Row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search workflows...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Active / Inactive Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _activeFilter == null,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _activeFilter = null);
                      _fetchWorkflows();
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Active Only'),
                  selected: _activeFilter == true,
                  onSelected: (selected) {
                    setState(() => _activeFilter = selected ? true : null);
                    _fetchWorkflows();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Inactive'),
                  selected: _activeFilter == false,
                  onSelected: (selected) {
                    setState(() => _activeFilter = selected ? false : null);
                    _fetchWorkflows();
                  },
                ),
              ],
            ),
          ),

          // Error State
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
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
                        onPressed: _fetchWorkflows,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Workflows List
          Expanded(
            child: _isLoading && _workflows.isEmpty
                ? const LoadingStateWidget(message: 'Loading workflows...')
                : displayedWorkflows.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _fetchWorkflows,
                        child: ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                children: [
                                  Icon(Icons.account_tree_outlined, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchController.text.isEmpty
                                        ? 'No workflows found'
                                        : 'No workflows match "${_searchController.text}"',
                                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: _showCreateWorkflowDialog,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Create Your First Workflow'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchWorkflows,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: displayedWorkflows.length,
                          itemBuilder: (context, index) {
                            final workflow = displayedWorkflows[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
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
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        workflow.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                                        workflow.isActive ? 'Active' : 'Inactive',
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
                                subtitle: workflow.description != null && workflow.description!.isNotEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          workflow.description!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                        ),
                                      )
                                    : null,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openWorkflowDetail(workflow),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
