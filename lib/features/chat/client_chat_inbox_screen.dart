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
  /// If provided, skips SharedPreferences lookup entirely.
  /// Pass this from the client dashboard which already knows the clientId.
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
  // Role is always 'client' — workers use WorkerChatInboxScreen instead.
  static const String _role = 'client';
  final ChatService _chatService = ChatService();

  // ── Avatar cache: avoids re-fetching on every stream rebuild ──
  // Key: other user's Firestore doc id → base64 string or empty string
  final Map<String, String> _avatarCache = {};

  // Track which IDs are currently being fetched to avoid duplicate calls
  final Set<String> _fetchingIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    // Use passed-in userId directly if available — no prefs hit needed.
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      if (mounted) setState(() => _userId = widget.userId!);
      return;
    }
    // Fallback: read from SharedPreferences (set during login).
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _userId = prefs.getString('user_uid') ?? '');
    }
  }

  /// Fetches a worker's photoBase64 once and stores it in [_avatarCache].
  /// Always looks in the 'workers' collection — clients chat with workers.
  Future<void> _prefetchAvatar(String workerId) async {
    if (_avatarCache.containsKey(workerId) || _fetchingIds.contains(workerId)) {
      return;
    }
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

  // Holds the last known good list so we never flash empty on a re-subscription
  List<ChatModel> _cachedChats = [];

  Widget _buildChatList(bool isDark) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // FIX: ValueKey forces the StreamBuilder to tear down and resubscribe
      // whenever _userId changes (e.g. after _loadUserInfo() completes async).
      // Without this, the stream was permanently bound to the empty-string
      // query from the very first build, so workers never saw their chats.
      key: ValueKey(_userId),
      stream: _chatService.chatsStream(userId: _userId, role: _role),
      builder: (context, snapshot) {
        // Only show spinner on the very first load
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cachedChats.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Update cache whenever we get real data
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          _cachedChats = snapshot.data!.docs
              .map((doc) => ChatModel.fromSnapshot(doc))
              .toList();

          // Prefetch worker avatars AFTER the current build frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final chat in _cachedChats) {
              _prefetchAvatar(chat.workerId);
            }
          });
        }

        // Use cached list — never drops to empty while cache has data
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
    // Client always talks to the worker — other person is always the worker
    final otherName = chat.workerName;
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
              otherRole:     'worker', // client always chats with a worker
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
            // Avatar — built from cache, no FutureBuilder inside list
            _buildAvatar(otherName, otherId, isDark),
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

            // Unread dot
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

  /// Builds avatar from [_avatarCache] — no async call, no FutureBuilder.
  /// Shows initials placeholder while the photo is still loading.
  Widget _buildAvatar(String name, String otherId, bool isDark) {
    final cached = _avatarCache[otherId]; // null = still loading, '' = no photo

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