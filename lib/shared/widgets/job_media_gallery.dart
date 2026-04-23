// lib/shared/widgets/job_media_gallery.dart
//
// Displays a horizontal scrollable gallery of job media (images + videos).
// Tapping any item opens a full-screen viewer.
//
// Supports two data modes (automatically detected):
//   • NEW — mediaUrls + mediaTypes lists (Cloudinary URLs)
//   • LEGACY — mediaBase64 list (old base64 strings still in Firestore)
//
// Dependencies to add in pubspec.yaml:
//   video_player: ^2.9.2
//   cached_network_image: ^3.4.1   ← for fast image loading from URLs

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/services/cloudinary_service.dart';

class JobMediaGallery extends StatelessWidget {
  // ── New URL-based fields ─────────────────────────────────────────
  final List<String> mediaUrls;
  final List<String> mediaTypes; // 'image' | 'video' per URL

  // ── Legacy base64 fallback ───────────────────────────────────────
  final List<String> mediaBase64;

  const JobMediaGallery({
    super.key,
    this.mediaUrls   = const [],
    this.mediaTypes  = const [],
    this.mediaBase64 = const [],
  });

  bool get _hasUrlMedia   => mediaUrls.isNotEmpty;
  bool get _hasBase64Media => mediaBase64.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasUrlMedia && !_hasBase64Media) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count  = _hasUrlMedia ? mediaUrls.length : mediaBase64.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media',
          style: TextStyle(
            fontSize:   14,
            fontWeight: FontWeight.w600,
            color:      isDark ? CColors.light : CColors.dark,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (_hasUrlMedia) {
                final url     = mediaUrls[i];
                final isVideo = i < mediaTypes.length
                    ? mediaTypes[i] == 'video'
                    : CloudinaryService.isVideo(url);
                return _MediaThumb(
                  onTap: () => _openViewer(context, i),
                  child: isVideo
                      ? _VideoThumb(url: url)
                      : _ImageThumb(url: url),
                );
              } else {
                // Legacy base64
                return _MediaThumb(
                  onTap: () => _openViewerBase64(context, i),
                  child: _Base64ImageThumb(base64: mediaBase64[i]),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MediaViewerScreen(
          urls:         mediaUrls,
          types:        mediaTypes,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _openViewerBase64(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _Base64ViewerScreen(
          base64List:   mediaBase64,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// ── Thumbnail wrapper ─────────────────────────────────────────────────────
class _MediaThumb extends StatelessWidget {
  final Widget      child;
  final VoidCallback onTap;
  const _MediaThumb({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        child: SizedBox(width: 110, height: 110, child: child),
      ),
    );
  }
}

// ── Image thumbnail (network) ─────────────────────────────────────────────
class _ImageThumb extends StatelessWidget {
  final String url;
  const _ImageThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl:   url,
      fit:        BoxFit.cover,
      width:      110,
      height:     110,
      placeholder: (_, __) => Container(
        color: Colors.grey.shade200,
        child: const Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      errorWidget: (_, __, ___) => Container(
        color:  Colors.grey.shade300,
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
      ),
    );
  }
}

// ── Video thumbnail ───────────────────────────────────────────────────────
class _VideoThumb extends StatelessWidget {
  final String url;
  const _VideoThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black87),
      const Center(
        child: Icon(Icons.play_circle_fill_rounded,
            color: Colors.white, size: 40),
      ),
      Positioned(
        bottom: 4, right: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color:        Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('VIDEO',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }
}

// ── Legacy base64 thumbnail ───────────────────────────────────────────────
class _Base64ImageThumb extends StatelessWidget {
  final String base64;
  const _Base64ImageThumb({required this.base64});

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(base64);
      return Image.memory(bytes, fit: BoxFit.cover, width: 110, height: 110);
    } catch (_) {
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Full-screen viewer — URL-based
// ══════════════════════════════════════════════════════════════════════════
class _MediaViewerScreen extends StatefulWidget {
  final List<String> urls;
  final List<String> types;
  final int          initialIndex;

  const _MediaViewerScreen({
    required this.urls,
    required this.types,
    required this.initialIndex,
  });

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late PageController _pageController;
  late int            _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex  = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isVideo(int index) {
    if (index < widget.types.length) return widget.types[index] == 'video';
    return CloudinaryService.isVideo(widget.urls[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.urls.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount:  widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          return _isVideo(i)
              ? _FullScreenVideoPlayer(url: widget.urls[i])
              : _FullScreenImageView(url: widget.urls[i]);
        },
      ),
    );
  }
}

// ── Full-screen image ─────────────────────────────────────────────────────
class _FullScreenImageView extends StatelessWidget {
  final String url;
  const _FullScreenImageView({required this.url});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: CachedNetworkImage(
          imageUrl:   url,
          fit:        BoxFit.contain,
          placeholder: (_, __) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
          errorWidget: (_, __, ___) =>
          const Icon(Icons.broken_image_rounded, color: Colors.white, size: 64),
        ),
      ),
    );
  }
}

// ── Full-screen video player ──────────────────────────────────────────────
class _FullScreenVideoPlayer extends StatefulWidget {
  final String url;
  const _FullScreenVideoPlayer({required this.url});

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _error       = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
          SizedBox(height: 8),
          Text('Failed to load video',
              style: TextStyle(color: Colors.white)),
        ]),
      );
    }

    if (!_initialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        });
      },
      child: Stack(alignment: Alignment.center, children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
        ),
        // Play/pause overlay
        AnimatedOpacity(
          opacity: _controller.value.isPlaying ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding:    const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color:  Colors.black45,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 48),
          ),
        ),
        // Progress bar at bottom
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: VideoProgressIndicator(
            _controller,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor:   CColors.primary,
              bufferedColor: Colors.white30,
              backgroundColor: Colors.white12,
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Full-screen viewer — Legacy base64
// ══════════════════════════════════════════════════════════════════════════
class _Base64ViewerScreen extends StatefulWidget {
  final List<String> base64List;
  final int          initialIndex;
  const _Base64ViewerScreen(
      {required this.base64List, required this.initialIndex});

  @override
  State<_Base64ViewerScreen> createState() => _Base64ViewerScreenState();
}

class _Base64ViewerScreenState extends State<_Base64ViewerScreen> {
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.base64List.length}',
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        itemCount: widget.base64List.length,
        controller: PageController(initialPage: widget.initialIndex),
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) {
          try {
            final bytes = base64Decode(widget.base64List[i]);
            return InteractiveViewer(
              child: Center(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            );
          } catch (_) {
            return const Center(
              child: Icon(Icons.broken_image_rounded,
                  color: Colors.white, size: 64),
            );
          }
        },
      ),
    );
  }
}