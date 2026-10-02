import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/auth/auth_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/task/task_service.dart';
import '../../services/user/user_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_list_screen.dart';

/// Screen displaying authoritative authenticated user identity and session controls.
class ProfileScreen extends StatefulWidget {
  final AuthProvider authProvider;
  final UserService? userService;
  final TaskService? taskService;

  const ProfileScreen({
    super.key,
    required this.authProvider,
    this.userService,
    this.taskService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final UserService _userService;
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _userService = widget.userService ??
        UserService(apiClient: widget.taskService?.apiClient ?? widget.authProvider.authService.apiClient);
    _user = widget.authProvider.currentUser;
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _userService.getCurrentUser();
      if (mounted) {
        setState(() {
          _user = user;
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
          _errorMessage = 'Failed to load user profile: $e';
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await widget.authProvider.logout();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user ?? widget.authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Profile',
            onPressed: _isLoading ? null : _refreshProfile,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading && user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshProfile,
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
                            onRetry: _refreshProfile,
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Hero Profile Card
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 44,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: Text(
                                    (user?.name.isNotEmpty == true ? user!.name[0] : 'U').toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  user?.name ?? 'Authenticated User',
                                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  user?.email ?? '',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                Chip(
                                  avatar: Icon(
                                    user?.isActive == true ? Icons.check_circle : Icons.pause_circle,
                                    size: 16,
                                    color: user?.isActive == true ? Colors.green : Colors.orange,
                                  ),
                                  label: Text(
                                    user?.isActive == true ? 'Active Account' : 'Inactive Account',
                                    style: TextStyle(
                                      color: user?.isActive == true ? Colors.green.shade800 : Colors.orange.shade800,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  backgroundColor: user?.isActive == true
                                      ? Colors.green.withOpacity(0.12)
                                      : Colors.orange.withOpacity(0.12),
                                  side: BorderSide.none,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Technical / Security Info Card
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.shield_outlined, size: 20, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Identity & Workspace Context',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                _buildInfoTile(
                                  icon: Icons.fingerprint,
                                  title: 'User ID',
                                  value: user?.id ?? '—',
                                  subtitle: 'Authoritative JWT subject UUID',
                                  theme: theme,
                                ),
                                const SizedBox(height: 12),
                                _buildInfoTile(
                                  icon: Icons.calendar_today_outlined,
                                  title: 'Member Since',
                                  value: user != null ? user.createdAt.toLocal().toString().split('.')[0] : '—',
                                  theme: theme,
                                ),
                                const SizedBox(height: 12),
                                _buildInfoTile(
                                  icon: Icons.update,
                                  title: 'Last Profile Update',
                                  value: user != null ? user.updatedAt.toLocal().toString().split('.')[0] : '—',
                                  theme: theme,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Quick Navigation Actions
                        if (widget.taskService != null && user != null) ...[
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Workspace Shortcuts',
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton.tonalIcon(
                                    icon: const Icon(Icons.assignment_ind_outlined),
                                    label: const Text('View My Assigned Tasks'),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TaskListScreen(
                                            taskService: widget.taskService!,
                                            initialAssignedUserId: user.id,
                                            currentUserId: user.id,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Sign Out Button
                        OutlinedButton.icon(
                          icon: const Icon(Icons.logout, color: Colors.red),
                          label: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _handleLogout,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required ThemeData theme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
