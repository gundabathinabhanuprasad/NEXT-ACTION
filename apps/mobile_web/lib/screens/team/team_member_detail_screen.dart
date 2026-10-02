import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../models/task/task_models.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_list_screen.dart';

/// Screen displaying a team member's profile and real task workload statistics.
class TeamMemberDetailScreen extends StatefulWidget {
  final String userId;
  final User? initialUser;
  final UserService userService;
  final TaskService taskService;
  final String? currentUserId;

  const TeamMemberDetailScreen({
    super.key,
    required this.userId,
    this.initialUser,
    required this.userService,
    required this.taskService,
    this.currentUserId,
  });

  @override
  State<TeamMemberDetailScreen> createState() => _TeamMemberDetailScreenState();
}

class _TeamMemberDetailScreenState extends State<TeamMemberDetailScreen> {
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  int _totalAssigned = 0;
  int _pendingCount = 0;
  int _inProgressCount = 0;
  int _completedCount = 0;
  int _overdueCount = 0;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _loadMemberData();
  }

  Future<void> _loadMemberData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        widget.userService.getUser(widget.userId),
        widget.taskService.getTasks(assignedUserId: widget.userId, pageSize: 100),
      ]);

      if (!mounted) return;

      final user = results[0] as User;
      final taskResponse = results[1] as TaskListResponse;

      int pending = 0;
      int inProgress = 0;
      int completed = 0;
      int overdue = 0;

      for (final t in taskResponse.items) {
        final st = t.status.toLowerCase();
        if (st == 'pending') pending++;
        if (st == 'in_progress') inProgress++;
        if (st == 'completed') completed++;
        if (t.isOverdue) overdue++;
      }

      setState(() {
        _user = user;
        _totalAssigned = taskResponse.total;
        _pendingCount = pending;
        _inProgressCount = inProgress;
        _completedCount = completed;
        _overdueCount = overdue;
        _isLoading = false;
      });
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
          _errorMessage = 'Failed to load team member: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.name ?? 'Team Member'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadMemberData,
          ),
        ],
      ),
      body: _isLoading && user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMemberData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null) ...[
                          ErrorStateWidget(
                            message: _errorMessage!,
                            onRetry: _loadMemberData,
                          ),
                          const SizedBox(height: 16),
                        ],
                        // User Header Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: Text(
                                    (user?.name.isNotEmpty == true ? user!.name[0] : 'U').toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user?.name ?? 'Team Member',
                                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        user?.email ?? '',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Chip(
                                        avatar: Icon(
                                          user?.isActive == true ? Icons.check_circle : Icons.pause_circle,
                                          size: 14,
                                          color: user?.isActive == true ? Colors.green : Colors.orange,
                                        ),
                                        label: Text(
                                          user?.isActive == true ? 'Active' : 'Inactive',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: user?.isActive == true ? Colors.green.shade800 : Colors.orange.shade800,
                                          ),
                                        ),
                                        backgroundColor: user?.isActive == true
                                            ? Colors.green.withOpacity(0.12)
                                            : Colors.orange.withOpacity(0.12),
                                        side: BorderSide.none,
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Workload Stats Section
                        Text(
                          'Workload Statistics',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Total Assigned',
                                value: '$_totalAssigned',
                                icon: Icons.assignment_outlined,
                                color: theme.colorScheme.primary,
                                theme: theme,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Pending',
                                value: '$_pendingCount',
                                icon: Icons.pending_actions_outlined,
                                color: Colors.orange,
                                theme: theme,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'In Progress',
                                value: '$_inProgressCount',
                                icon: Icons.play_circle_outline,
                                color: Colors.blue,
                                theme: theme,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Completed',
                                value: '$_completedCount',
                                icon: Icons.check_circle_outline,
                                color: Colors.green,
                                theme: theme,
                              ),
                            ),
                          ],
                        ),
                        if (_overdueCount > 0) ...[
                          const SizedBox(height: 12),
                          _buildMetricCard(
                            title: 'Overdue Attention Required',
                            value: '$_overdueCount',
                            icon: Icons.warning_amber_rounded,
                            color: Colors.red,
                            theme: theme,
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Action button: View Assigned Tasks
                        FilledButton.icon(
                          icon: const Icon(Icons.list_alt),
                          label: Text('View Assigned Tasks ($_totalAssigned)'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TaskListScreen(
                                  taskService: widget.taskService,
                                  initialAssignedUserId: widget.userId,
                                  currentUserId: widget.currentUserId,
                                ),
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

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(icon, size: 20, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
