// lib/core/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String getChatId(String jobId, String workerId) => '${jobId}_$workerId';

  // ── Create or get existing chat ────────────────────────────────
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
    } else {
      final existing         = doc.data()!;
      final storedWorkerName = existing['workerName'] as String? ?? '';
      final storedClientName = existing['clientName'] as String? ?? '';
      if (storedWorkerName != workerName || storedClientName != clientName) {
        await ref.update({'workerName': workerName, 'clientName': clientName});
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
        .collection('chats').doc(chatId).collection('messages').doc();

    batch.set(msgRef, {
      'senderId':  senderId,
      'text':      text.trim(),
      'timestamp': now,
      'isRead':    false,
      'type':      'text',
    });

    batch.set(
      _firestore.collection('chats').doc(chatId),
      {
        'lastMessage':     text.trim(),
        'lastMessageTime': now,
        'lastSenderId':    senderId,
        'isRead':          false,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ── Send a voice message (base64 — voice clips are tiny, ~20-200 KB) ──
  Future<void> sendVoiceMessage({
    required String chatId,
    required String senderId,
    required String audioBase64,
    required int durationMs,
  }) async {
    final batch = _firestore.batch();
    final now   = Timestamp.now();

    final msgRef = _firestore
        .collection('chats').doc(chatId).collection('messages').doc();

    batch.set(msgRef, {
      'senderId':        senderId,
      'text':            '🎤 Voice message',
      'timestamp':       now,
      'isRead':          false,
      'type':            'voice',
      'audioBase64':     audioBase64,
      'audioDurationMs': durationMs,
    });

    batch.set(
      _firestore.collection('chats').doc(chatId),
      {
        'lastMessage':     '🎤 Voice message',
        'lastMessageTime': now,
        'lastSenderId':    senderId,
        'isRead':          false,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ── Send an image or video message (Cloudinary URL) ────────────
  // The heavy upload happens in ChatScreen via CloudinaryService.
  // This method only writes the resulting URL + metadata to Firestore
  // — the document stays tiny (just a URL string).
  Future<void> sendMediaMessage({
    required String chatId,
    required String senderId,
    required String mediaUrl,    // Cloudinary secure_url
    required String mediaType,   // 'image' or 'video'
  }) async {
    final batch   = _firestore.batch();
    final now     = Timestamp.now();
    final preview = mediaType == 'video' ? '🎥 Video' : '📷 Photo';

    final msgRef = _firestore
        .collection('chats').doc(chatId).collection('messages').doc();

    batch.set(msgRef, {
      'senderId':  senderId,
      'text':      preview,
      'timestamp': now,
      'isRead':    false,
      'type':      mediaType,   // 'image' | 'video'
      'mediaUrl':  mediaUrl,
    });

    batch.set(
      _firestore.collection('chats').doc(chatId),
      {
        'lastMessage':     preview,
        'lastMessageTime': now,
        'lastSenderId':    senderId,
        'isRead':          false,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ── Mark messages as read ──────────────────────────────────────
  Future<void> markAsRead({
    required String chatId,
    required String currentUserId,
  }) async {
    final unread = await _firestore
        .collection('chats').doc(chatId).collection('messages')
        .where('isRead',    isEqualTo:    false)
        .where('senderId',  isNotEqualTo: currentUserId)
        .get();

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    batch.set(
      _firestore.collection('chats').doc(chatId),
      {'isRead': true},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  // ── Delete a single message ────────────────────────────────────
  // [forEveryone] = true  → hard-deletes the Firestore document (only within 2-min window, enforced in UI)
  // [forEveryone] = false → adds currentUserId to a `deletedFor` array so only that user stops seeing it
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    required bool   forEveryone,
    required String currentUserId,
  }) async {
    final msgRef = _firestore
        .collection('chats').doc(chatId).collection('messages').doc(messageId);

    if (forEveryone) {
      await msgRef.delete();
    } else {
      await msgRef.update({
        'deletedFor': FieldValue.arrayUnion([currentUserId]),
      });
    }

    // Refresh lastMessage in the chat document
    final remaining = await _firestore
        .collection('chats').doc(chatId).collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (remaining.docs.isNotEmpty) {
      final last = remaining.docs.first.data();
      await _firestore.collection('chats').doc(chatId).set(
        {
          'lastMessage':     last['text'] ?? '',
          'lastMessageTime': last['timestamp'],
          'lastSenderId':    last['senderId'] ?? '',
        },
        SetOptions(merge: true),
      );
    } else {
      await _firestore.collection('chats').doc(chatId).set(
        {'lastMessage': '', 'lastSenderId': ''},
        SetOptions(merge: true),
      );
    }
  }

  // ── Edit a text message ────────────────────────────────────────
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final msgRef = _firestore
        .collection('chats').doc(chatId).collection('messages').doc(messageId);

    await msgRef.update({
      'text':     newText.trim(),
      'edited':   true,
      'editedAt': Timestamp.now(),
    });

    // Keep lastMessage in sync if this was the last message
    final last = await _firestore
        .collection('chats').doc(chatId).collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (last.docs.isNotEmpty && last.docs.first.id == messageId) {
      await _firestore.collection('chats').doc(chatId).set(
        {'lastMessage': newText.trim()},
        SetOptions(merge: true),
      );
    }
  }

  // ── Delete a chat and all its messages ─────────────────────────
  // Note: Cloudinary media files are NOT deleted here — they live on
  // Cloudinary's servers. If you need cleanup, call the Cloudinary
  // Admin API separately (requires an authenticated server-side call).
  Future<void> deleteChat(String chatId) async {
    const batchSize = 100;
    QuerySnapshot<Map<String, dynamic>> snap;
    do {
      snap = await _firestore
          .collection('chats').doc(chatId).collection('messages')
          .limit(batchSize)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snap.docs) batch.delete(doc.reference);
      await batch.commit();
    } while (snap.docs.length == batchSize);

    await _firestore.collection('chats').doc(chatId).delete();
  }

  // ── Stream of messages ─────────────────────────────────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return _firestore
        .collection('chats').doc(chatId).collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // ── Stream of all chats for a user ────────────────────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> chatsStream({
    required String userId,
    required String role,
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
        .where(field,          isEqualTo:    userId)
        .where('isRead',       isEqualTo:    false)
        .where('lastSenderId', isNotEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}