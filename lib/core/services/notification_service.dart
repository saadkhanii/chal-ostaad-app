import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/main.dart'; // for navigatorKey
import 'dart:convert';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("[NotificationService] Handling background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _notificationsEnabledKey = 'notifications_enabled';

  User? get _currentUser {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;
    try {
      user = FirebaseAuth.instanceFor(app: Firebase.app('client')).currentUser;
      if (user != null) return user;
      user = FirebaseAuth.instanceFor(app: Firebase.app('worker')).currentUser;
    } catch (_) {}
    return user;
  }

  Future<void> initialize() async {
    print("[NotificationService] Initializing...");
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _requestPermissions();
    await _setupLocalNotifications();
    await updateToken();

    _fcm.onTokenRefresh.listen((token) => _saveTokenToFirestore(token));
    FirebaseMessaging.onMessage.listen((msg) => _handleForegroundMessage(msg));
    
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(milliseconds: 500), () => _handleMessage(initialMessage));
    }
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _handleMessage(msg));
  }

  Future<void> updateToken() async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) await _saveTokenToFirestore(token);
    } catch (e) {
      print("[NotificationService] Error getting token: $e");
    }
  }

  Future<void> _requestPermissions() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _setupLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (res) {
        if (res.payload != null) _handlePayload(res.payload!);
      },
    );

    const channel = AndroidNotificationChannel(
      'chal_ostaad_channel',
      'Chal Ostaad Notifications',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = _currentUser;
      if (user == null) return;

      final batch = _firestore.batch();
      final timestamp = FieldValue.serverTimestamp();

      batch.set(_firestore.collection('users').doc(user.uid), {
        'fcmToken': token,
        'lastTokenUpdate': timestamp,
      }, SetOptions(merge: true));

      batch.set(_firestore.collection('clients').doc(user.uid), {
        'fcmToken': token,
        'lastTokenUpdate': timestamp,
      }, SetOptions(merge: true));

      batch.set(_firestore.collection('workers').doc(user.uid), {
        'fcmToken': token,
        'lastTokenUpdate': timestamp,
      }, SetOptions(merge: true));
      
      await batch.commit();
      print("[NotificationService] FCM Token updated for ${user.uid}");
    } catch (e) {
      print("[NotificationService] Error saving token: $e");
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _areNotificationsEnabled().then((enabled) {
      if (enabled) _showLocalNotification(message);
    });
    _saveNotificationToFirestore(message);
  }

  void _handleMessage(RemoteMessage message) => _navigateBasedOnType(message.data);

  void _handlePayload(String payload) {
    try {
      _navigateBasedOnType(jsonDecode(payload));
    } catch (_) {}
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('chal_ostaad_channel', 'Chal Ostaad Notifications', importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  Future<void> _saveNotificationToFirestore(RemoteMessage message) async {
    final user = _currentUser;
    if (user == null) return;

    try {
      final notificationData = {
        'title': message.notification?.title ?? message.data['title'] ?? 'Notification',
        'body': message.notification?.body ?? message.data['body'] ?? '',
        'type': message.data['type'] ?? 'general',
        'jobId': message.data['jobId'],
        'chatId': message.data['chatId'],
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'data': message.data,
      };

      await _firestore.collection('users').doc(user.uid).collection('notifications').add(notificationData);
    } catch (e) {
      print("[NotificationService] Error saving notification: $e");
    }
  }

  void _navigateBasedOnType(Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    String type = data['type'] ?? '';
    String? jobId = data['jobId'];
    
    if ((type == 'new_job' || type == 'bid_accepted' || type == 'bid_rejected') && jobId != null) {
      navigator.pushNamed(AppRoutes.jobDetails, arguments: jobId);
    } else if (type == 'chat_message' && data['chatId'] != null) {
      navigator.pushNamed(AppRoutes.chat, arguments: data['chatId']);
    } else {
      navigator.pushNamed(AppRoutes.notifications);
    }
  }

  // ============== SENDING LOGIC ==============

  Future<void> sendJobPostedNotification({
    required String jobId,
    required String jobTitle,
    required String clientId,
    required String clientName,
    required List<String> workerIds,
    required String category,
  }) async {
    try {
      final batch = _firestore.batch();
      for (final workerId in workerIds) {
        final notificationData = {
          'title': 'New Job: $jobTitle',
          'body': '$clientName posted a job in $category',
          'type': 'new_job',
          'jobId': jobId,
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
          'data': {'jobId': jobId, 'type': 'new_job'},
        };
        batch.set(_firestore.collection('users').doc(workerId).collection('notifications').doc(), notificationData);
      }
      await batch.commit();
      print("[NotificationService] Sent job alerts to ${workerIds.length} workers");
    } catch (e) {
      print("[NotificationService] Error sending job alerts: $e");
    }
  }

  Future<void> sendBidPlacedNotification({
    required String jobId,
    required String jobTitle,
    required String workerId,
    required String workerName,
    required double bidAmount,
    required String clientId,
  }) async {
    try {
      final notificationData = {
        'title': 'New Bid Received',
        'body': '$workerName bid Rs. $bidAmount on "$jobTitle"',
        'type': 'bid_received',
        'jobId': jobId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': {'jobId': jobId, 'type': 'bid_received'},
      };
      await _firestore.collection('users').doc(clientId).collection('notifications').add(notificationData);
    } catch (_) {}
  }

  Future<void> sendBidStatusNotification({
    required String jobId,
    required String jobTitle,
    required String workerId,
    required String clientName,
    required String status,
  }) async {
    try {
      final isAccepted = status == 'accepted';
      final notificationData = {
        'title': isAccepted ? 'Bid Accepted!' : 'Bid Update',
        'body': isAccepted ? 'Your bid for "$jobTitle" was accepted by $clientName' : 'Your bid for "$jobTitle" was not selected',
        'type': isAccepted ? 'bid_accepted' : 'bid_rejected',
        'jobId': jobId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': {'jobId': jobId, 'type': isAccepted ? 'bid_accepted' : 'bid_rejected'},
      };
      await _firestore.collection('users').doc(workerId).collection('notifications').add(notificationData);
    } catch (_) {}
  }

  Future<List<String>> getRelevantWorkersForJob(String category) async {
    try {
      print("[NotificationService] SEARCHING for workers in: '$category'");
      final querySnapshot = await _firestore
          .collection('workers')
          .where('accountStatus', isEqualTo: 'active')
          .get();
      
      final target = category.trim().toLowerCase();
      
      final workers = querySnapshot.docs.where((doc) {
        final data = doc.data();
        final workInfo = data['workInfo'] as Map<String, dynamic>? ?? {};
        
        final catId = (workInfo['categoryId'] ?? '').toString().toLowerCase();
        final catName = (workInfo['categoryName'] ?? '').toString().toLowerCase();
        
        // Log worker data for debugging
        print("[NotificationService] Checking Worker ${doc.id}: ID='$catId', Name='$catName'");

        return catId == target || catName == target || target.contains(catId) || target.contains(catName);
      }).map((doc) => doc.id).toList();

      print("[NotificationService] MATCH FOUND: ${workers.length} workers");
      return workers;
      
    } catch (e) {
      print("[NotificationService] Error finding workers: $e");
      return [];
    }
  }

  Future<bool> _areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  Future<bool> areNotificationsEnabled() => _areNotificationsEnabled();

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }
}
