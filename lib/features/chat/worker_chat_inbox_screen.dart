// lib/features/chat/worker_chat_inbox_screen.dart
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

class WorkerChatInboxScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  /// Pass workerId directly from the dashboard (preferred).
  /// If null, falls back to SharedPreferences.
  final String? workerId;

  const WorkerChatInboxScreen({
    super.key,
    this.scrollController,
    this.showAppBar = true,
    this.workerId,
  });

  @override
  ConsumerState<WorkerChatInboxScreen> createState() =>
      _WorkerChatInboxScreenState();
}

class _WorkerChatInboxScreenState
    extends ConsumerState<WorkerChatInboxScreen> {
  String _workerId   = '';
  String _workerName = '';

  final ChatService _chatService = ChatService();
  final Map<String, String> _avatarCache  = {};
  final Set<String>         _fetchingIds  = {};
  List<ChatModel>           _cachedChats  = [];

  @override
  void initState() {
    super.initState();
    _loadWorkerInfo();
  }

  Future<void> _loadWorkerInfo() async {
    // Use passed-in workerId if available — no prefs hit needed.
    if (widget.workerId != null && widget.workerId!.isNotEmpty) {
      if (mounted) setState(() => _workerId = widget.workerId!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _workerId   = prefs.getString('user_uid')  ?? '';
        _workerName = prefs.getString('user_name') ?? '';
      });
    }
  }

  /// Fetch client avatar once and cache it.
  Future<void> _prefetchAvatar(String clientId) async {
    if (_avatarCache.containsKey(clientId) ||
        _fetchingIds.contains(clientId)) return;
    _fetchingIds.add(clientId);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .get();
      String photo = '';
      if (doc.exists) {
        final info =
            (doc.data()?['personalInfo']) as Map<String, dynamic>? ?? {};
        photo = (info['photoBase64'] as String?) ?? '';
      }
      _avatarCache[clientId] = photo;
      if (mounted) setState(() {});
    } catch (_) {
      _avatarCache[clientId] = '';
      if (mounted) setState(() {});
    } finally {
      _fetchingIds.remove(clientId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Always use Scaffold — even when embedded in the dashboard.
    // The key fix for nav bar disappearing is NotificationListener below,
    // which re-shows the nav bar whenever the user scrolls UP or when
    // the list is too short to scroll (overscroll at top).
    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'chat.inbox'.tr(),
            showBackButton: widget.showAppBar,
            onBackPressed:
            widget.showAppBar ? () => Navigator.pop(context) : null,
          ),
          Expanded(
            child: _workerId.isEmpty
                ? _buildEmpty(isDark)
                : _buildChatList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(bool isDark) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // ValueKey ensures a fresh Firestore subscription whenever
      // _workerId changes (async load from prefs on first open).
      key: ValueKey(_workerId),
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('workerId', isEqualTo: _workerId) // always worker field
          .orderBy('lastMessageTime', descending: true)
          .snapshots(),
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
              _prefetchAvatar(chat.clientId);
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
    final isUnread  = !chat.isRead && chat.lastSenderId != _workerId;
    // From worker's perspective, the other person is always the client
    final otherName = chat.clientName;
    final clientId  = chat.clientId;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId:        chat.id,
              jobTitle:      chat.jobTitle,
              otherName:     otherName,
              currentUserId: _workerId,
              otherUserId:   clientId,
              otherRole:     'client',
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
            _buildAvatar(otherName, clientId, isDark),
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
                          fontSize:   11,
                          color:      isUnread
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
                      if (chat.lastSenderId == _workerId)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.done_all,
                            size:  14,
                            color: chat.isRead
                                ? CColors.primary
                                : CColors.darkGrey,
                          ),
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
                  color:  CColors.primary,
                  shape:  BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, String clientId, bool isDark) {
    final cached = _avatarCache[clientId];

    ImageProvider? img;
    if (cached != null && cached.isNotEmpty) {
      try {
        img = MemoryImage(base64Decode(cached));
      } catch (_) {}
    }

    final initials = name.trim().isNotEmpty
        ? name
        .trim()
        .split(' ')
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