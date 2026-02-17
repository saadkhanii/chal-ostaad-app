// lib/features/notifications/notifications_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/routes/app_routes.dart';
import '../../shared/widgets/common_header.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  const NotificationsScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true,
  });

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _isDeleting = false;
  bool _isMarkingAllRead = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          // Use standard CommonHeader
          CommonHeader(
            title: 'notification.notifications'.tr(),
            showBackButton: widget.showAppBar,
            onBackPressed: widget.showAppBar
                ? () => Navigator.pop(context)
                : null,
          ),

          // Mark All Read Button (moved below header)
          _buildMarkAllButton(context, user?.uid),

          // Notifications List
          Expanded(
            child: _buildNotificationsList(context, user, isDark, isUrdu),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkAllButton(BuildContext context, String? userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

        if (unreadCount == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace,
            vertical: CSizes.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'You have $unreadCount unread notification${unreadCount > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: CColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!_isMarkingAllRead)
                TextButton.icon(
                  onPressed: () => _markAllAsRead(context, userId),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: Text('Mark all read'),
                  style: TextButton.styleFrom(
                    foregroundColor: CColors.primary,
                  ),
                ),
              if (_isMarkingAllRead)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationsList(BuildContext context, User? user, bool isDark, bool isUrdu) {
    if (user == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'notification.login_to_view'.tr(),
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('common.error: ${snapshot.error}'),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final notifications = snapshot.data?.docs ?? [];

        if (notifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'notification.no_notifications'.tr(),
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return _isDeleting
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: () async {},
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final notif = doc.data() as Map<String, dynamic>;
              final notifId = doc.id;

              return Dismissible(
                key: Key(notifId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text('common.confirm'.tr()),
                        content: Text('notification.confirm_delete'.tr()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text('common.cancel'.tr()),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(foregroundColor: CColors.error),
                            child: Text('common.delete'.tr()),
                          ),
                        ],
                      );
                    },
                  );
                },
                onDismissed: (direction) {
                  _deleteNotification(user.uid, notifId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('notification.deleted'.tr()),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
                    side: notif['isRead'] == true
                        ? BorderSide.none
                        : BorderSide(
                      color: CColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: notif['isRead'] == true
                          ? Colors.grey[300]
                          : CColors.primary,
                      child: Icon(
                        _getNotificationIcon(notif['type']),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      notif['title'] ?? '',
                      style: TextStyle(
                        fontWeight: notif['isRead'] == true
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontSize: isUrdu ? 18 : 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notif['body'] ?? '',
                          style: TextStyle(fontSize: isUrdu ? 16 : 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(notif['timestamp']),
                          style: TextStyle(
                            fontSize: isUrdu ? 14 : 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (notif['isRead'] == true)
                          Icon(Icons.check_circle, color: CColors.success, size: 16),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _showDeleteDialog(context, user.uid, notifId),
                          color: Colors.grey,
                        ),
                      ],
                    ),
                    onTap: () {
                      _markAsRead(user.uid, notifId);
                      _navigateToNotification(context, notif);
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, String userId, String notifId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.confirm'.tr()),
        content: Text('notification.confirm_delete'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteNotification(userId, notifId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('notification.deleted'.tr()),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: CColors.error),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }
  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'new_job':
        return Icons.work;
      case 'bid_received':
      case 'bid_accepted':
        return Icons.gavel;
      case 'job_started':
      case 'job_completed':
        return Icons.check_circle;
      case 'payment_received':
        return Icons.payment;
      case 'review_received':
        return Icons.star;
      case 'chat_message':
        return Icons.chat;
      default:
        return Icons.notifications;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    if (timestamp is Timestamp) {
      return timeago.format(timestamp.toDate());
    }
    return '';
  }

  Future<void> _markAsRead(String userId, String notifId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .update({'isRead': true});
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _markAllAsRead(BuildContext context, String? userId) async {
    if (userId == null) return;

    setState(() => _isMarkingAllRead = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('notification.all_marked_read'.tr()),
            duration: const Duration(seconds: 2),
            backgroundColor: CColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'common.error'.tr()}: $e'),
            backgroundColor: CColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMarkingAllRead = false);
      }
    }
  }

  Future<void> _showClearAllDialog(BuildContext context, String? userId) async {
    if (userId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('notification.clear_all_title'.tr()),
          content: Text('notification.clear_all_confirm'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: CColors.error),
              child: Text('common.delete'.tr()),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      _clearAllNotifications(userId);
    }
  }

  Future<void> _clearAllNotifications(String userId) async {
    setState(() => _isDeleting = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .get();

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('notification.all_cleared'.tr()),
            duration: const Duration(seconds: 2),
            backgroundColor: CColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'common.error'.tr()}: $e'),
            backgroundColor: CColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _deleteNotification(String userId, String notifId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting notification: $e');
    }
  }

  void _navigateToNotification(BuildContext context, Map<String, dynamic> notif) {
    final type = notif['type'];
    final jobId = notif['jobId'];
    final chatId = notif['chatId'];

    switch (type) {
      case 'new_job':
      case 'bid_accepted':
      case 'job_started':
      case 'job_completed':
        if (jobId != null) {
          // Navigate to job details - you'll need to define these routes in AppRoutes
          Navigator.pushNamed(context, '/job-details', arguments: jobId);
        }
        break;
      case 'chat_message':
        if (chatId != null) {
          Navigator.pushNamed(context, '/chat', arguments: chatId);
        }
        break;
      case 'payment_received':
        Navigator.pushNamed(context, '/wallet');
        break;
    }
  }
}