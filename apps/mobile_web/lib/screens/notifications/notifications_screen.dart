import 'package:flutter/material.dart';
import '../../core/errors/api_exception.dart';
import '../../models/notification/notification_models.dart';
import '../../services/notification/notification_service.dart';
import '../../services/scheduler/scheduler_service.dart';
import '../../services/task/task_service.dart';
import '../../widgets/common_widgets.dart';
import '../tasks/task_detail_screen.dart';

/// Category filter options for attention items in the Notification Center.
enum NotificationCategoryFilter {
  all('All'),
  overdue('Overdue'),
  reminder('Reminders'),
  followUp('Follow-ups'),
  nextAction('Next Actions'),
  attemptLimit('Attempt Limits'),
  assignment('Assignments');

  final String label;
  const NotificationCategoryFilter(this.label);
}

/// Production Notification Center & Attention Management Screen.
class NotificationsScreen extends StatefulWidget {
  final NotificationService notificationService;
  final TaskService taskService;
  final SchedulerService? schedulerService;

  const NotificationsScreen({
    super.key,
    required this.notificationService,
    required this.taskService,
    this.schedulerService,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _unreadOnly = false;
  NotificationCategoryFilter _categoryFilter = NotificationCategoryFilter.all;
  bool _isLoading = true;
  bool _isActionInProgress = false;
  String? _errorMessage;

  List<AppNotification> _notifications = [];
  int _totalCount = 0;
  int _unreadCount = 0;

  List<AppNotification> get _filteredNotifications {
    if (_categoryFilter == NotificationCategoryFilter.all) {
      return _notifications;
    }
    return _notifications.where((n) {
      switch (_categoryFilter) {
        case NotificationCategoryFilter.overdue:
          return n.isOverdue;
        case NotificationCategoryFilter.reminder:
          return n.isReminderDue;
        case NotificationCategoryFilter.followUp:
          return n.isFollowUpDue;
        case NotificationCategoryFilter.nextAction:
          return n.isNextActionDue;
        case NotificationCategoryFilter.attemptLimit:
          return n.isAttemptLimit;
        case NotificationCategoryFilter.assignment:
          return n.isTaskAssigned;
        case NotificationCategoryFilter.all:
          return true;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.notificationService.getNotifications(
        unreadOnly: _unreadOnly,
        page: 1,
        pageSize: 100,
      );

      if (mounted) {
        setState(() {
          _notifications = response.items;
          _totalCount = response.total;
          _unreadCount = response.unreadCount;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load notifications: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (notification.isRead) return;

    try {
      final updated = await widget.notificationService.markAsRead(notification.id);
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n.id == notification.id);
          if (index != -1) {
            _notifications[index] = updated;
          }
          if (_unreadCount > 0) {
            _unreadCount--;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark notification as read: $e')),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    setState(() => _isActionInProgress = true);
    try {
      await widget.notificationService.markAllAsRead();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _fetchNotifications();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark all as read: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _evaluateDueNotifications() async {
    setState(() => _isActionInProgress = true);
    try {
      if (widget.schedulerService != null) {
        final result = await widget.schedulerService!.evaluateScheduler();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.notificationsCreated > 0
                    ? 'Evaluation complete: ${result.notificationsCreated} new alert(s), ${result.duplicatesSkipped} duplicate(s) skipped.'
                    : 'All alerts are up to date (${result.duplicatesSkipped} duplicates skipped).',
              ),
              backgroundColor: Colors.indigo,
            ),
          );
        }
      } else {
        final result = await widget.notificationService.evaluateNotifications();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.createdCount > 0
                    ? 'Evaluation generated ${result.createdCount} new alert(s).'
                    : 'All notifications are up to date.',
              ),
              backgroundColor: Colors.indigo,
            ),
          );
        }
      }
      await _fetchNotifications();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to evaluate alerts: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  void _onNotificationTap(AppNotification notification) async {
    if (!notification.isRead) {
      await _markAsRead(notification);
    }

    if (notification.taskId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskDetailScreen(
            taskService: widget.taskService,
            taskId: notification.taskId!,
          ),
        ),
      ).then((_) => _fetchNotifications());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.notifications_outlined),
            const SizedBox(width: 8),
            const Text(
              'Notification Center',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Evaluate Due Alerts',
            icon: _isActionInProgress
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: _isActionInProgress ? null : _evaluateDueNotifications,
          ),
          IconButton(
            tooltip: 'Mark All as Read',
            icon: const Icon(Icons.done_all),
            onPressed: _isActionInProgress || _unreadCount == 0 ? null : _markAllAsRead,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchNotifications,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs & Stats Bar
          _buildFilterBar(theme),

          // Main Content List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchNotifications,
              child: _buildBodyContent(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  FilterChip(
                    label: Text('All ($_totalCount)'),
                    selected: !_unreadOnly,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _unreadOnly = false);
                        _fetchNotifications();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unread'),
                        if (_unreadCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: _unreadOnly,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _unreadOnly = true);
                        _fetchNotifications();
                      }
                    },
                  ),
                ],
              ),
              if (_unreadCount > 0)
                TextButton.icon(
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                  onPressed: _isActionInProgress ? null : _markAllAsRead,
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: NotificationCategoryFilter.values.map((cat) {
                final isSelected = _categoryFilter == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat.label, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _categoryFilter = cat);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(ThemeData theme) {
    if (_isLoading) {
      return const LoadingStateWidget(message: 'Loading notifications...');
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Failed to load notifications',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _fetchNotifications,
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _unreadOnly ? Icons.mark_email_read_outlined : Icons.notifications_none_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                _unreadOnly ? 'No unread notifications' : 'No notifications yet',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _unreadOnly
                    ? 'You are all caught up! Switch to "All" to view notification history.'
                    : 'Important alerts, assignments, and due reminders will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Check for Due Alerts'),
                onPressed: _evaluateDueNotifications,
              ),
            ],
          ),
        ),
      );
    }

    final displayItems = _filteredNotifications;
    if (displayItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.filter_list_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No ${_categoryFilter.label.toLowerCase()} notifications',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => setState(() => _categoryFilter = NotificationCategoryFilter.all),
                child: const Text('Show All Categories'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: displayItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = displayItems[index];
        return _buildNotificationCard(theme, item);
      },
    );
  }

  Widget _buildNotificationCard(ThemeData theme, AppNotification notification) {
    final meta = _getNotificationMetadata(notification.type);

    return Semantics(
      label: '${notification.isRead ? "Read" : "Unread"} notification: ${notification.title}',
      container: true,
      child: Card(
        elevation: notification.isRead ? 0 : 1,
      color: notification.isRead
          ? theme.colorScheme.surface
          : meta.color.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: notification.isRead
              ? theme.colorScheme.outlineVariant
              : meta.color.withOpacity(0.4),
          width: notification.isRead ? 1 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onNotificationTap(notification),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notification Type Icon with Badge Dot
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: meta.color.withOpacity(0.15),
                    child: Icon(meta.icon, color: meta.color, size: 20),
                  ),
                  if (!notification.isRead)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: meta.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),

              // Notification Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Type Chip & Time
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: meta.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            meta.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: meta.color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          AppDateFormat.formatRelativeDate(notification.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Title
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.bold,
                        color: notification.isRead
                            ? theme.colorScheme.onSurface
                            : meta.color.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Message
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),

                    // Task Link & Mark as Read Action
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (notification.taskId != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new, size: 12, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'View Task',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Spacer(),
                        if (!notification.isRead)
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => _markAsRead(notification),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Mark read',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.done_all, size: 12, color: Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Text(
                                'Read',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  ({String label, IconData icon, Color color}) _getNotificationMetadata(String type) {
    switch (type) {
      case 'task_assigned':
        return (label: 'Assigned', icon: Icons.person_add_alt_1, color: const Color(0xFF1565C0));
      case 'task_reassigned':
        return (label: 'Reassigned', icon: Icons.swap_horiz, color: const Color(0xFF0288D1));
      case 'reminder_due':
        return (label: 'Reminder Due', icon: Icons.alarm, color: Colors.amber.shade900);
      case 'follow_up_due':
        return (label: 'Follow-up Due', icon: Icons.repeat, color: Colors.teal.shade700);
      case 'next_action_due':
        return (label: 'Next Action Due', icon: Icons.play_circle_fill, color: const Color(0xFF2E7D32));
      case 'task_overdue':
        return (label: 'Overdue', icon: Icons.warning_amber_rounded, color: Colors.red.shade700);
      case 'attempt_limit_reached':
        return (label: 'Max Attempts', icon: Icons.priority_high, color: Colors.purple.shade700);
      case 'task_completed':
        return (label: 'Completed', icon: Icons.check_circle, color: Colors.green.shade800);
      case 'task_reopened':
        return (label: 'Reopened', icon: Icons.replay, color: Colors.orange.shade800);
      default:
        return (label: 'Alert', icon: Icons.notifications, color: Colors.blueGrey);
    }
  }
}
