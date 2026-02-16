// lib/features/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  const NotificationsScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true, // Default to true for standalone navigation
  });

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      // Conditionally show AppBar
      appBar: widget.showAppBar
          ? AppBar(
        title: Text('notification.notifications'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () {
              _markAllAsRead(context, user?.uid);
            },
            tooltip: 'notification.mark_all_read'.tr(),
          ),
        ],
      )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
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

          return ListView.builder(
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
                onDismissed: (direction) {
                  _deleteNotification(user?.uid, notifId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('common.deleted'.tr()),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: notif['isRead'] == true
                          ? Colors.grey[300]
                          : Theme.of(context).primaryColor,
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
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(notif['body'] ?? ''),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(notif['timestamp']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      _markAsRead(user?.uid, notifId);
                      _navigateToNotification(context, notif);
                    },
                  ),
                ),
              );
            },
          );
        },
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

  Future<void> _markAsRead(String? userId, String notifId) async {
    if (userId == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notifId)
        .update({'isRead': true});
  }

  Future<void> _markAllAsRead(BuildContext context, String? userId) async {
    if (userId == null) return;
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
          content: Text('notification.mark_all_read'.tr()),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteNotification(String? userId, String notifId) async {
    if (userId == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notifId)
        .delete();
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

