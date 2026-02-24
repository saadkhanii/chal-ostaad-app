// lib/core/models/chat_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String id;         // jobId_workerId
  final String jobId;
  final String jobTitle;
  final String clientId;
  final String workerId;
  final String workerName;
  final String clientName;
  final String lastMessage;
  final Timestamp lastMessageTime;
  final String lastSenderId;
  final bool isRead;
  final Timestamp createdAt;

  ChatModel({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.clientId,
    required this.workerId,
    required this.workerName,
    required this.clientName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastSenderId,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ChatModel(
      id:              doc.id,
      jobId:           data['jobId']           ?? '',
      jobTitle:        data['jobTitle']         ?? '',
      clientId:        data['clientId']         ?? '',
      workerId:        data['workerId']         ?? '',
      workerName:      data['workerName']       ?? '',
      clientName:      data['clientName']       ?? '',
      lastMessage:     data['lastMessage']      ?? '',
      lastMessageTime: data['lastMessageTime']  ?? Timestamp.now(),
      lastSenderId:    data['lastSenderId']     ?? '',
      isRead:          data['isRead']           ?? true,
      createdAt:       data['createdAt']        ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId':           jobId,
    'jobTitle':        jobTitle,
    'clientId':        clientId,
    'workerId':        workerId,
    'workerName':      workerName,
    'clientName':      clientName,
    'lastMessage':     lastMessage,
    'lastMessageTime': lastMessageTime,
    'lastSenderId':    lastSenderId,
    'isRead':          isRead,
    'createdAt':       createdAt,
  };

  // The other person's name from current user's perspective
  String otherPersonName(String currentUserId) =>
      currentUserId == clientId ? workerName : clientName;
}

class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final Timestamp timestamp;
  final bool isRead;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isRead,
  });

  factory MessageModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MessageModel(
      id:        doc.id,
      senderId:  data['senderId']  ?? '',
      text:      data['text']      ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      isRead:    data['isRead']    ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'senderId':  senderId,
    'text':      text,
    'timestamp': timestamp,
    'isRead':    isRead,
  };
}