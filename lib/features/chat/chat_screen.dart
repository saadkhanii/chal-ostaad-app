// lib/features/chat/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/chat_model.dart';
import '../../core/services/chat_service.dart';
import '../../shared/widgets/header_clipper.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String jobTitle;
  final String otherName;
  final String currentUserId;
  final String otherUserId;
  final String otherRole;

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
  final ChatService            _chatService = ChatService();
  final TextEditingController  _msgCtrl     = TextEditingController();
  final ScrollController       _scrollCtrl  = ScrollController();

  bool    _isSending      = false;
  String? _otherPhotoBase64;
  DateTime? _otherLastSeen;

  // ── Voice recording ──────────────────────────────────────────
  final AudioRecorder _recorder      = AudioRecorder();
  bool    _isRecording               = false;
  bool    _isSendingVoice            = false;
  String? _recordingPath;
  int     _recordingSeconds          = 0;
  Timer?  _recordingTimer;

  // ── Per-message audio players ─────────────────────────────────
  final Map<String, AudioPlayer> _players     = {};
  final Map<String, bool>        _playingMap  = {};
  final Map<String, Duration>    _progressMap = {};
  final Map<String, Duration>    _durationMap = {};

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _loadOtherUser();
    _msgCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _recordingTimer?.cancel();
    _recorder.dispose();
    for (final p in _players.values) p.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    await _chatService.markAsRead(
      chatId:        widget.chatId,
      currentUserId: widget.currentUserId,
    );
  }

  Future<void> _loadOtherUser() async {
    try {
      final collection = widget.otherRole == 'worker' ? 'workers' : 'clients';
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(widget.otherUserId)
          .get();
      if (doc.exists) {
        final info = (doc.data()?['personalInfo']) as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _otherPhotoBase64 = info['photoBase64'] as String?;
          });
        }
      }
    } catch (_) {}
  }

  // ── Text send ─────────────────────────────────────────────────
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
        _msgCtrl.text = text;
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Voice recording ───────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_isRecording) { await _stopAndSendVoice(); return; }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('chat.microphone_permission'.tr()),
        backgroundColor: CColors.error,
      ));
      return;
    }

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

    final started = await _recorder.isRecording();
    if (!started) return;

    _recordingSeconds = 0;
    _recordingTimer   = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds++);
    });

    if (mounted) setState(() { _isRecording = true; _recordingPath = path; });
  }

  Future<void> _stopAndSendVoice() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final capturedSeconds = _recordingSeconds;
    final capturedPath    = _recordingPath;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final stillRecording = await _recorder.isRecording();
    String? path;
    if (stillRecording) {
      path = await _recorder.stop();
    } else if (capturedPath != null && await File(capturedPath).exists()) {
      path = capturedPath;
    }

    if (!mounted) return;
    if (capturedSeconds < 1 || path == null) {
      setState(() { _isRecording = false; _isSendingVoice = false; _recordingPath = null; _recordingSeconds = 0; });
      return;
    }

    setState(() { _isRecording = false; _isSendingVoice = true; });

    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) throw Exception('Audio file is empty');
      await _chatService.sendVoiceMessage(
        chatId:      widget.chatId,
        senderId:    widget.currentUserId,
        audioBase64: base64Encode(bytes),
        durationMs:  capturedSeconds * 1000,
      );
      await File(path).delete();
      _scrollToBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to send voice: $e'),
        backgroundColor: CColors.error,
      ));
    } finally {
      if (mounted) setState(() { _isSendingVoice = false; _recordingPath = null; _recordingSeconds = 0; });
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    if (_recordingPath != null) try { await File(_recordingPath!).delete(); } catch (_) {}
    if (mounted) setState(() { _isRecording = false; _recordingPath = null; _recordingSeconds = 0; });
  }

  // ── Audio playback ────────────────────────────────────────────
  Future<void> _togglePlayback(MessageModel msg) async {
    final msgId = msg.id;
    if (_playingMap[msgId] == true) {
      await _players[msgId]?.pause();
      if (mounted) setState(() => _playingMap[msgId] = false);
      return;
    }
    for (final entry in _playingMap.entries) {
      if (entry.value) { await _players[entry.key]?.pause(); if (mounted) setState(() => _playingMap[entry.key] = false); }
    }
    if (!_players.containsKey(msgId)) {
      final player = AudioPlayer();
      _players[msgId] = player;
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/voice_play_$msgId.m4a');
      await file.writeAsBytes(base64Decode(msg.audioBase64!));
      await player.setFilePath(file.path);
      player.positionStream.listen((pos) { if (mounted) setState(() => _progressMap[msgId] = pos); });
      player.durationStream.listen((dur) { if (dur != null && mounted) setState(() => _durationMap[msgId] = dur); });
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) { setState(() { _playingMap[msgId] = false; _progressMap[msgId] = Duration.zero; }); _players[msgId]?.seek(Duration.zero); }
        }
      });
    }
    await _players[msgId]?.play();
    if (mounted) setState(() => _playingMap[msgId] = true);
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

  String _formatDuration(int ms) {
    final s = (ms / 1000).round();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _formatDurationObj(Duration d) {
    final s = d.inSeconds.clamp(0, 9999);
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : const Color(0xFFF5F5F5),
      body: Column(
        children: [
          _buildHeader(isDark),
          Expanded(child: _buildMessagesList(isDark)),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  // ── Header with curved wave shape ────────────────────────────
  Widget _buildHeader(bool isDark) {
    ImageProvider? img;
    if (_otherPhotoBase64 != null && _otherPhotoBase64!.isNotEmpty) {
      try { img = MemoryImage(base64Decode(_otherPhotoBase64!)); } catch (_) {}
    }

    final initials = widget.otherName.trim().isNotEmpty
        ? widget.otherName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    final topPad = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: topPad + 90,
      child: Stack(
        children: [
          // ── Wavy orange background ──────────────────────────
          Positioned.fill(
            child: ClipPath(
              clipper: HeaderClipper(),
              child: Container(color: CColors.primary),
            ),
          ),

          // ── Content ────────────────────────────────────────
          Positioned(
            top:   topPad,
            left:  0,
            right: 0,
            child: SizedBox(
              height: 68,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Back button
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white : CColors.secondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),

                  // Avatar with online ring
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? Colors.white : CColors.secondary, width: 2),
                        ),
                        child: CircleAvatar(
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
                      ),
                      // Online dot
                      Positioned(
                        bottom: 1, right: 1,
                        child: Container(
                          width: 11, height: 11,
                          decoration: BoxDecoration(
                            color:  const Color(0xFF44D97E),
                            shape:  BoxShape.circle,
                            border: Border.all(color: isDark ? Colors.white : CColors.secondary, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Name + subtitle
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.otherName,
                          style: TextStyle(
                            color:      isDark ? Colors.white : CColors.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize:   16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.jobTitle,
                          style: TextStyle(
                            color:    isDark ? Colors.white.withOpacity(0.85) : CColors.secondary.withOpacity(0.8),
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
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages list ─────────────────────────────────────────────
  Widget _buildMessagesList(bool isDark) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.messagesStream(widget.chatId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 48, color: CColors.grey),
                const SizedBox(height: 12),
                Text('chat.say_hello'.tr(),
                    style: TextStyle(color: CColors.darkGrey, fontSize: 14)),
              ],
            ),
          );
        }

        final messages = snapshot.data!.docs
            .map((doc) => MessageModel.fromSnapshot(doc))
            .toList();

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller:  _scrollCtrl,
          padding: const EdgeInsets.symmetric(
              horizontal: CSizes.defaultSpace, vertical: CSizes.md),
          itemCount:   messages.length,
          itemBuilder: (context, index) {
            final msg      = messages[index];
            final isMine   = msg.senderId == widget.currentUserId;
            final showTime = index == messages.length - 1 ||
                messages[index + 1].senderId != msg.senderId;

            // Date separator
            final showDate = index == 0 ||
                !_isSameDay(messages[index - 1].timestamp.toDate(),
                    msg.timestamp.toDate());

            return Column(
              children: [
                if (showDate) _buildDateSeparator(msg.timestamp.toDate(), isDark),
                msg.isVoice
                    ? _buildVoiceBubble(msg, isMine, showTime, isDark)
                    : _buildBubble(msg, isMine, showTime, isDark),
              ],
            );
          },
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;

  Widget _buildDateSeparator(DateTime date, bool isDark) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(date.year, date.month, date.day);
    String label;
    if (d == today) {
      label = 'Today';
    } else if (d == today.subtract(const Duration(days: 1))) {
      label = 'Yesterday';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: CColors.grey.withOpacity(0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:        isDark
                    ? CColors.darkContainer
                    : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color:    CColors.darkGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: CColors.grey.withOpacity(0.3))),
        ],
      ),
    );
  }

  // ── Text bubble ───────────────────────────────────────────────
  Widget _buildBubble(MessageModel msg, bool isMine, bool showTime, bool isDark) {
    final time = _formatTime(msg.timestamp.toDate());

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine) ...[
                _buildSmallAvatar(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.70,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMine
                        ? CColors.primary
                        : (isDark ? Colors.white : CColors.secondary),
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(20),
                      topRight:    const Radius.circular(20),
                      bottomLeft:  Radius.circular(isMine ? 20 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.07),
                        blurRadius: 6,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isMine
                          ? Colors.white
                          : (isDark ? CColors.textPrimary : Colors.white),
                      fontSize: 14.5,
                      height:   1.45,
                    ),
                  ),
                ),
              ),
              if (isMine) const SizedBox(width: 2),
            ],
          ),
          if (showTime) _buildTimestamp(time, isMine, msg.isRead, isDark),
        ],
      ),
    );
  }

  // ── Voice bubble ──────────────────────────────────────────────
  Widget _buildVoiceBubble(
      MessageModel msg, bool isMine, bool showTime, bool isDark) {
    final time      = _formatTime(msg.timestamp.toDate());
    final msgId     = msg.id;
    final isPlaying = _playingMap[msgId] ?? false;
    final progress  = _progressMap[msgId] ?? Duration.zero;
    final totalDur  = _durationMap[msgId] ??
        Duration(milliseconds: msg.audioDurationMs ?? 0);
    final sliderVal = totalDur.inMilliseconds > 0
        ? (progress.inMilliseconds / totalDur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final durLabel  = isPlaying
        ? _formatDurationObj(totalDur - progress)
        : _formatDuration(msg.audioDurationMs ?? 0);

    final bubbleColor = isMine
        ? CColors.primary
        : (isDark ? Colors.white : CColors.secondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine) ...[
                _buildSmallAvatar(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.70,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(20),
                      topRight:    const Radius.circular(20),
                      bottomLeft:  Radius.circular(isMine ? 20 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.07),
                        blurRadius: 6,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Play/pause
                      GestureDetector(
                        onTap: () => _togglePlayback(msg),
                        child: Container(
                          width:  40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isMine
                                ? Colors.white.withOpacity(0.2)
                                : (isDark ? CColors.primary.withOpacity(0.15) : Colors.white.withOpacity(0.25)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: isMine ? Colors.white : (isDark ? CColors.primary : Colors.white),
                            size:  24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight:        2.5,
                                thumbShape:         const RoundSliderThumbShape(
                                    enabledThumbRadius: 5),
                                overlayShape:       const RoundSliderOverlayShape(
                                    overlayRadius: 10),
                                activeTrackColor:   isMine
                                    ? Colors.white
                                    : (isDark ? CColors.primary : Colors.white),
                                inactiveTrackColor: isMine
                                    ? Colors.white.withOpacity(0.35)
                                    : (isDark ? CColors.primary.withOpacity(0.2) : Colors.white.withOpacity(0.4)),
                                thumbColor:         isMine
                                    ? Colors.white
                                    : (isDark ? CColors.primary : Colors.white),
                                overlayColor:       isMine
                                    ? Colors.white.withOpacity(0.15)
                                    : (isDark ? CColors.primary.withOpacity(0.15) : Colors.white.withOpacity(0.15)),
                              ),
                              child: Slider(
                                value: sliderVal,
                                onChanged: (v) {
                                  if (_players[msgId] != null &&
                                      totalDur.inMilliseconds > 0) {
                                    _players[msgId]!.seek(Duration(
                                        milliseconds:
                                        (v * totalDur.inMilliseconds).round()));
                                  }
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 2),
                              child: Text(
                                durLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMine
                                      ? Colors.white.withOpacity(0.8)
                                      : (isDark ? CColors.darkGrey : Colors.white.withOpacity(0.8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isMine) const SizedBox(width: 2),
            ],
          ),
          if (showTime) _buildTimestamp(time, isMine, msg.isRead, isDark),
        ],
      ),
    );
  }

  Widget _buildTimestamp(String time, bool isMine, bool isRead, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(
          top: 3, left: isMine ? 0 : 40, right: isMine ? 2 : 0),
      child: Row(
        mainAxisAlignment:
        isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(time,
              style: TextStyle(fontSize: 10.5, color: CColors.darkGrey)),
          if (isMine) ...[
            const SizedBox(width: 4),
            Icon(
              isRead ? Icons.done_all_rounded : Icons.done_rounded,
              size:  13,
              color: isRead ? CColors.primary : CColors.darkGrey,
            ),
          ],
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
      radius:          16,
      backgroundColor: CColors.secondary,
      backgroundImage: img,
      child: img == null
          ? Text(initials,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
          : null,
    );
  }

  // ── Input bar ─────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark) {
    if (_isRecording) return _buildRecordingBar(isDark);

    final hasText = _msgCtrl.text.trim().isNotEmpty;
    final showMic = !hasText && !_isSendingVoice;

    return Container(
      padding: EdgeInsets.only(
        left:   12,
        right:  12,
        top:    10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset:     const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color:        isDark ? CColors.dark : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller:         _msgCtrl,
                maxLines:           4,
                minLines:           1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:       'chat.type_message'.tr(),
                  hintStyle:      TextStyle(
                      color: CColors.darkGrey, fontSize: 14),
                  border:         InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Mic / Send button
          GestureDetector(
            onTap: showMic ? _startRecording : _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width:  48,
              height: 48,
              decoration: BoxDecoration(
                color:  CColors.primary,
                shape:  BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:      CColors.primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset:     const Offset(0, 3),
                  ),
                ],
              ),
              child: showMic
                  ? (_isSendingVoice
                  ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.mic_rounded,
                  color: Colors.white, size: 24))
                  : (_isSending
                  ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded,
                  color: Colors.white, size: 22)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recording strip ───────────────────────────────────────────
  Widget _buildRecordingBar(bool isDark) {
    final mins    = _recordingSeconds ~/ 60;
    final secs    = _recordingSeconds % 60;
    final timeStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Container(
      padding: EdgeInsets.only(
        left:   12,
        right:  12,
        top:    10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset:     const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cancel
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: CColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: CColors.error, size: 22),
            ),
          ),
          const SizedBox(width: 10),

          // Pulsing dot + timer
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color:        isDark ? CColors.dark : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(26),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildPulsingDot(),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: TextStyle(
                      color:      CColors.error,
                      fontSize:   15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'chat.recording'.tr(),
                      style: TextStyle(color: CColors.darkGrey, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Send
          GestureDetector(
            onTap: _stopAndSendVoice,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: CColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:      CColors.primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset:     const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      tween:    Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve:    Curves.easeInOut,
      builder:  (context, value, child) => Opacity(
        opacity: value,
        child: Container(
          width: 10, height: 10,
          decoration: const BoxDecoration(
            color: CColors.error, shape: BoxShape.circle,
          ),
        ),
      ),
      onEnd: () => setState(() {}),
    );
  }
}