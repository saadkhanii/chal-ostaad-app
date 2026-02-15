// lib/core/providers/notification_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chal_ostaad/core/services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final notificationsEnabledProvider = FutureProvider<bool>((ref) async {
  final notificationService = ref.read(notificationServiceProvider);
  return await notificationService.areNotificationsEnabled();
});

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

final notificationSettingsProvider = StateNotifierProvider<NotificationSettingsNotifier, bool>((ref) {
  final notificationService = ref.read(notificationServiceProvider);
  return NotificationSettingsNotifier(notificationService);
});
