// lib/features/chat/chat_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/chat_model.dart';
import '../../core/services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String jobTitle;
  final String otherName;
  final String currentUserId;
  final String otherUserId;
  final String otherRole; // 'worker' or 'client'

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.jobTitle,
    required this.otherName,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherRole,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService  = ChatService();
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl  = ScrollController();
  bool _isSending = false;
  String? _otherPhotoBase64;

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _loadOtherPhoto();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    await _chatService.markAsRead(
      chatId:        widget.chatId,
      currentUserId: widget.currentUserId,
    );
  }

  Future<void> _loadOtherPhoto() async {
    try {
      final collection = widget.otherRole == 'worker' ? 'workers' : 'clients';
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(widget.otherUserId)
          .get();
      if (doc.exists) {
        final info = (doc.data()?['personalInfo']) as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() => _otherPhotoBase64 = info['photoBase64'] as String?);
        }
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _msgCtrl.clear();

    try {
      await _chatService.sendMessage(
        chatId:   widget.chatId,
        senderId: widget.currentUserId,
        text:     text,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to send: $e'),
          backgroundColor: CColors.error,
        ));
        _msgCtrl.text = text; // restore text on failure
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          _buildHeader(isDark),
          Expanded(child: _buildMessagesList(isDark)),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    ImageProvider? img;
    if (_otherPhotoBase64 != null && _otherPhotoBase64!.isNotEmpty) {
      try { img = MemoryImage(base64Decode(_otherPhotoBase64!)); } catch (_) {}
    }

    final initials = widget.otherName.trim().isNotEmpty
        ? widget.otherName.trim().split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    return Container(
      padding: EdgeInsets.only(
        top:    MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        left:   8,
        right:  16,
      ),
      decoration: BoxDecoration(
        color: CColors.primary,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon:  const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),

          // Avatar
          CircleAvatar(
            radius:          22,
            backgroundColor: CColors.secondary,
            backgroundImage: img,
            child: img == null
                ? Text(initials,
                style: const TextStyle(
                  color:      Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize:   14,
                ))
                : null,
          ),
          const SizedBox(width: 12),

          // Name + job title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherName,
                  style: const TextStyle(
                    color:      Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize:   16,
                  ),
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                ),
                Text(
                  widget.jobTitle,
                  style: TextStyle(
                    color:    Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages list ──────────────────────────────────────────────
  Widget _buildMessagesList(bool isDark) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.messagesStream(widget.chatId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'chat.say_hello'.tr(),
              style: TextStyle(color: CColors.darkGrey, fontSize: 14),
            ),
          );
        }

        final messages = snapshot.data!.docs
            .map((doc) => MessageModel.fromSnapshot(doc))
            .toList();

        // Auto scroll to bottom on new messages
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollCtrl,
          padding:    const EdgeInsets.symmetric(
              horizontal: CSizes.defaultSpace, vertical: CSizes.md),
          itemCount:  messages.length,
          itemBuilder: (context, index) {
            final msg        = messages[index];
            final isMine     = msg.senderId == widget.currentUserId;
            final showTime   = index == messages.length - 1 ||
                messages[index + 1].senderId != msg.senderId;

            return _buildBubble(msg, isMine, showTime, isDark);
          },
        );
      },
    );
  }

  // ── Message bubble ─────────────────────────────────────────────
  Widget _buildBubble(
      MessageModel msg, bool isMine, bool showTime, bool isDark) {
    final time = _formatTime(msg.timestamp.toDate());

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Other person avatar (only on their messages)
              if (!isMine) ...[
                _buildSmallAvatar(),
                const SizedBox(width: 6),
              ],

              // Bubble
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMine
                        ? CColors.primary
                        : (isDark ? CColors.darkContainer : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isMine ? 18 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.06),
                        blurRadius: 4,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isMine
                          ? Colors.white
                          : (isDark ? CColors.white : CColors.textPrimary),
                      fontSize: 14,
                      height:   1.4,
                    ),
                  ),
                ),
              ),

              if (isMine) const SizedBox(width: 4),
            ],
          ),

          // Timestamp + read receipt
          if (showTime)
            Padding(
              padding: EdgeInsets.only(
                  top: 2,
                  left:  isMine ? 0 : 36,
                  right: isMine ? 4 : 0),
              child: Row(
                mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Text(time,
                      style: TextStyle(
                          fontSize: 10, color: CColors.darkGrey)),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      msg.isRead ? Icons.done_all : Icons.done,
                      size:  12,
                      color: msg.isRead ? CColors.primary : CColors.darkGrey,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSmallAvatar() {
    ImageProvider? img;
    if (_otherPhotoBase64 != null && _otherPhotoBase64!.isNotEmpty) {
      try { img = MemoryImage(base64Decode(_otherPhotoBase64!)); } catch (_) {}
    }
    final initials = widget.otherName.isNotEmpty
        ? widget.otherName[0].toUpperCase()
        : '?';

    return CircleAvatar(
      radius:          14,
      backgroundColor: CColors.secondary,
      backgroundImage: img,
      child: img == null
          ? Text(initials,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
          : null,
    );
  }

  // ── Input bar ──────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left:   CSizes.defaultSpace,
        right:  CSizes.sm,
        top:    8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset:     const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color:        isDark ? CColors.dark : CColors.lightGrey,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller:  _msgCtrl,
                maxLines:    4,
                minLines:    1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:      'chat.type_message'.tr(),
                  hintStyle:     TextStyle(color: CColors.darkGrey, fontSize: 14),
                  border:        InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width:  48,
              height: 48,
              decoration: BoxDecoration(
                color:  CColors.primary,
                shape:  BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:      CColors.primary.withOpacity(0.4),
                    blurRadius: 8,
                    offset:     const Offset(0, 2),
                  ),
                ],
              ),
              child: _isSending
                  ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
                  : const Icon(Icons.send_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}