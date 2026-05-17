// lib/features/chat/client_chat_inbox_screen.dart
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
  /// If provided, skips SharedPreferences lookup entirely.
  final String? userId;

  const ChatInboxScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true,
    this.userId,
  });

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  String _userId = '';
  static const String _role = 'client';
  final ChatService _chatService = ChatService();

  final Map<String, String> _avatarCache   = {};
  final Map<String, String> _nameCache     = {};
  final Set<String>         _fetchingIds   = {};
  final Set<String>         _fetchingNames = {};

  List<ChatModel> _cachedChats = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      if (mounted) setState(() => _userId = widget.userId!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _userId = prefs.getString('user_uid') ?? '');
    }
  }

  Future<void> _prefetchAvatar(String workerId) async {
    if (_avatarCache.containsKey(workerId) || _fetchingIds.contains(workerId)) return;
    _fetchingIds.add(workerId);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(workerId)
          .get();
      String photo = '';
      if (doc.exists) {
        final info = (doc.data()?['personalInfo']) as Map<String, dynamic>? ?? {};
        photo = (info['photoBase64'] as String?) ?? '';
        if (!_nameCache.containsKey(workerId)) {
          final name = (info['fullName'] as String?) ?? '';
          if (name.isNotEmpty) _nameCache[workerId] = name;
        }
      }
      _avatarCache[workerId] = photo;
      if (mounted) setState(() {});
    } catch (_) {
      _avatarCache[workerId] = '';
      if (mounted) setState(() {});
    } finally {
      _fetchingIds.remove(workerId);
    }
  }

  String _resolvedWorkerName(String storedName, String workerId) {
    final looksValid = storedName.isNotEmpty &&
        storedName.length < 28 &&
        !RegExp(r'^[A-Za-z0-9]{20,}$').hasMatch(storedName);
    if (looksValid) return storedName;
    return _nameCache[workerId] ?? storedName;
  }

  Future<void> _prefetchWorkerName(String workerId, String storedName) async {
    final looksValid = storedName.isNotEmpty &&
        storedName.length < 28 &&
        !RegExp(r'^[A-Za-z0-9]{20,}$').hasMatch(storedName);
    if (looksValid) return;
    if (_nameCache.containsKey(workerId) || _fetchingNames.contains(workerId)) return;
    _fetchingNames.add(workerId);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(workerId)
          .get();
      if (doc.exists) {
        final info = (doc.data()?['personalInfo']) as Map<String, dynamic>? ?? {};
        final name = (info['fullName'] as String?) ?? '';
        if (name.isNotEmpty) {
          _nameCache[workerId] = name;
          if (mounted) setState(() {});
        }
      }
    } catch (_) {
    } finally {
      _fetchingNames.remove(workerId);
    }
  }

  // ── Delete chat with confirmation ──────────────────────────────────
  Future<void> _confirmDeleteChat(ChatModel chat, String otherName) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? CColors.darkContainer : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: CColors.error, size: 22),
            const SizedBox(width: 8),
            Text(
              'chat.delete_chat'.tr(),
              style: TextStyle(
                fontSize:   17,
                fontWeight: FontWeight.bold,
                color:      isDark ? CColors.white : CColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'chat.delete_chat_confirm'.tr(args: [otherName]),
          style: TextStyle(
            fontSize: 14,
            color:    isDark ? CColors.grey : CColors.darkGrey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'common.cancel'.tr(),
              style: const TextStyle(color: CColors.darkGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'chat.delete'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _chatService.deleteChat(chat.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('chat.chat_deleted'.tr()),
            backgroundColor: CColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text('Failed to delete chat: $e'),
            backgroundColor: CColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Column(
      children: [
        CommonHeader(
          title: 'chat.inbox'.tr(),
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
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
        body: content,
      );
    }

    return ColoredBox(
      color: isDark ? CColors.dark : CColors.lightGrey,
      child: content,
    );
  }

  Widget _buildChatList(bool isDark) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(_userId),
      stream: _chatService.chatsStream(userId: _userId, role: _role),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cachedChats.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          _cachedChats = snapshot.data!.docs
              .map((doc) => ChatModel.fromSnapshot(doc))
              .toList();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final chat in _cachedChats) {
              _prefetchAvatar(chat.workerId);
              _prefetchWorkerName(chat.workerId, chat.workerName);
            }
          });
        }

        if (_cachedChats.isEmpty) return _buildEmpty(isDark);

        return ListView.separated(
          controller: widget.scrollController,
          padding:    const EdgeInsets.symmetric(vertical: CSizes.sm),
          itemCount:  _cachedChats.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 80,
            color:  isDark ? CColors.darkGrey : CColors.borderPrimary,
          ),
          itemBuilder: (context, index) =>
              _buildChatTile(_cachedChats[index], isDark),
        );
      },
    );
  }

  Widget _buildChatTile(ChatModel chat, bool isDark) {
    final isUnread  = !chat.isRead && chat.lastSenderId != _userId;
    final otherName = _resolvedWorkerName(chat.workerName, chat.workerId);
    final otherId   = chat.workerId;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId:        chat.id,
              jobTitle:      chat.jobTitle,
              otherName:     otherName,
              currentUserId: _userId,
              otherUserId:   otherId,
              otherRole:     'worker',
            ),
          ),
        );
      },
      onLongPress: () => _confirmDeleteChat(chat, otherName),
      child: Container(
        color: isUnread
            ? CColors.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: CSizes.defaultSpace, vertical: 12),
        child: Row(
          children: [
            _buildAvatar(otherName, otherId, isDark),
            const SizedBox(width: CSizes.md),
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
                    style: const TextStyle(
                      fontSize:   11,
                      color:      CColors.primary,
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
                              size:  14,
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
                                ? (isDark
                                ? CColors.white
                                : CColors.textPrimary)
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
            if (isUnread)
              Container(
                width:  10,
                height: 10,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: CColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, String otherId, bool isDark) {
    final cached = _avatarCache[otherId];

    ImageProvider? img;
    if (cached != null && cached.isNotEmpty) {
      try { img = MemoryImage(base64Decode(cached)); } catch (_) {}
    }

    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase()
        : '?';

    return CircleAvatar(
      radius:          26,
      backgroundColor: CColors.secondary,
      backgroundImage: img,
      child: img == null
          ? Text(
        initials,
        style: const TextStyle(
          color:      Colors.white,
          fontWeight: FontWeight.bold,
          fontSize:   16,
        ),
      )
          : null,
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 72, color: CColors.grey),
          const SizedBox(height: CSizes.md),
          Text(
            'chat.no_chats'.tr(),
            style: TextStyle(
              fontSize:   16,
              color:      CColors.darkGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Text(
            'chat.chats_appear_after_bid'.tr(),
            style:     TextStyle(fontSize: 13, color: CColors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}