import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:chal_ostaad/core/routes/app_routes.dart';
import 'package:chal_ostaad/main.dart'; // for navigatorKey

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling background message: ${message.messageId}");
  // You can also save to Firestore here if needed
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
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _requestPermissions();
    await _setupLocalNotifications();
    await _handleTokenRefresh();

    _fcm.onTokenRefresh.listen((token) {
      _saveTokenToFirestore(token);
    });

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleMessage(initialMessage);
      });
    }

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
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Fix: Use named parameter 'settings' for older plugin versions
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          _handlePayload(response.payload!);
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chal_ostaad_channel',
      'Chal Ostaad Notifications',
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
        final clientDoc = await _firestore.collection('clients').doc(userId).get();
        if (clientDoc.exists) {
          await _firestore.collection('clients').doc(userId).set({
            'fcmToken': token,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          final user = _auth.currentUser;
          if (user?.email != null) {
            final workerQuery = await _firestore
                .collection('workers')
                .where('personalInfo.email', isEqualTo: user!.email)
                .limit(1)
                .get();
            if (workerQuery.docs.isNotEmpty) {
              await _firestore.collection('workers').doc(workerQuery.docs.first.id).set({
                'fcmToken': token,
                'lastTokenUpdate': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          }
        }
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
    _areNotificationsEnabled().then((enabled) {
      if (enabled) {
        _showLocalNotification(message);
      }
    });
    _saveNotificationToFirestore(message);
  }

  void _handleMessage(RemoteMessage message) {
    _navigateBasedOnType(message.data);
  }

  void _handlePayload(String payload) {
    try {
      final Map<String, dynamic> data = Map.fromEntries(
          payload.replaceAll('{', '').replaceAll('}', '').split(', ').map((e) {
            final parts = e.split(': ');
            return MapEntry(parts[0], parts[1]);
          }));
      _navigateBasedOnType(data);
    } catch (e) {
      print('Error parsing payload: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      bool notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? true;
      if (!notificationsEnabled) return;

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'chal_ostaad_channel',
        'Chal Ostaad Notifications',
        channelDescription: 'Notifications for Chal Ostaad app',
        importance: Importance.high,
        priority: Priority.high,
      );
      const DarwinNotificationDetails iosPlatformChannelSpecifics =
      DarwinNotificationDetails();
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iosPlatformChannelSpecifics,
      );

      // Fix: Use named parameters for show()
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: platformChannelSpecifics,
        payload: message.data.toString(),
      );
    }
  }

  Future<void> _saveNotificationToFirestore(RemoteMessage message) async {
    String? userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      final clientDoc = await _firestore.collection('clients').doc(userId).get();
      final isClient = clientDoc.exists;

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

      if (isClient) {
        await _firestore
            .collection('clients')
            .doc(userId)
            .collection('notifications')
            .add(notificationData);
      } else {
        final user = _auth.currentUser;
        if (user?.email != null) {
          final workerQuery = await _firestore
              .collection('workers')
              .where('personalInfo.email', isEqualTo: user!.email)
              .limit(1)
              .get();
          if (workerQuery.docs.isNotEmpty) {
            await _firestore
                .collection('workers')
                .doc(workerQuery.docs.first.id)
                .collection('notifications')
                .add(notificationData);
          }
        }
      }

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add(notificationData);
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  void _navigateBasedOnType(Map<String, dynamic> data) {
    String type = data['type'] ?? '';
    String? jobId = data['jobId'];
    String? chatId = data['chatId'];

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    switch (type) {
      case 'new_job':
      case 'bid_accepted':
      case 'bid_rejected':
      case 'job_started':
      case 'job_completed':
        if (jobId != null) {
          navigator.pushNamed(AppRoutes.jobDetails, arguments: jobId);
        }
        break;
      case 'chat_message':
        if (chatId != null) {
          navigator.pushNamed(AppRoutes.chat, arguments: chatId);
        }
        break;
      case 'payment_received':
        navigator.pushNamed(AppRoutes.wallet);
        break;
      case 'review_received':
        navigator.pushNamed(AppRoutes.reviews);
        break;
      default:
        navigator.pushNamed(AppRoutes.notifications);
        break;
    }
  }

  // ============== PUBLIC SENDING METHODS ==============

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
          'title': 'New Job Posted',
          'body': '$clientName posted a new job: $jobTitle in $category',
          'type': 'new_job',
          'jobId': jobId,
          'clientId': clientId,
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
          'data': {
            'jobId': jobId,
            'clientId': clientId,
            'clientName': clientName,
            'jobTitle': jobTitle,
            'category': category,
          },
        };
        final workerNotificationRef = _firestore
            .collection('workers')
            .doc(workerId)
            .collection('notifications')
            .doc();
        batch.set(workerNotificationRef, notificationData);
        final userNotificationRef = _firestore
            .collection('users')
            .doc(workerId)
            .collection('notifications')
            .doc();
        batch.set(userNotificationRef, notificationData);
      }
      await batch.commit();
    } catch (e) {
      print('Error sending job notifications: $e');
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
      final batch = _firestore.batch();
      final notificationData = {
        'title': 'New Bid Received',
        'body': '$workerName placed a bid of ₹$bidAmount on your job "$jobTitle"',
        'type': 'bid_received',
        'jobId': jobId,
        'workerId': workerId,
        'bidAmount': bidAmount,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': {
          'jobId': jobId,
          'workerId': workerId,
          'workerName': workerName,
          'bidAmount': bidAmount,
          'jobTitle': jobTitle,
        },
      };
      final clientNotificationRef = _firestore
          .collection('clients')
          .doc(clientId)
          .collection('notifications')
          .doc();
      batch.set(clientNotificationRef, notificationData);
      final userNotificationRef = _firestore
          .collection('users')
          .doc(clientId)
          .collection('notifications')
          .doc();
      batch.set(userNotificationRef, notificationData);
      await batch.commit();
    } catch (e) {
      print('Error sending bid notification: $e');
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
      String title = status == 'accepted' ? 'Bid Accepted' : 'Bid Rejected';
      String body = status == 'accepted'
          ? 'Your bid for "$jobTitle" has been accepted by $clientName'
          : 'Your bid for "$jobTitle" has been rejected';
      final batch = _firestore.batch();
      final notificationData = {
        'title': title,
        'body': body,
        'type': status == 'accepted' ? 'bid_accepted' : 'bid_rejected',
        'jobId': jobId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': {
          'jobId': jobId,
          'jobTitle': jobTitle,
          'clientName': clientName,
          'status': status,
        },
      };
      final workerNotificationRef = _firestore
          .collection('workers')
          .doc(workerId)
          .collection('notifications')
          .doc();
      batch.set(workerNotificationRef, notificationData);
      final userNotificationRef = _firestore
          .collection('users')
          .doc(workerId)
          .collection('notifications')
          .doc();
      batch.set(userNotificationRef, notificationData);
      await batch.commit();
    } catch (e) {
      print('Error sending bid status notification: $e');
    }
  }

  Future<List<String>> getRelevantWorkersForJob(String category) async {
    try {
      final querySnapshot = await _firestore
          .collection('workers')
          .where('workInfo.categoryId', isEqualTo: category)
          .where('accountStatus', isEqualTo: 'active')
          .get();
      return querySnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      print('Error getting relevant workers: $e');
      return [];
    }
  }

  Future<void> removeToken() async {
    try {
      String? userId = _auth.currentUser?.uid;
      if (userId != null) {
        final clientDoc = await _firestore.collection('clients').doc(userId).get();
        if (clientDoc.exists) {
          await _firestore.collection('clients').doc(userId).update({
            'fcmToken': FieldValue.delete(),
          });
        } else {
          final user = _auth.currentUser;
          if (user?.email != null) {
            final workerQuery = await _firestore
                .collection('workers')
                .where('personalInfo.email', isEqualTo: user!.email)
                .limit(1)
                .get();
            if (workerQuery.docs.isNotEmpty) {
              await _firestore.collection('workers').doc(workerQuery.docs.first.id).update({
                'fcmToken': FieldValue.delete(),
              });
            }
          }
        }
        await _firestore.collection('users').doc(userId).update({
          'fcmToken': FieldValue.delete(),
        });
      }
    } catch (e) {
      print('Error removing token: $e');
    }
  }

  Future<bool> areNotificationsEnabled() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }

  Future<bool> _areNotificationsEnabled() async {
    return await areNotificationsEnabled();
  }
}