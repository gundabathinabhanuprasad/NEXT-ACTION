import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../widgets/common_widgets.dart';
import 'team_member_detail_screen.dart';

/// Screen listing team members with search, active status filter, and profile navigation.
class TeamScreen extends StatefulWidget {
  final UserService userService;
  final TaskService taskService;
  final String? currentUserId;

  const TeamScreen({
    super.key,
    required this.userService,
    required this.taskService,
    this.currentUserId,
  });

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  List<User> _users = [];
  bool? _isActiveFilter; // null = all, true = active only, false = inactive only

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.userService.getUsers(
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        isActive: _isActiveFilter,
        page: 1,
        pageSize: 100,
      );

      if (mounted) {
        setState(() {
          _users = response.items;
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
          _errorMessage = 'Failed to load team members: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Team',
            onPressed: _isLoading ? null : _fetchUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search members by name or email...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _fetchUsers();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => _fetchUsers(),
                  onSubmitted: (_) => _fetchUsers(),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All Members'),
                        selected: _isActiveFilter == null,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _isActiveFilter = null);
                            _fetchUsers();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Active Only'),
                        selected: _isActiveFilter == true,
                        onSelected: (selected) {
                          setState(() => _isActiveFilter = selected ? true : null);
                          _fetchUsers();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Inactive Only'),
                        selected: _isActiveFilter == false,
                        onSelected: (selected) {
                          setState(() => _isActiveFilter = selected ? false : null);
                          _fetchUsers();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // User List Body
          Expanded(
            child: _isLoading && _users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: ErrorStateWidget(
                          message: _errorMessage!,
                          onRetry: _fetchUsers,
                        ),
                      )
                    : _users.isEmpty
                        ? Center(
                            child: EmptyStateWidget(
                              icon: Icons.people_outline,
                              title: 'No Team Members Found',
                              description: _searchController.text.isNotEmpty
                                  ? 'No members matching "${_searchController.text}".'
                                  : 'No team members registered yet.',
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchUsers,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: _users.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                final isCurrentUser = user.id == widget.currentUserId;

                                return Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: isCurrentUser
                                        ? BorderSide(color: theme.colorScheme.primary.withOpacity(0.5), width: 1.5)
                                        : BorderSide.none,
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TeamMemberDetailScreen(
                                            userId: user.id,
                                            initialUser: user,
                                            userService: widget.userService,
                                            taskService: widget.taskService,
                                            currentUserId: widget.currentUserId,
                                          ),
                                        ),
                                      ).then((_) => _fetchUsers());
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 24,
                                            backgroundColor: theme.colorScheme.primaryContainer,
                                            child: Text(
                                              (user.name.isNotEmpty ? user.name[0] : 'U').toUpperCase(),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        user.name,
                                                        style: theme.textTheme.titleMedium?.copyWith(
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (isCurrentUser) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: theme.colorScheme.primaryContainer,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          'You',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: theme.colorScheme.primary,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  user.email,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Chip(
                                            avatar: Icon(
                                              user.isActive ? Icons.check_circle : Icons.pause_circle,
                                              size: 14,
                                              color: user.isActive ? Colors.green : Colors.orange,
                                            ),
                                            label: Text(
                                              user.isActive ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: user.isActive ? Colors.green.shade800 : Colors.orange.shade800,
                                              ),
                                            ),
                                            backgroundColor: user.isActive
                                                ? Colors.green.withOpacity(0.12)
                                                : Colors.orange.withOpacity(0.12),
                                            side: BorderSide.none,
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_right, color: Colors.grey),
                                        ],
                                      ),
                                    ),
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
