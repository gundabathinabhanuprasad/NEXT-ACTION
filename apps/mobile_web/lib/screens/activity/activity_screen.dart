import 'package:flutter/material.dart';
import '../../models/history/task_history_models.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';

/// Activity Center & Timeline Feed screen presenting chronological audit history across tasks.
class ActivityScreen extends StatefulWidget {
  final TaskService taskService;
  final UserService? userService;

  const ActivityScreen({
    super.key,
    required this.taskService,
    this.userService,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<TaskHistory> _activities = [];
  int _total = 0;
  int _page = 1;
  final int _pageSize = 30;
  bool _isLoading = false;
  String? _errorMessage;

  String _selectedCategory = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchActivities();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchActivities() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.taskService.getActivity(
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _activities = response.items;
        _total = response.total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load activity timeline: $e';
        _isLoading = false;
      });
    }
  }

  List<TaskHistory> get _filteredActivities {
    var list = _activities;

    if (_selectedCategory != 'all') {
      list = list.where((a) => a.actionCategory == _selectedCategory).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) {
        final matchesTask = a.taskTitle?.toLowerCase().contains(q) ?? false;
        final matchesActor = a.displayActor.toLowerCase().contains(q);
        final matchesAction = a.formattedAction.toLowerCase().contains(q);
        final matchesReason = a.reason?.toLowerCase().contains(q) ?? false;
        return matchesTask || matchesActor || matchesAction || matchesReason;
      }).toList();
    }

    return list;
  }

  Map<String, List<TaskHistory>> _groupByDate(List<TaskHistory> list) {
    final Map<String, List<TaskHistory>> groups = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

    for (final item in list) {
      final itemDate = DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day);
      String groupKey;

      if (itemDate == today) {
        groupKey = 'Today';
      } else if (itemDate == yesterday) {
        groupKey = 'Yesterday';
      } else if (itemDate.isAfter(startOfWeek)) {
        groupKey = 'Earlier This Week';
      } else if (itemDate.month == now.month && itemDate.year == now.year) {
        groupKey = 'Earlier This Month';
      } else {
        groupKey = '${itemDate.year}-${itemDate.month.toString().padLeft(2, '0')}';
      }

      groups.putIfAbsent(groupKey, () => []).add(item);
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredActivities;
    final grouped = _groupByDate(filtered);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Timeline',
            onPressed: _fetchActivities,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchActivities,
        child: Column(
          children: [
            // Search & Filter Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: const Border(bottom: BorderSide(color: Colors.black12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Filter activity by keyword, actor, or task...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Activity ($_total)', theme),
                        const SizedBox(width: 6),
                        _buildFilterChip('status', 'Status Changes', theme),
                        const SizedBox(width: 6),
                        _buildFilterChip('assignment', 'Assignments', theme),
                        const SizedBox(width: 6),
                        _buildFilterChip('attempt', 'Attempts', theme),
                        const SizedBox(width: 6),
                        _buildFilterChip('scheduling', 'Postponed & Scheduled', theme),
                        const SizedBox(width: 6),
                        _buildFilterChip('creation', 'Created & Templates', theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 40),
                              const SizedBox(height: 8),
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchActivities,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.timeline, size: 48, color: Colors.black26),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No activity records found.',
                                    style: TextStyle(fontSize: 14, color: Colors.black54),
                                  ),
                                  if (_selectedCategory != 'all' || _searchQuery.isNotEmpty)
                                    TextButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _selectedCategory = 'all';
                                          _searchQuery = '';
                                        });
                                      },
                                      child: const Text('Clear Filters'),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: grouped.length,
                              itemBuilder: (context, groupIndex) {
                                final groupKey = grouped.keys.elementAt(groupIndex);
                                final items = grouped[groupKey]!;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            groupKey,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.primary,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(child: Divider()),
                                        ],
                                      ),
                                    ),
                                    ...items.map((item) => _buildActivityTile(item, theme)),
                                  ],
                                );
                              },
                            ),
            ),
            if (_total > _pageSize) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Page $_page of ${((_total - 1) / _pageSize).floor() + 1} ($_total total)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _page > 1
                              ? () {
                                  setState(() => _page--);
                                  _fetchActivities();
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _page * _pageSize < _total
                              ? () {
                                  setState(() => _page++);
                                  _fetchActivities();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String category, String label, ThemeData theme) {
    final isSelected = _selectedCategory == category;
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
          _selectedCategory = category;
        });
      },
    );
  }

  Widget _buildActivityTile(TaskHistory item, ThemeData theme) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: item.taskId != null
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(
                      taskId: item.taskId!,
                      taskService: widget.taskService,
                    ),
                  ),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: item.actionColor.withOpacity(0.15),
                    child: Icon(item.actionIcon, size: 14, color: item.actionColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.formattedAction,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        if (item.taskTitle != null && item.taskTitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Task: ${item.taskTitle}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
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
                  const Icon(Icons.person_outline, size: 12, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(
                    'By ${item.displayActor}',
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
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
        ),
      ),
    );
  }
}
