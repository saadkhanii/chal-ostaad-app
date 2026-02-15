// lib/core/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages
  print("Handling background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _notificationsEnabledKey = 'notifications_enabled';

  Future<void> initialize() async {
    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permissions
    await _requestPermissions();

    // Setup local notifications
    await _setupLocalNotifications();

    // Get and save token if user is logged in
    await _handleTokenRefresh();

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((token) {
      _saveTokenToFirestore(token);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle when app is opened from terminated state
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }

    // Handle when app is in background and opened
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  Future<void> _requestPermissions() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      print('User declined notification permissions');
    }
  }

  Future<void> _setupLocalNotifications() async {
    // FIXED: Correct initialization for v20.1.0
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          _handlePayload(response.payload!);
        }
      },
    );


    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chal_ostaad_channel', // id
      'Chal Ostaad Notifications', // name
      description: 'Notifications for Chal Ostaad app',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _handleTokenRefresh() async {
    User? user = _auth.currentUser;
    if (user != null) {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      String? userId = _auth.currentUser?.uid;
      if (userId != null) {
        await _firestore.collection('users').doc(userId).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Show local notification
    _showLocalNotification(message);

    // Save to Firestore
    _saveNotificationToFirestore(message);
  }

  void _handleMessage(RemoteMessage message) {
    // Navigate based on notification data
    _navigateBasedOnType(message.data);
  }

  void _handlePayload(String payload) {
    // Parse payload and navigate
    print('Notification tapped with payload: $payload');
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      // Check if notifications are enabled in settings
      SharedPreferences prefs = await SharedPreferences.getInstance();
      bool notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? true;

      if (!notificationsEnabled) return;

      // FIXED: Correct show method for v20.1.0
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'chal_ostaad_channel',
            'Chal Ostaad Notifications',
            channelDescription: 'Notifications for Chal Ostaad app',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data.toString(),
      );

    }
  }

  Future<void> _saveNotificationToFirestore(RemoteMessage message) async {
    String? userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add({
        'title': message.notification?.title,
        'body': message.notification?.body,
        'type': message.data['type'] ?? 'general',
        'jobId': message.data['jobId'],
        'chatId': message.data['chatId'],
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'data': message.data,
      });
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  void _navigateBasedOnType(Map<String, dynamic> data) {
    String type = data['type'] ?? '';
    String? jobId = data['jobId'];
    String? chatId = data['chatId'];

    switch (type) {
      case 'new_job':
      case 'bid_accepted':
      case 'job_started':
      case 'job_completed':
        if (jobId != null) {
          // Navigate to job details
          // AppRouter.navigateTo('/job/$jobId');
        }
        break;
      case 'chat_message':
        if (chatId != null) {
          // Navigate to chat
          // AppRouter.navigateTo('/chat/$chatId');
        }
        break;
      case 'payment_received':
      // Navigate to wallet
      // AppRouter.navigateTo('/wallet');
        break;
      case 'review_received':
      // Navigate to reviews
      // AppRouter.navigateTo('/reviews');
        break;
    }
  }

  Future<void> removeToken() async {
    try {
      String? userId = _auth.currentUser?.uid;
      if (userId != null) {
        await _firestore.collection('users').doc(userId).update({
          'fcmToken': FieldValue.delete(),
        });
      }
    } catch (e) {
      print('Error removing token: $e');
    }
  }

  // Notification settings methods
  Future<bool> areNotificationsEnabled() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }
}