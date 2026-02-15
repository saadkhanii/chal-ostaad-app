// lib/features/notifications/notification_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chal_ostaad/core/providers/notification_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  // Local state for notification type preferences
  bool _jobNotifications = true;
  bool _chatNotifications = true;
  bool _paymentNotifications = true;
  bool _promotionNotifications = true;

  static const String _jobNotificationsKey = 'job_notifications';
  static const String _chatNotificationsKey = 'chat_notifications';
  static const String _paymentNotificationsKey = 'payment_notifications';
  static const String _promotionNotificationsKey = 'promotion_notifications';

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _jobNotifications = prefs.getBool(_jobNotificationsKey) ?? true;
      _chatNotifications = prefs.getBool(_chatNotificationsKey) ?? true;
      _paymentNotifications = prefs.getBool(_paymentNotificationsKey) ?? true;
      _promotionNotifications = prefs.getBool(_promotionNotificationsKey) ?? true;
    });
  }

  Future<void> _saveNotificationPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(notificationsEnabledProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('notification.notifications_settings'.tr()),
        backgroundColor: isDarkMode ? Colors.grey[900] : null,
      ),
      body: settingsAsync.when(
        data: (masterEnabled) {
          return ListView(
            children: [
              // Master toggle
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(
                        'notification.enable_notifications'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('notification.receive_notifications'.tr()),
                      value: masterEnabled,
                      activeColor: Theme.of(context).primaryColor,
                      onChanged: (value) async {
                        final notifier = ref.read(notificationSettingsProvider.notifier);
                        await notifier.toggleNotifications(value);
                      },
                    ),
                  ],
                ),
              ),

              // Notification type preferences (only enabled if master is on)
              if (masterEnabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'notification.notification_types'.tr(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[850] : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildNotificationTypeTile(
                        title: 'notification.job_notifications'.tr(),
                        subtitle: 'notification.job_notifications_desc'.tr(),
                        icon: Icons.work,
                        value: _jobNotifications,
                        onChanged: (value) {
                          setState(() => _jobNotifications = value);
                          _saveNotificationPreference(_jobNotificationsKey, value);
                        },
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildNotificationTypeTile(
                        title: 'notification.chat_notifications'.tr(),
                        subtitle: 'notification.chat_notifications_desc'.tr(),
                        icon: Icons.chat,
                        value: _chatNotifications,
                        onChanged: (value) {
                          setState(() => _chatNotifications = value);
                          _saveNotificationPreference(_chatNotificationsKey, value);
                        },
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildNotificationTypeTile(
                        title: 'notification.payment_notifications'.tr(),
                        subtitle: 'notification.payment_notifications_desc'.tr(),
                        icon: Icons.payment,
                        value: _paymentNotifications,
                        onChanged: (value) {
                          setState(() => _paymentNotifications = value);
                          _saveNotificationPreference(_paymentNotificationsKey, value);
                        },
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildNotificationTypeTile(
                        title: 'notification.promotion_notifications'.tr(),
                        subtitle: 'notification.promotion_notifications_desc'.tr(),
                        icon: Icons.local_offer,
                        value: _promotionNotifications,
                        onChanged: (value) {
                          setState(() => _promotionNotifications = value);
                          _saveNotificationPreference(_promotionNotificationsKey, value);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Info card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[850] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDarkMode ? Colors.grey[700]! : Colors.blue[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: isDarkMode ? Colors.blue[300] : Colors.blue[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'notification.notification_info'.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode ? Colors.grey[300] : Colors.blue[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Show message when notifications are disabled
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off,
                          size: 64,
                          color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'notification.notifications_disabled_msg'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text('common.error: $error'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationTypeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: value
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : (isDarkMode ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: value
              ? Theme.of(context).primaryColor
              : (isDarkMode ? Colors.grey[500] : Colors.grey[600]),
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).primaryColor,
      ),
    );
  }
}