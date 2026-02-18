import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chal_ostaad/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Provider for NotificationService
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// FutureProvider to check if notifications are enabled
final notificationsEnabledProvider = FutureProvider<bool>((ref) async {
  final notificationService = ref.read(notificationServiceProvider);
  return await notificationService.areNotificationsEnabled();
});

// Notifier for managing notification settings
class NotificationSettingsNotifier extends StateNotifier<bool> {
  final NotificationService _notificationService;

  NotificationSettingsNotifier(this._notificationService) : super(true) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    state = await _notificationService.areNotificationsEnabled();
  }

  Future<void> toggleNotifications(bool enabled) async {
    await _notificationService.setNotificationsEnabled(enabled);
    state = enabled;
  }
}

// Provider for NotificationSettingsNotifier
final notificationSettingsProvider = StateNotifierProvider<NotificationSettingsNotifier, bool>((ref) {
  final notificationService = ref.read(notificationServiceProvider);
  return NotificationSettingsNotifier(notificationService);
});

// Provider for checking specific notification type preferences
final notificationTypePrefsProvider = FutureProvider<Map<String, bool>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'job_notifications': prefs.getBool('job_notifications') ?? true,
    'chat_notifications': prefs.getBool('chat_notifications') ?? true,
    'payment_notifications': prefs.getBool('payment_notifications') ?? true,
    'promotion_notifications': prefs.getBool('promotion_notifications') ?? true,
  };
});
