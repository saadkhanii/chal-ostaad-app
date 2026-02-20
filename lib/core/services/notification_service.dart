import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/main.dart';
import 'package:flutter/services.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:chal_ostaad/shared/widgets/in_app_notification_banner.dart';

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

  // Cached OAuth token to avoid generating on every call
  String? _cachedAccessToken;
  DateTime? _tokenExpiry;

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

      for (final collection in ['users', 'clients', 'workers']) {
        batch.set(_firestore.collection(collection).doc(user.uid), {
          'fcmToken': token,
          'lastTokenUpdate': timestamp,
        }, SetOptions(merge: true));
      }

      await batch.commit();
      print("[NotificationService] FCM Token updated for ${user.uid}");
    } catch (e) {
      print("[NotificationService] Error saving token: $e");
    }
  }

  // ============== FCM V1 API OAUTH TOKEN ==============

  Future<String?> _getAccessToken() async {
    // Return cached token if still valid (with 5 min buffer)
    if (_cachedAccessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return _cachedAccessToken;
    }

    try {
      // Load service account from assets
      final jsonStr = await rootBundle.loadString('assets/service_account.json');
      final serviceAccount = jsonDecode(jsonStr);

      final privateKeyPem = serviceAccount['private_key'] as String;
      final clientEmail = serviceAccount['client_email'] as String;

      final now = DateTime.now();
      final expiry = now.add(const Duration(hours: 1));

      // Create JWT
      final jwt = JWT(
        {
          'iss': clientEmail,
          'sub': clientEmail,
          'aud': 'https://oauth2.googleapis.com/token',
          'iat': now.millisecondsSinceEpoch ~/ 1000,
          'exp': expiry.millisecondsSinceEpoch ~/ 1000,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        },
      );

      final token = jwt.sign(
        RSAPrivateKey(privateKeyPem),
        algorithm: JWTAlgorithm.RS256,
      );

      // Exchange JWT for OAuth access token
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': token,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _cachedAccessToken = data['access_token'];
        _tokenExpiry = expiry;
        print("[NotificationService] OAuth token obtained successfully");
        return _cachedAccessToken;
      } else {
        print("[NotificationService] Failed to get OAuth token: ${response.body}");
        return null;
      }
    } catch (e) {
      print("[NotificationService] Error generating access token: $e");
      return null;
    }
  }

  // ============== SEND PUSH VIA FCM V1 ==============

  Future<bool> _sendPushNotification({
    required String fcmToken,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) return false;

      const projectId = 'chalostaad';
      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final payload = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': data,
          'android': {
            'notification': {
              'channel_id': 'chal_ostaad_channel',
            },
            'priority': 'high',
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
                'badge': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        print("[NotificationService] Push sent successfully");
        return true;
      } else {
        print("[NotificationService] Push failed: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      print("[NotificationService] Error sending push: $e");
      return false;
    }
  }

  /// Get FCM token for a specific user from Firestore
  Future<String?> _getUserFcmToken(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data()?['fcmToken'] as String?;
    } catch (e) {
      print("[NotificationService] Error getting FCM token for $userId: $e");
      return null;
    }
  }

  // ============== MESSAGE HANDLERS ==============

  void _handleForegroundMessage(RemoteMessage message) {
    _areNotificationsEnabled().then((enabled) {
      if (!enabled) return;
      _showLocalNotification(message);

      // Show in-app banner when app is in foreground
      final context = navigatorKey.currentContext;
      if (context != null) {
        final title = message.notification?.title ?? message.data['title'] ?? 'Notification';
        final body = message.notification?.body ?? message.data['body'] ?? '';
        InAppNotificationBanner.show(
          context,
          title: title,
          body: body,
          onTap: () => _navigateBasedOnType(message.data),
        );
      }
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
          android: AndroidNotificationDetails(
            'chal_ostaad_channel',
            'Chal Ostaad Notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
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
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .add({
        'title': message.notification?.title ?? message.data['title'] ?? 'Notification',
        'body': message.notification?.body ?? message.data['body'] ?? '',
        'type': message.data['type'] ?? 'general',
        'jobId': message.data['jobId'],
        'chatId': message.data['chatId'],
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'data': message.data,
      });
    } catch (e) {
      print("[NotificationService] Error saving notification: $e");
    }
  }

  void _navigateBasedOnType(Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final type = data['type'] ?? '';
    final jobId = data['jobId'];

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
        // Save to Firestore
        batch.set(
          _firestore.collection('users').doc(workerId).collection('notifications').doc(),
          {
            'title': 'New Job: $jobTitle',
            'body': '$clientName posted a job in $category',
            'type': 'new_job',
            'jobId': jobId,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
            'data': {'jobId': jobId, 'type': 'new_job'},
          },
        );
      }
      await batch.commit();

      // Send actual push notifications
      for (final workerId in workerIds) {
        final fcmToken = await _getUserFcmToken(workerId);
        if (fcmToken != null) {
          await _sendPushNotification(
            fcmToken: fcmToken,
            title: 'New Job: $jobTitle',
            body: '$clientName posted a job in $category',
            data: {'type': 'new_job', 'jobId': jobId},
          );
        }
      }

      print("[NotificationService] Job alerts sent to ${workerIds.length} workers");
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
      const title = 'New Bid Received';
      final body = '$workerName bid Rs. $bidAmount on "$jobTitle"';

      // Save to Firestore
      await _firestore.collection('users').doc(clientId).collection('notifications').add({
        'title': title,
        'body': body,
        'type': 'bid_received',
        'jobId': jobId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': {'jobId': jobId, 'type': 'bid_received'},
      });

      // Send push
      final fcmToken = await _getUserFcmToken(clientId);
      if (fcmToken != null) {
        await _sendPushNotification(
          fcmToken: fcmToken,
          title: title,
          body: body,
          data: {'type': 'bid_received', 'jobId': jobId},
        );
      }
    } catch (e) {
      print("[NotificationService] Error sending bid notification: $e");
    }
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
      final title = isAccepted ? 'Bid Accepted!' : 'Bid Update';
      final body = isAccepted
          ? 'Your bid for "$jobTitle" was accepted by $clientName'
          : 'Your bid for "$jobTitle" was not selected';
      final type = isAccepted ? 'bid_accepted' : 'bid_rejected';

      // Save to Firestore
      await _firestore.collection('users').doc(workerId).collection('notifications').add({
        'title': title,
        'body': body,
        'type': type,
        'jobId': jobId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': {'jobId': jobId, 'type': type},
      });

      // Send push
      final fcmToken = await _getUserFcmToken(workerId);
      if (fcmToken != null) {
        await _sendPushNotification(
          fcmToken: fcmToken,
          title: title,
          body: body,
          data: {'type': type, 'jobId': jobId},
        );
      }
    } catch (e) {
      print("[NotificationService] Error sending bid status notification: $e");
    }
  }

  Future<List<String>> getRelevantWorkersForJob(String categoryId) async {
    try {
      print("[NotificationService] Searching for workers with categoryId: '$categoryId'");
      final querySnapshot = await _firestore
          .collection('workers')
          .where('accountStatus', isEqualTo: 'active')
          .get();

      final workers = querySnapshot.docs.where((doc) {
        final data = doc.data();
        final workInfo = data['workInfo'] as Map<String, dynamic>? ?? {};
        final catId = (workInfo['categoryId'] ?? '').toString();
        return catId == categoryId;
      }).map((doc) => doc.id).toList();

      print("[NotificationService] Found ${workers.length} matching workers");
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