// lib/features/client/post_job_screen.dart
import 'dart:io';

import 'package:chal_ostaad/core/models/job_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';
import '../../shared/widgets/Cbutton.dart';
import '../../shared/widgets/CtextField.dart';
import '../../shared/widgets/common_header.dart';

class Category {
  final String id;
  final String name;
  Category({required this.id, required this.name});
}

class PostJobScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  final VoidCallback? onJobPosted;

  const PostJobScreen({
    super.key,
    this.showAppBar = true,
    this.onJobPosted,
  });

  @override
  ConsumerState<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends ConsumerState<PostJobScreen> {
  final _formKey               = GlobalKey<FormState>();
  final _titleController       = TextEditingController();
  final _descriptionController = TextEditingController();
  final _mapService            = MapService();
  final _cloudinary            = CloudinaryService();

  String? _selectedCategoryId;
  bool    _isLoading            = false;
  List<Category> _categories    = [];
  bool    _isFetchingCategories = true;
  String? _clientId;
  String? _clientName;

  // ── Location state ───────────────────────────────────────────────
  GeoPoint? _jobLocation;
  String?   _jobLocationAddress;
  String?   _jobCity;
  // ────────────────────────────────────────────────────────────────

  // ── Media state (up to 3 items: images or videos) ────────────────
  final List<File>   _pickedFiles = [];
  final List<String> _mediaTypes  = []; // 'image' | 'video'
  static const int   _maxMedia    = 3;

  // ── Upload progress (drives the progress dialog) ─────────────────
  int    _uploadTotal   = 0;
  int    _uploadCurrent = 0;
  double _fileProgress  = 0.0;
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);
  // ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadClientInfo();
    _fetchCategories();
  }

  Future<void> _loadClientInfo() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final userUid  = prefs.getString('user_uid');
      final userName = prefs.getString('user_name') ?? 'A client';
      if (userUid != null && mounted) {
        setState(() {
          _clientId   = userUid;
          _clientName = userName;
        });
      }
    } catch (e) {
      debugPrint('Error loading client info: $e');
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('workCategories')
          .where('status', isEqualTo: 'active')
          .get();

      final categoriesData = snapshot.docs.map((doc) {
        return Category(
          id:   doc.id,
          name: doc.data()['name'] ?? 'job.unknown_category'.tr(),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _categories           = categoriesData;
          _isFetchingCategories = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      if (mounted) {
        setState(() => _isFetchingCategories = false);
        _showErrorMessage('errors.load_categories_failed'.tr());
      }
    }
  }

  // ── Pick image ───────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    if (_pickedFiles.length >= _maxMedia) {
      _showErrorMessage('Maximum $_maxMedia media items allowed.');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       source,
      maxWidth:     1280,
      maxHeight:    1280,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedFiles.add(File(picked.path));
      _mediaTypes.add('image');
    });
  }

  // ── Pick video ───────────────────────────────────────────────────
  Future<void> _pickVideo(ImageSource source) async {
    if (_pickedFiles.length >= _maxMedia) {
      _showErrorMessage('Maximum $_maxMedia media items allowed.');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source:            source,
      maxDuration: const Duration(seconds: 60), // keep videos short
    );
    if (picked == null || !mounted) return;

    // Warn if the file is very large (> 50 MB)
    final size = await File(picked.path).length();
    if (size > 50 * 1024 * 1024) {
      _showErrorMessage('Video is too large (max 50 MB). Please trim it first.');
      return;
    }

    setState(() {
      _pickedFiles.add(File(picked.path));
      _mediaTypes.add('video');
    });
  }

  void _removeMedia(int index) {
    setState(() {
      _pickedFiles.removeAt(index);
      _mediaTypes.removeAt(index);
    });
  }

  void _showMediaSourceDialog({required bool isVideo}) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(isVideo
                ? Icons.videocam_rounded
                : Icons.camera_alt_rounded),
            title: Text(isVideo ? 'Record Video' : 'Take a Photo'),
            onTap: () {
              Navigator.pop(context);
              isVideo
                  ? _pickVideo(ImageSource.camera)
                  : _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Icon(isVideo
                ? Icons.video_library_rounded
                : Icons.photo_library_rounded),
            title: Text(isVideo ? 'Choose Video from Gallery' : 'Choose from Gallery'),
            onTap: () {
              Navigator.pop(context);
              isVideo
                  ? _pickVideo(ImageSource.gallery)
                  : _pickImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  void _showAddMediaDialog() {
    if (_pickedFiles.length >= _maxMedia) {
      _showErrorMessage('Maximum $_maxMedia media items allowed.');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add Media',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.image_rounded),
            title:   const Text('Add Photo'),
            onTap: () {
              Navigator.pop(context);
              _showMediaSourceDialog(isVideo: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam_rounded),
            title:   const Text('Add Video'),
            subtitle: const Text('Max 60 sec · Max 50 MB'),
            onTap: () {
              Navigator.pop(context);
              _showMediaSourceDialog(isVideo: true);
            },
          ),
        ]),
      ),
    );
  }

  // ── Open map picker ──────────────────────────────────────────────
  Future<void> _openLocationPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _mapService.locationPickerScreen(
          initialLocation: _jobLocation,
          onLocationSelected: (geoPoint, address) async {
            setState(() {
              _jobLocation        = geoPoint;
              _jobLocationAddress = address;
            });
            if (address != null) {
              final parts = address.split(',');
              if (parts.length >= 2) {
                final city = parts[parts.length >= 3
                    ? parts.length - 3
                    : parts.length - 2]
                    .trim();
                if (mounted) setState(() => _jobCity = city);
              }
            }
          },
        ),
      ),
    );
  }

  // ── Upload progress helpers ──────────────────────────────────────
  void _showUploadDialog() {
    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(
        screen:           this,
        progressNotifier: _progressNotifier,
      ),
    );
  }

  void _updateProgress(int current, int total, double fileProgress) {
    if (!mounted) return;
    setState(() {
      _uploadCurrent = current;
      _uploadTotal   = total;
      _fileProgress  = fileProgress;
    });
    // Update notifier so the dialog rebuilds with latest progress
    final overall = total == 0 ? 0.0 : ((current - 1) + fileProgress) / total;
    _progressNotifier.value = overall.clamp(0.0, 1.0);
  }

  // ── Submit job ───────────────────────────────────────────────────
  Future<void> _handlePostJob() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategoryId == null) {
      _showErrorMessage('job.category_required'.tr());
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? clientIdToUse = _clientId;

      if (clientIdToUse == null) {
        final user = FirebaseAuth
            .instanceFor(app: Firebase.app('client'))
            .currentUser;
        if (user == null) throw Exception('errors.not_logged_in'.tr());
        clientIdToUse = user.uid;
      }

      final selectedCategory = _categories.firstWhere(
            (cat) => cat.id == _selectedCategoryId,
        orElse: () => Category(id: '', name: 'job.unknown_category'.tr()),
      );

      if (selectedCategory.id.isEmpty) {
        throw Exception('errors.category_not_found'.tr());
      }

      // ── Upload media to Cloudinary with progress dialog ────────
      final List<String> mediaUrls  = [];
      final List<String> mediaTypes = List<String>.from(_mediaTypes);

      if (_pickedFiles.isNotEmpty) {
        _updateProgress(1, _pickedFiles.length, 0.0);
        _showUploadDialog();

        for (int i = 0; i < _pickedFiles.length; i++) {
          _updateProgress(i + 1, _pickedFiles.length, 0.0);

          final url = _mediaTypes[i] == 'video'
              ? await _cloudinary.uploadVideo(
            _pickedFiles[i],
            onProgress: (p) =>
                _updateProgress(i + 1, _pickedFiles.length, p),
          )
              : await _cloudinary.uploadImage(
            _pickedFiles[i],
            onProgress: (p) =>
                _updateProgress(i + 1, _pickedFiles.length, p),
          );

          mediaUrls.add(url);
          _updateProgress(i + 1, _pickedFiles.length, 1.0);
        }

        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
      // ──────────────────────────────────────────────────────────

      final newJob = JobModel(
        title:           _titleController.text.trim(),
        description:     _descriptionController.text.trim(),
        category:        selectedCategory.name,
        clientId:        clientIdToUse,
        createdAt:       Timestamp.now(),
        status:          'open',
        mediaUrls:       mediaUrls,
        mediaTypes:      mediaTypes,
        location:        _jobLocation,
        locationAddress: _jobLocationAddress,
        city:            _jobCity,
      );

      final jobService = JobService();
      await jobService.createJob(newJob);

      _showSuccessMessage('job.job_posted'.tr());

      if (mounted) {
        if (widget.onJobPosted != null) {
          widget.onJobPosted!();
        } else {
          Navigator.pop(context);
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
      }
      _showErrorMessage('${"errors.post_job_failed".tr()}: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'job.post_job'.tr(),
            showBackButton: true,
            onBackPressed: () {
              if (widget.onJobPosted != null) {
                widget.onJobPosted!();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'job.fill_details'.tr(),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: isUrdu ? 20 : 18),
                    ),
                    const SizedBox(height: CSizes.spaceBtwSections),

                    // Title
                    CTextField(
                      label:      'job.job_title'.tr(),
                      hintText:   'job.title_hint'.tr(),
                      controller: _titleController,
                      validator: (value) => value == null || value.isEmpty
                          ? 'job.title_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // Description
                    CTextField(
                      label:      'job.job_description'.tr(),
                      hintText:   'job.description_hint'.tr(),
                      controller: _descriptionController,
                      maxLines:   5,
                      validator: (value) => value == null || value.isEmpty
                          ? 'job.description_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // Category
                    _buildCategoryDropdown(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // Location Picker
                    _buildLocationPicker(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // Media Picker
                    _buildMediaPicker(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwSections),

                    // Submit
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : CButton(
                      text:      'job.post_job'.tr(),
                      onPressed: _handlePostJob,
                      width:     double.infinity,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Media picker widget ──────────────────────────────────────────
  Widget _buildMediaPicker(bool isDark, bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(
            'Job Photos / Videos (optional)',
            style: TextStyle(
              fontSize:   isUrdu ? 16 : 14,
              fontWeight: FontWeight.w500,
              color:      isDark ? CColors.light : CColors.dark,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_pickedFiles.length}/$_maxMedia',
            style: TextStyle(
              fontSize: 12,
              color:    _pickedFiles.length >= _maxMedia
                  ? CColors.error
                  : CColors.darkGrey,
            ),
          ),
        ]),
        const SizedBox(height: 8),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Existing media thumbnails
              ..._pickedFiles.asMap().entries.map((entry) {
                final i       = entry.key;
                final isVideo = _mediaTypes[i] == 'video';
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  width:  90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                    border: Border.all(
                        color: CColors.primary.withOpacity(0.4)),
                    color: isDark ? CColors.darkContainer : CColors.lightGrey,
                  ),
                  child: Stack(children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius:
                      BorderRadius.circular(CSizes.borderRadiusMd),
                      child: isVideo
                          ? _VideoThumbnail(file: _pickedFiles[i])
                          : Image.file(
                        _pickedFiles[i],
                        width:  90,
                        height: 90,
                        fit:    BoxFit.cover,
                      ),
                    ),
                    // Video badge
                    if (isVideo)
                      const Positioned(
                        bottom: 4,
                        left:   4,
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 22),
                      ),
                    // Remove button
                    Positioned(
                      top: 4, right: 4,
                      child: GestureDetector(
                        onTap: () => _removeMedia(i),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ]),
                );
              }),

              // Add button
              if (_pickedFiles.length < _maxMedia)
                GestureDetector(
                  onTap: _showAddMediaDialog,
                  child: Container(
                    width:  90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: isDark
                          ? CColors.darkContainer
                          : CColors.lightGrey,
                      borderRadius:
                      BorderRadius.circular(CSizes.borderRadiusMd),
                      border: Border.all(
                        color: isDark
                            ? CColors.darkerGrey
                            : CColors.borderPrimary,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: CColors.primary, size: 28),
                        const SizedBox(height: 4),
                        Text('Add Media',
                            style: TextStyle(
                              fontSize:   11,
                              color:      CColors.primary,
                              fontWeight: FontWeight.w500,
                            )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 6),
        Text(
          'Max $_maxMedia items · Photos & videos · Uploaded on submit',
          style: TextStyle(
            fontSize: 11,
            color:    isDark
                ? CColors.textWhite.withOpacity(0.4)
                : CColors.darkGrey,
          ),
        ),
      ],
    );
  }

  // ── Location picker widget ───────────────────────────────────────
  Widget _buildLocationPicker(bool isDark, bool isUrdu) {
    final hasLocation = _jobLocation != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'job.job_location'.tr(),
          style: TextStyle(
            fontSize:   isUrdu ? 16 : 14,
            fontWeight: FontWeight.w500,
            color:      isDark ? CColors.light : CColors.dark,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _openLocationPicker,
          child: Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(CSizes.md),
            decoration: BoxDecoration(
              color:        isDark ? CColors.darkContainer : CColors.white,
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              border: Border.all(
                color: hasLocation
                    ? CColors.primary
                    : (isDark ? CColors.darkerGrey : CColors.borderPrimary),
                width: hasLocation ? 1.5 : 1.0,
              ),
            ),
            child: Row(children: [
              Container(
                padding:    const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        CColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  hasLocation
                      ? Icons.location_on_rounded
                      : Icons.add_location_alt_outlined,
                  color: CColors.primary,
                  size:  22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLocation
                          ? 'job.location_selected'.tr()
                          : 'job.tap_to_pick_location'.tr(),
                      style: TextStyle(
                        fontSize:   isUrdu ? 15 : 13,
                        fontWeight: hasLocation
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: hasLocation
                            ? CColors.primary
                            : (isDark
                            ? CColors.textWhite.withOpacity(0.5)
                            : CColors.darkGrey),
                      ),
                    ),
                    if (hasLocation && _jobLocationAddress != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _jobLocationAddress!,
                        style: TextStyle(
                          fontSize: isUrdu ? 13 : 11,
                          color:    isDark
                              ? CColors.textWhite.withOpacity(0.6)
                              : CColors.darkerGrey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
            ]),
          ),
        ),
        if (hasLocation)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _jobLocation        = null;
                _jobLocationAddress = null;
                _jobCity            = null;
              }),
              icon:  const Icon(Icons.clear, size: 14),
              label: Text('job.clear_location'.tr(),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: CColors.error,
                padding:         EdgeInsets.zero,
                visualDensity:   VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryDropdown(bool isDark, bool isUrdu) {
    return DropdownButtonFormField<String>(
      value:      _selectedCategoryId,
      hint: Text(
        _isFetchingCategories
            ? 'job.loading_categories'.tr()
            : 'job.select_category'.tr(),
        style: TextStyle(fontSize: isUrdu ? 16 : 14),
      ),
      isExpanded: true,
      decoration: InputDecoration(
        labelText:  'job.category'.tr(),
        labelStyle: TextStyle(
          fontSize: isUrdu ? 16 : 14,
          color:    isDark ? CColors.light : CColors.dark,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        ),
        prefixIcon: Icon(
          Icons.category_outlined,
          color: isDark ? CColors.lightGrey : CColors.darkGrey,
        ),
      ),
      onChanged: _isFetchingCategories
          ? null
          : (v) => setState(() => _selectedCategoryId = v),
      items: _categories.map((cat) {
        return DropdownMenuItem<String>(
          value: cat.id,
          child: Text(cat.name,
              style: TextStyle(fontSize: isUrdu ? 16 : 14)),
        );
      }).toList(),
      validator: (v) =>
      v == null ? 'job.category_required'.tr() : null,
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(message),
      backgroundColor: CColors.error,
      duration:        const Duration(seconds: 4),
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
    ));
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(message),
      backgroundColor: CColors.success,
      duration:        const Duration(seconds: 2),
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
    ));
  }
}

// ── Local video thumbnail (shows a video icon over a dark box) ─────────────
// We use a simple placeholder instead of video_player here to keep the
// picker lightweight. Full playback is in JobMediaGallery.
class _VideoThumbnail extends StatelessWidget {
  final File file;
  const _VideoThumbnail({required this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  90,
      height: 90,
      color:  Colors.black87,
      child: const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Upload Progress Dialog
// ══════════════════════════════════════════════════════════════════
class _UploadProgressDialog extends StatelessWidget {
  final _PostJobScreenState    screen;
  final ValueNotifier<double>  progressNotifier;

  const _UploadProgressDialog({
    required this.screen,
    required this.progressNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // block back button during upload
      child: ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (_, overall, __) {
          final current = screen._uploadCurrent;
          final total   = screen._uploadTotal;
          final isVideo = current > 0 && current <= screen._mediaTypes.length
              ? screen._mediaTypes[current - 1] == 'video'
              : false;

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:  const Color(0xFF5B5BDB).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.cloud_upload_rounded,
                      color: const Color(0xFF5B5BDB),
                      size:  36,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    isVideo ? 'Uploading Video…' : 'Uploading Photo…',
                    style: TextStyle(
                      fontSize:   16,
                      fontWeight: FontWeight.bold,
                      color:      isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // e.g. "File 1 of 3"
                  Text(
                    'File $current of $total',
                    style: TextStyle(
                      fontSize: 13,
                      color:    isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value:           overall,
                      minHeight:       10,
                      backgroundColor: isDark
                          ? Colors.white12
                          : Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF5B5BDB)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Percentage
                  Text(
                    '${(overall * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color:      Color(0xFF5B5BDB),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Please keep the app open',
                    style: TextStyle(
                      fontSize: 11,
                      color:    isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}