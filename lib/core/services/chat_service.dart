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
    }

    return chatId;
  }

  // ── Send a message ─────────────────────────────────────────────
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final batch = _firestore.batch();
    final now   = Timestamp.now();

    // Add message to subcollection
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
    });

    // Update chat metadata
    final chatRef = _firestore.collection('chats').doc(chatId);
    batch.update(chatRef, {
      'lastMessage':     text.trim(),
      'lastMessageTime': now,
      'lastSenderId':    senderId,
      'isRead':          false,
    });

    await batch.commit();
  }

  // ── Mark messages as read ──────────────────────────────────────
  Future<void> markAsRead({
    required String chatId,
    required String currentUserId,
  }) async {
    // Mark unread messages from the other person as read
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

    // Mark chat as read
    batch.update(
      _firestore.collection('chats').doc(chatId),
      {'isRead': true},
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