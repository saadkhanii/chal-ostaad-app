// lib/core/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Chat ID is always jobId_workerId — unique per job+worker combo
  String getChatId(String jobId, String workerId) => '${jobId}_$workerId';

  // ── Create or get existing chat (called when bid is accepted) ──
  Future<String> createOrGetChat({
    required String jobId,
    required String jobTitle,
    required String clientId,
    required String workerId,
    required String workerName,
    required String clientName,
  }) async {
    final chatId = getChatId(jobId, workerId);
    final ref    = _firestore.collection('chats').doc(chatId);
    final doc    = await ref.get();

    if (!doc.exists) {
      // Brand-new chat — write all fields.
      await ref.set({
        'jobId':           jobId,
        'jobTitle':        jobTitle,
        'clientId':        clientId,
        'workerId':        workerId,
        'workerName':      workerName,
        'clientName':      clientName,
        'lastMessage':     '',
        'lastMessageTime': Timestamp.now(),
        'lastSenderId':    '',
        'isRead':          true,
        'createdAt':       Timestamp.now(),
      });
    } else {
      // Doc already exists. Always patch the name fields so that if the
      // worker opened a pre-bid chat first (storing a category string
      // instead of a real name), the correct names are fixed on the next
      // call — e.g. when the worker opens chat after _loadWorkerName()
      // has completed, or when the client accepts the bid.
      final existing         = doc.data()!;
      final storedWorkerName = existing['workerName'] as String? ?? '';
      final storedClientName = existing['clientName'] as String? ?? '';

      if (storedWorkerName != workerName || storedClientName != clientName) {
        await ref.update({
          'workerName': workerName,
          'clientName': clientName,
        });
      }
    }

    return chatId;
  }

  // ── Send a text message ────────────────────────────────────────
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final batch = _firestore.batch();
    final now   = Timestamp.now();

    final msgRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'senderId':  senderId,
      'text':      text.trim(),
      'timestamp': now,
      'isRead':    false,
      'type':      'text',
    });

    // FIX: use set+merge instead of update so it never throws
    // [cloud_firestore/not-found] when the chat doc is missing.
    // merge:true creates the doc if absent, updates fields if present.
    final chatRef = _firestore.collection('chats').doc(chatId);
    batch.set(chatRef, {
      'lastMessage':     text.trim(),
      'lastMessageTime': now,
      'lastSenderId':    senderId,
      'isRead':          false,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ── Send a voice message (base64 audio stored in Firestore) ────
  Future<void> sendVoiceMessage({
    required String chatId,
    required String senderId,
    required String audioBase64,
    required int durationMs,
  }) async {
    final batch = _firestore.batch();
    final now   = Timestamp.now();

    final msgRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'senderId':        senderId,
      'text':            '🎤 Voice message',
      'timestamp':       now,
      'isRead':          false,
      'type':            'voice',
      'audioBase64':     audioBase64,
      'audioDurationMs': durationMs,
    });

    // FIX: same as above — set+merge prevents not-found crash
    final chatRef = _firestore.collection('chats').doc(chatId);
    batch.set(chatRef, {
      'lastMessage':     '🎤 Voice message',
      'lastMessageTime': now,
      'lastSenderId':    senderId,
      'isRead':          false,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ── Mark messages as read ──────────────────────────────────────
  Future<void> markAsRead({
    required String chatId,
    required String currentUserId,
  }) async {
    final unread = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .where('senderId', isNotEqualTo: currentUserId)
        .get();

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    // FIX: set+merge so markAsRead also never crashes on missing chat doc
    batch.set(
      _firestore.collection('chats').doc(chatId),
      {'isRead': true},
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ── Stream of messages for a chat ─────────────────────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // ── Stream of all chats for a user ────────────────────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> chatsStream({
    required String userId,
    required String role, // 'client' or 'worker'
  }) {
    final field = role == 'client' ? 'clientId' : 'workerId';
    return _firestore
        .collection('chats')
        .where(field, isEqualTo: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }

  // ── Unread count stream for badge ──────────────────────────────
  Stream<int> unreadCountStream({
    required String userId,
    required String role,
  }) {
    final field = role == 'client' ? 'clientId' : 'workerId';
    return _firestore
        .collection('chats')
        .where(field, isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .where('lastSenderId', isNotEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}