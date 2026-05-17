// lib/features/chat/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/chat_model.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/cloudinary_service.dart';
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
  final ChatService            _chatService      = ChatService();
  final CloudinaryService      _cloudinary       = CloudinaryService();
  final TextEditingController  _msgCtrl          = TextEditingController();
  final ScrollController       _scrollCtrl       = ScrollController();
  final ImagePicker            _picker           = ImagePicker();

  bool    _isSending      = false;
  bool    _isSendingMedia = false;
  double  _uploadProgress = 0.0;   // 0.0–1.0 for Cloudinary upload progress
  String? _otherPhotoBase64;

  // ── Cached ImageProvider so avatar never rebuilds during playback ──
  ImageProvider? _cachedAvatarImage;
  bool           _avatarLoaded = false;

  // ── Voice recording ──────────────────────────────────────────────
  final AudioRecorder _recorder      = AudioRecorder();
  bool    _isRecording               = false;
  bool    _isSendingVoice            = false;
  String? _recordingPath;
  int     _recordingSeconds          = 0;
  Timer?  _recordingTimer;

  // ── Per-message audio players ─────────────────────────────────────
  final Map<String, AudioPlayer>          _players       = {};
  final Map<String, bool>                 _playingMap    = {};
  final Map<String, Duration>             _progressMap   = {};
  final Map<String, Duration>             _durationMap   = {};

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
        final b64  = info['photoBase64'] as String?;
        ImageProvider? img;
        if (b64 != null && b64.isNotEmpty) {
          try { img = MemoryImage(base64Decode(b64)); } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _otherPhotoBase64  = b64;
            _cachedAvatarImage = img;
            _avatarLoaded      = true;
          });
        }
      } else {
        if (mounted) setState(() => _avatarLoaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _avatarLoaded = true);
    }
  }

  // ── Text send ─────────────────────────────────────────────────────
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

  // ── Media pick & send ─────────────────────────────────────────────
  Future<void> _pickAndSendImage() async {
    try {
      final xFile = await _picker.pickImage(
        source:        ImageSource.gallery,
        imageQuality:  80,
        maxWidth:      1280,
        maxHeight:     1280,
      );
      if (xFile == null || !mounted) return;
      await _sendMediaFile(File(xFile.path), 'image/jpeg');
    } catch (e) {
      if (mounted) _showError('Failed to pick image: $e');
    }
  }

  Future<void> _recordAndSendVideo() async {
    try {
      final xFile = await _picker.pickVideo(
        source:      ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (xFile == null || !mounted) return;
      await _sendMediaFile(File(xFile.path), 'video/mp4');
    } catch (e) {
      if (mounted) _showError('Failed to record video: $e');
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final xFile = await _picker.pickVideo(
        source:         ImageSource.gallery,
        maxDuration:    const Duration(seconds: 60),
      );
      if (xFile == null || !mounted) return;
      await _sendMediaFile(File(xFile.path), 'video/mp4');
    } catch (e) {
      if (mounted) _showError('Failed to pick video: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final xFile = await _picker.pickImage(
        source:       ImageSource.camera,
        imageQuality: 80,
        maxWidth:     1280,
        maxHeight:    1280,
      );
      if (xFile == null || !mounted) return;
      await _sendMediaFile(File(xFile.path), 'image/jpeg');
    } catch (e) {
      if (mounted) _showError('Failed to take photo: $e');
    }
  }

  Future<void> _sendMediaFile(File file, String mimeType) async {
    if (_isSendingMedia) return;
    setState(() { _isSendingMedia = true; _uploadProgress = 0.0; });
    try {
      final isVideo = mimeType.startsWith('video/');

      // Compress images before uploading
      File fileToUpload = file;
      if (!isVideo) {
        final compressed = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          '${file.absolute.path}_compressed.jpg',
          quality: 70,
          minWidth: 800,
          minHeight: 800,
        );
        if (compressed != null) fileToUpload = File(compressed.path);
      }

      // Upload to Cloudinary — get back a URL, nothing goes to Firestore as bytes
      final String mediaUrl = isVideo
          ? await _cloudinary.uploadVideo(
        fileToUpload,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      )
          : await _cloudinary.uploadImage(
        fileToUpload,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      await _chatService.sendMediaMessage(
        chatId:    widget.chatId,
        senderId:  widget.currentUserId,
        mediaUrl:  mediaUrl,
        mediaType: isVideo ? 'video' : 'image',
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) _showError('Failed to send media: $e');
    } finally {
      if (mounted) setState(() { _isSendingMedia = false; _uploadProgress = 0.0; });
    }
  }

  // ── Long-press message options ────────────────────────────────────
  // Delete for everyone only within 60 min of sending (WhatsApp-style).
  static const Duration _deleteForEveryoneWindow = Duration(minutes: 2);

  bool _canDeleteForEveryone(MessageModel msg) {
    final age = DateTime.now().difference(msg.timestamp.toDate());
    return age <= _deleteForEveryoneWindow;
  }

  void _showMessageOptions(MessageModel msg, bool isDark, {required bool isMine}) {
    final canEdit         = isMine && msg.type == MessageType.text;
    final canDeleteForAll = isMine && _canDeleteForEveryone(msg);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? CColors.darkContainer : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: CColors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (canEdit)
                _sheetTile(
                  icon:   Icons.edit_rounded,
                  color:  CColors.primary,
                  label:  'Edit Message',
                  isDark: isDark,
                  onTap:  () { Navigator.pop(context); _showEditDialog(msg, isDark); },
                ),
              // Delete for everyone — only within 2-minute window
              if (canDeleteForAll)
                _sheetTile(
                  icon:   Icons.delete_sweep_rounded,
                  color:  CColors.error,
                  label:  'Delete for Everyone',
                  isDark: isDark,
                  onTap:  () { Navigator.pop(context); _confirmDelete(msg, forEveryone: true); },
                ),
              // Delete for me — always available
              _sheetTile(
                icon:   Icons.delete_outline_rounded,
                color:  CColors.error,
                label:  canDeleteForAll ? 'Delete for Me' : 'Delete',
                isDark: isDark,
                onTap:  () { Navigator.pop(context); _confirmDelete(msg, forEveryone: false); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required Color color,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize:   15,
          fontWeight: FontWeight.w500,
          color: color == CColors.error
              ? CColors.error
              : (isDark ? CColors.white : CColors.textPrimary),
        ),
      ),
      onTap: onTap,
    );
  }

  void _showEditDialog(MessageModel msg, bool isDark) {
    final ctrl = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? CColors.darkContainer : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Message',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? CColors.white : CColors.textPrimary,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Edit your message…',
            hintStyle: TextStyle(color: CColors.darkGrey),
            filled: true,
            fillColor: isDark ? CColors.dark : const Color(0xFFF0F0F0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: CColors.darkGrey)),
          ),
          TextButton(
            onPressed: () async {
              final newText = ctrl.text.trim();
              if (newText.isEmpty || newText == msg.text) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              try {
                await _chatService.editMessage(
                  chatId:    widget.chatId,
                  messageId: msg.id,
                  newText:   newText,
                );
              } catch (e) {
                if (mounted) _showError('Failed to edit: $e');
              }
            },
            child: Text('Save',
                style: TextStyle(
                    color: CColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(MessageModel msg, {required bool forEveryone}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? CColors.darkContainer : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          forEveryone ? 'Delete for Everyone' : 'Delete for Me',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? CColors.white : CColors.textPrimary,
          ),
        ),
        content: Text(
          forEveryone
              ? 'This message will be deleted for everyone in this chat.'
              : 'This message will be deleted only for you.',
          style: TextStyle(color: CColors.darkGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: CColors.darkGrey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _chatService.deleteMessage(
                  chatId:       widget.chatId,
                  messageId:    msg.id,
                  forEveryone:  forEveryone,
                  currentUserId: widget.currentUserId,
                );
              } catch (e) {
                if (mounted) _showError('Failed to delete: $e');
              }
            },
            child: Text('Delete',
                style: TextStyle(
                    color: CColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: CColors.error),
    );
  }

  void _showAttachmentSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context:       context,
      backgroundColor: isDark ? CColors.darkContainer : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: CColors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _attachOption(
                icon:  Icons.photo_library_rounded,
                label: 'chat.photo_from_gallery'.tr(),
                color: CColors.primary,
                onTap: () { Navigator.pop(context); _pickAndSendImage(); },
              ),
              _attachOption(
                icon:  Icons.camera_alt_rounded,
                label: 'chat.take_photo'.tr(),
                color: Colors.teal,
                onTap: () { Navigator.pop(context); _takePhoto(); },
              ),
              _attachOption(
                icon:  Icons.videocam_rounded,
                label: 'Record Video',
                color: Colors.orange,
                onTap: () { Navigator.pop(context); _recordAndSendVideo(); },
              ),
              _attachOption(
                icon:  Icons.video_library_rounded,
                label: 'chat.video_from_gallery'.tr(),
                color: Colors.deepPurple,
                onTap: () { Navigator.pop(context); _pickAndSendVideo(); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color:    isDark ? CColors.white : CColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  // ── Voice recording ───────────────────────────────────────────────
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

  // ── Audio playback ────────────────────────────────────────────────
  Future<void> _togglePlayback(MessageModel msg) async {
    final msgId = msg.id;
    if (_playingMap[msgId] == true) {
      await _players[msgId]?.pause();
      if (mounted) setState(() => _playingMap[msgId] = false);
      return;
    }
    for (final entry in _playingMap.entries) {
      if (entry.value) {
        await _players[entry.key]?.pause();
        if (mounted) setState(() => _playingMap[entry.key] = false);
      }
    }
    if (!_players.containsKey(msgId)) {
      final player = AudioPlayer();
      _players[msgId] = player;
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/voice_play_$msgId.m4a');
      await file.writeAsBytes(base64Decode(msg.audioBase64!));
      await player.setFilePath(file.path);
      player.positionStream.listen((pos) {
        if (mounted) setState(() => _progressMap[msgId] = pos);
      });
      player.durationStream.listen((dur) {
        if (dur != null && mounted) setState(() => _durationMap[msgId] = dur);
      });
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _playingMap[msgId]  = false;
              _progressMap[msgId] = Duration.zero;
            });
            _players[msgId]?.seek(Duration.zero);
          }
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

  // ── Build ─────────────────────────────────────────────────────────
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

  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    // Use the cached provider — built once, never re-decoded on setState
    final img      = _cachedAvatarImage;
    final initials = widget.otherName.trim().isNotEmpty
        ? widget.otherName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    final topPad = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: topPad + 90,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: HeaderClipper(),
              child: Container(color: CColors.primary),
            ),
          ),
          Positioned(
            top:   topPad,
            left:  0,
            right: 0,
            child: SizedBox(
              height: 68,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white : CColors.secondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isDark ? Colors.white : CColors.secondary,
                              width: 2),
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
                                  fontSize:   14))
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 1, right: 1,
                        child: Container(
                          width: 11, height: 11,
                          decoration: BoxDecoration(
                            color:  const Color(0xFF44D97E),
                            shape:  BoxShape.circle,
                            border: Border.all(
                                color: isDark ? Colors.white : CColors.secondary,
                                width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
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
                          widget.jobTitle.trim().split(' ').take(2).join(' '),
                          style: TextStyle(
                            color:    isDark
                                ? Colors.white.withValues(alpha: 0.85)
                                : CColors.secondary.withValues(alpha: 0.8),
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

  // ── Messages list ─────────────────────────────────────────────────
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
            .where((m) => !m.isDeletedFor(widget.currentUserId))
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
            final showDate = index == 0 ||
                !_isSameDay(messages[index - 1].timestamp.toDate(),
                    msg.timestamp.toDate());

            return Column(
              children: [
                if (showDate) _buildDateSeparator(msg.timestamp.toDate(), isDark),
                if (msg.isVoice)
                  _wrapWithLongPress(
                    msg: msg, isMine: isMine, isDark: isDark,
                    child: _buildVoiceBubble(msg, isMine, showTime, isDark),
                  )
                else if (msg.isImage || msg.isVideo)
                  _wrapWithLongPress(
                    msg: msg, isMine: isMine, isDark: isDark,
                    child: _buildMediaBubble(msg, isMine, showTime, isDark),
                  )
                else
                  _wrapWithLongPress(
                    msg: msg, isMine: isMine, isDark: isDark,
                    child: _buildBubble(msg, isMine, showTime, isDark),
                  ),
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
          Expanded(child: Divider(color: CColors.grey.withValues(alpha: 0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:        isDark
                    ? CColors.darkContainer
                    : Colors.white.withValues(alpha: 0.8),
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
          Expanded(child: Divider(color: CColors.grey.withValues(alpha: 0.3))),
        ],
      ),
    );
  }

  // ── Long-press wrapper — available on all messages ───────────────
  Widget _wrapWithLongPress({
    required MessageModel msg,
    required bool isMine,
    required bool isDark,
    required Widget child,
  }) {
    return GestureDetector(
      onLongPress: () => _showMessageOptions(msg, isDark, isMine: isMine),
      child: child,
    );
  }

  // ── Text bubble ───────────────────────────────────────────────────
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
                        color:      Colors.black.withValues(alpha: 0.07),
                        blurRadius: 6,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.text,
                        style: TextStyle(
                          color: isMine
                              ? Colors.white
                              : (isDark ? CColors.textPrimary : Colors.white),
                          fontSize: 14.5,
                          height:   1.45,
                        ),
                      ),
                      if (msg.edited) ...[
                        const SizedBox(height: 2),
                        Text(
                          'edited',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: isMine
                                ? Colors.white.withValues(alpha: 0.65)
                                : (isDark
                                ? CColors.darkGrey
                                : Colors.white.withValues(alpha: 0.65)),
                          ),
                        ),
                      ],
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

  // ── Media bubble (image / video) ──────────────────────────────────
  Widget _buildMediaBubble(
      MessageModel msg, bool isMine, bool showTime, bool isDark) {
    final time = _formatTime(msg.timestamp.toDate());

    Widget mediaContent;
    if (msg.isImage && msg.mediaUrl != null) {
      mediaContent = ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft:     const Radius.circular(18),
          topRight:    const Radius.circular(18),
          bottomLeft:  Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        child: GestureDetector(
          onTap: () => _openImageFullscreen(msg.mediaUrl!),
          child: Image.network(
            msg.mediaUrl!,
            fit:    BoxFit.cover,
            width:  220,
            height: 200,
            gaplessPlayback: true,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                width: 220, height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CColors.primary,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 220, height: 200,
              child: Center(child: Icon(Icons.broken_image_outlined,
                  size: 48, color: Colors.white54)),
            ),
          ),
        ),
      );
    } else if (msg.isVideo && msg.mediaUrl != null) {
      final thumbUrl = msg.mediaUrl!
          .replaceFirst('/upload/', '/upload/so_0,w_440,h_320,c_fill/')
          .replaceAll(RegExp(r'\.(mp4|mov|avi|webm)$', caseSensitive: false), '.jpg');

      mediaContent = GestureDetector(
        onTap: () => _openVideoUrl(msg.mediaUrl!, msg.id),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(18),
            topRight:    const Radius.circular(18),
            bottomLeft:  Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.network(
                thumbUrl,
                width:  220,
                height: 160,
                fit:    BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 220, height: 160,
                  color: Colors.black54,
                ),
              ),
              Container(
                width: 220, height: 160,
                color: Colors.black26,
              ),
              const Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 56),
            ],
          ),
        ),
      );
    } else {
      mediaContent = const SizedBox.shrink();
    }

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
              mediaContent,
              if (isMine) const SizedBox(width: 2),
            ],
          ),
          if (showTime) _buildTimestamp(time, isMine, msg.isRead, isDark),
        ],
      ),
    );
  }

  void _openImageFullscreen(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openVideoUrl(String url, String msgId) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _BetterVideoDialog(url: url),
    );
  }

  // ── Voice bubble ──────────────────────────────────────────────────
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
                // ── FIX: Use RepaintBoundary + const-keyed widget so
                //    audio progress setState never triggers an avatar
                //    re-decode/repaint. ────────────────────────────
                RepaintBoundary(child: _buildSmallAvatar()),
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
                        color:      Colors.black.withValues(alpha: 0.07),
                        blurRadius: 6,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _togglePlayback(msg),
                        child: Container(
                          width:  40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isMine
                                ? Colors.white.withValues(alpha: 0.2)
                                : (isDark
                                ? CColors.primary.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.25)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: isMine
                                ? Colors.white
                                : (isDark ? CColors.primary : Colors.white),
                            size: 24,
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
                                    ? Colors.white.withValues(alpha: 0.35)
                                    : (isDark
                                    ? CColors.primary.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.4)),
                                thumbColor: isMine
                                    ? Colors.white
                                    : (isDark ? CColors.primary : Colors.white),
                                overlayColor: isMine
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : (isDark
                                    ? CColors.primary.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.15)),
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
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : (isDark
                                      ? CColors.darkGrey
                                      : Colors.white.withValues(alpha: 0.8)),
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

  // ── Small avatar — uses pre-decoded _cachedAvatarImage ────────────
  // The key fix: we do NOT decode base64 here. The ImageProvider is
  // built once in _loadOtherUser() and reused. No blink on setState.
  Widget _buildSmallAvatar() {
    final img      = _cachedAvatarImage;
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

  // ── Input bar ─────────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark) {
    if (_isRecording) return _buildRecordingBar(isDark);

    final hasText  = _msgCtrl.text.trim().isNotEmpty;
    final showMic  = !hasText && !_isSendingVoice && !_isSendingMedia;
    final isBusy   = _isSending || _isSendingVoice || _isSendingMedia;

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
            color:      Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset:     const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Attachment button ──────────────────────────────────
          GestureDetector(
            onTap: _isSendingMedia ? null : _showAttachmentSheet,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width:  42,
              height: 42,
              margin: const EdgeInsets.only(right: 6, bottom: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? CColors.dark
                    : const Color(0xFFF0F0F0),
                shape: BoxShape.circle,
              ),
              child: _isSendingMedia
                  ? Padding(
                padding: const EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CColors.primary,
                  value: _uploadProgress > 0 ? _uploadProgress : null,
                ),
              )
                  : Icon(Icons.attach_file_rounded,
                  color: CColors.primary, size: 22),
            ),
          ),

          // ── Text field ─────────────────────────────────────────
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

          // ── Mic / Send button ──────────────────────────────────
          GestureDetector(
            onTap: isBusy ? null : (showMic ? _startRecording : _sendMessage),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width:  48,
              height: 48,
              decoration: BoxDecoration(
                color:  CColors.primary,
                shape:  BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:      CColors.primary.withValues(alpha: 0.35),
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

  // ── Recording strip ───────────────────────────────────────────────
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
            color:      Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset:     const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: CColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: CColors.error, size: 22),
            ),
          ),
          const SizedBox(width: 10),
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
          GestureDetector(
            onTap: _stopAndSendVoice,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: CColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:      CColors.primary.withValues(alpha: 0.35),
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

// ── Inline video player dialog (better_player) ────────────────────────────
class _BetterVideoDialog extends StatefulWidget {
  final String url;
  const _BetterVideoDialog({required this.url});

  @override
  State<_BetterVideoDialog> createState() => _BetterVideoDialogState();
}

class _BetterVideoDialogState extends State<_BetterVideoDialog> {
  late BetterPlayerController _controller;

  @override
  void initState() {
    super.initState();

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.url,
      cacheConfiguration: const BetterPlayerCacheConfiguration(
        useCache:              true,
        maxCacheSize:          100 * 1024 * 1024,  // 100 MB disk cache
        maxCacheFileSize:      20  * 1024 * 1024,  // 20 MB per file
        preCacheSize:          5   * 1024 * 1024,  // pre-buffer 5 MB immediately
      ),
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs:               5000,   // start playing after 5 s buffered
        maxBufferMs:               30000,  // keep up to 30 s ahead
        bufferForPlaybackMs:       2500,   // resume after rebuffer at 2.5 s
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
    );

    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay:          true,
        looping:           false,
        aspectRatio:       16 / 9,
        fit:               BoxFit.contain,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableFullscreen:    true,
          enableSkips:         false,
          enableMute:          true,
          enablePlayPause:     true,
          enableProgressBar:   true,
          progressBarPlayedColor:    CColors.primary,
          progressBarBufferedColor:  Colors.white30,
          progressBarBackgroundColor: Colors.white12,
          iconsColor:          Colors.white,
          controlBarColor:     Colors.black45,
          loadingColor:        CColors.primary,
        ),
        errorBuilder: (context, errorMessage) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white54, size: 56),
              const SizedBox(height: 12),
              Text(
                errorMessage ?? 'Could not load video',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      betterPlayerDataSource: dataSource,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: GestureDetector(
            onTap: () {}, // prevent tap-through
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tap outside to close',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: BetterPlayer(controller: _controller),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}