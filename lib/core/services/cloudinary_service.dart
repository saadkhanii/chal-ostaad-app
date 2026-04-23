// lib/core/services/cloudinary_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CloudinaryService {
  // ── ⚙️  Your Cloudinary credentials ─────────────────────────────
  static const String _cloudName    = 'dtk7jx3bj';
  static const String _uploadPreset = 'chal_ostaad_unsigned';
  // ────────────────────────────────────────────────────────────────

  static const String _baseUrl =
      'https://api.cloudinary.com/v1_1/$_cloudName';

  static const Duration _imageTimeout = Duration(seconds: 60);
  static const Duration _videoTimeout = Duration(minutes: 3);

  /// Upload image with optional byte-level progress callback.
  /// [onProgress] receives a value from 0.0 to 1.0.
  Future<String> uploadImage(
      File file, {
        void Function(double progress)? onProgress,
      }) async {
    final sizeKb = await file.length() ~/ 1024;
    debugPrint('[Cloudinary] Uploading image — ${sizeKb}KB');
    return _upload(
      file,
      resourceType: 'image',
      timeout:      _imageTimeout,
      onProgress:   onProgress,
    );
  }

  /// Upload video with optional byte-level progress callback.
  /// [onProgress] receives a value from 0.0 to 1.0.
  Future<String> uploadVideo(
      File file, {
        void Function(double progress)? onProgress,
      }) async {
    final sizeMb = (await file.length()) / (1024 * 1024);
    debugPrint('[Cloudinary] Uploading video — ${sizeMb.toStringAsFixed(1)}MB');
    return _upload(
      file,
      resourceType: 'video',
      timeout:      _videoTimeout,
      onProgress:   onProgress,
    );
  }

  Future<String> _upload(
      File file, {
        required String resourceType,
        required Duration timeout,
        void Function(double progress)? onProgress,
      }) async {
    final uri = Uri.parse('$_baseUrl/$resourceType/upload');
    debugPrint('[Cloudinary] POST → $uri');

    late http.Response response;

    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder']        = 'chal_ostaad/jobs'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      // Track bytes sent for progress reporting
      final totalBytes = request.contentLength;
      int bytesSent    = 0;

      final streamed = await request.send().timeout(
        timeout,
        onTimeout: () => throw Exception(
          'Upload timed out after ${timeout.inSeconds}s — '
              'check your internet connection.',
        ),
      );

      // Stream the response while tracking progress
      final List<int> responseBytes = [];
      await for (final chunk in streamed.stream) {
        responseBytes.addAll(chunk);
        if (onProgress != null && totalBytes != null && totalBytes > 0) {
          bytesSent += chunk.length;
          // We use bytesSent as a proxy — goes 0→~0.9 during transfer,
          // then snaps to 1.0 when Firestore save completes.
          final progress = (bytesSent / totalBytes).clamp(0.0, 0.95);
          onProgress(progress);
        }
      }

      response = http.Response.bytes(
        responseBytes,
        streamed.statusCode,
        headers: streamed.headers,
      );
    } on SocketException {
      throw Exception('No internet connection. Please check your network.');
    } on Exception {
      rethrow;
    }

    debugPrint('[Cloudinary] Response ${response.statusCode}');

    if (response.statusCode != 200) {
      String reason = response.body;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        reason = (json['error'] as Map?)?.containsKey('message') == true
            ? json['error']['message'] as String
            : response.body;
      } catch (_) {}
      throw Exception(
          'Cloudinary upload failed [${response.statusCode}]: $reason');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final url  = data['secure_url'] as String?;

    if (url == null || url.isEmpty) {
      throw Exception(
          'Cloudinary returned no URL. Response: ${response.body}');
    }

    onProgress?.call(1.0); // snap to 100% on success
    debugPrint('[Cloudinary] ✓ Uploaded → $url');
    return url;
  }

  static bool isVideo(String url) {
    if (url.contains('/video/upload/')) return true;
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.mp4')  ||
        lower.endsWith('.mov')  ||
        lower.endsWith('.avi')  ||
        lower.endsWith('.webm');
  }
}