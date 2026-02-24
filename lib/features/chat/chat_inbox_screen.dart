// lib/features/chat/chat_inbox_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/chat_model.dart';
import '../../core/services/chat_service.dart';
import '../../shared/widgets/common_header.dart';
import 'chat_screen.dart';

class ChatInboxScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  const ChatInboxScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true,
  });

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  String _userId = '';
  String _role   = '';
  String _userName = '';
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userId   = prefs.getString('user_uid')   ?? '';
        _role     = prefs.getString('user_role')  ?? 'client';
        _userName = prefs.getString('user_name')  ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'chat.inbox'.tr(),
            showBackButton: widget.showAppBar,
            onBackPressed:  widget.showAppBar
                ? () => Navigator.pop(context)
                : null,
          ),
          Expanded(
            child: _userId.isEmpty
                ? _buildEmpty(isDark)
                : _buildChatList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(bool isDark) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.chatsStream(userId: _userId, role: _role),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmpty(isDark);
        }

        final chats = snapshot.data!.docs
            .map((doc) => ChatModel.fromSnapshot(doc))
            .toList();

        return ListView.separated(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(vertical: CSizes.sm),
          itemCount: chats.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 80,
            color: isDark ? CColors.darkGrey : CColors.borderPrimary,
          ),
          itemBuilder: (context, index) =>
              _buildChatTile(chats[index], isDark),
        );
      },
    );
  }

  Widget _buildChatTile(ChatModel chat, bool isDark) {
    final isUnread = !chat.isRead && chat.lastSenderId != _userId;
    final otherName = chat.otherPersonName(_userId);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId:      chat.id,
              jobTitle:    chat.jobTitle,
              otherName:   otherName,
              currentUserId: _userId,
              otherUserId:   _userId == chat.clientId
                  ? chat.workerId
                  : chat.clientId,
              otherRole: _role == 'client' ? 'worker' : 'client',
            ),
          ),
        );
      },
      child: Container(
        color: isUnread
            ? CColors.primary.withOpacity(0.05)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace, vertical: 12),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(otherName, chat, isDark),
            const SizedBox(width: CSizes.md),

            // Chat info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          otherName,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 15,
                            color: isDark
                                ? CColors.white
                                : CColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeago.format(chat.lastMessageTime.toDate()),
                        style: TextStyle(
                          fontSize: 11,
                          color: isUnread
                              ? CColors.primary
                              : CColors.darkGrey,
                          fontWeight: isUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chat.jobTitle,
                    style: TextStyle(
                      fontSize: 11,
                      color:    CColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (chat.lastSenderId == _userId)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.done_all,
                              size: 14,
                              color: chat.isRead
                                  ? CColors.primary
                                  : CColors.darkGrey),
                        ),
                      Expanded(
                        child: Text(
                          chat.lastMessage.isEmpty
                              ? 'chat.no_messages'.tr()
                              : chat.lastMessage,
                          style: TextStyle(
                            fontSize: 13,
                            color: isUnread
                                ? (isDark ? CColors.white : CColors.textPrimary)
                                : CColors.darkGrey,
                            fontWeight: isUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Unread dot
            if (isUnread)
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color:  CColors.primary,
                  shape:  BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, ChatModel chat, bool isDark) {
    // Try to load photo from Firestore for the other person
    final otherId = _userId == chat.clientId ? chat.workerId : chat.clientId;
    final otherCollection = _role == 'client' ? 'workers' : 'clients';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(otherCollection)
          .doc(otherId)
          .get(),
      builder: (context, snap) {
        String? photoBase64;
        if (snap.hasData && snap.data!.exists) {
          final info = (snap.data!.data()
          as Map<String, dynamic>?)?['personalInfo']
          as Map<String, dynamic>? ?? {};
          photoBase64 = info['photoBase64'] as String?;
        }

        ImageProvider? img;
        if (photoBase64 != null && photoBase64.isNotEmpty) {
          try { img = MemoryImage(base64Decode(photoBase64)); } catch (_) {}
        }

        final initials = name.trim().isNotEmpty
            ? name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '')
            .take(2).join().toUpperCase()
            : '?';

        return CircleAvatar(
          radius:          26,
          backgroundColor: CColors.secondary,
          backgroundImage: img,
          child: img == null
              ? Text(initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ))
              : null,
        );
      },
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 72, color: CColors.grey),
          const SizedBox(height: CSizes.md),
          Text(
            'chat.no_chats'.tr(),
            style: TextStyle(
              fontSize: 16,
              color:    CColors.darkGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            'chat.chats_appear_after_bid'.tr(),
            style: TextStyle(fontSize: 13, color: CColors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}