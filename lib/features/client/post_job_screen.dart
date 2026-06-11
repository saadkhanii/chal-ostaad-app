// lib/features/client/post_job_screen.dart
import 'dart:io';

import 'package:chal_ostaad/core/models/job_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';
import '../maps/location_picker_screen.dart';
import '../../shared/widgets/Cbutton.dart';
import '../../shared/widgets/CtextField.dart';
import '../../shared/widgets/common_header.dart';
import 'my_posted_jobs_screen.dart';

class Category {
  final String id;
  final String name;
  Category({required this.id, required this.name});
}

class PostJobScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  final VoidCallback? onJobPosted;

  /// Pass an existing job to enter edit mode.
  /// The form will be pre-filled and Save will call updateJob() instead of createJob().
  final JobModel? existingJob;

  const PostJobScreen({
    super.key,
    this.showAppBar = true,
    this.onJobPosted,
    this.existingJob,
  });

  @override
  ConsumerState<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends ConsumerState<PostJobScreen> {
  final _formKey               = GlobalKey<FormState>();
  final _titleController       = TextEditingController();
  final _descriptionController = TextEditingController();
  final _minAmountController   = TextEditingController();
  final _maxAmountController   = TextEditingController();
  final _mapService            = MapService();
  final _cloudinary            = CloudinaryService();

  String? _selectedCategoryId;
  bool    _isLoading            = false;
  List<Category> _categories    = [];
  bool    _isFetchingCategories = true;
  String? _clientId;
  String? _clientName;

  // ── Location state (mandatory) ───────────────────────────────────────────────
  GeoPoint? _jobLocation;
  String?   _jobLocationAddress;
  String?   _jobCity;

  // ── Scheduled start time ─────────────────────────────────────────
  DateTime? _scheduledAt;
  bool _isUrgent = false;

  // ── Media state (up to 3 items: images or videos) ────────────────
  final List<File>   _pickedFiles        = [];
  final List<String> _mediaTypes         = [];
  final List<String> _existingMediaUrls  = [];
  final List<String> _existingMediaTypes = [];
  static const int   _maxMedia           = 3;

  // ── Upload progress ─────────────────────────────────
  int    _uploadTotal   = 0;
  int    _uploadCurrent = 0;
  double _fileProgress  = 0.0;
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);

  // ── Edit mode helpers ─────────────────────────────────────────────
  bool get _isEditMode => widget.existingJob != null;

  int get _totalMediaCount =>
      _existingMediaUrls.length + _pickedFiles.length;

  @override
  void initState() {
    super.initState();
    _loadClientInfo();
    _fetchCategories();
    if (_isEditMode) _prefillFromExistingJob();
  }

  /// Pre-fill all fields from the existing job when editing.
  void _prefillFromExistingJob() {
    final job = widget.existingJob!;
    _titleController.text       = job.title;
    _descriptionController.text = job.description;
    _jobLocation        = job.location;
    _jobLocationAddress = job.locationAddress;
    _jobCity            = job.city;
    _scheduledAt        = job.scheduledAt?.toDate();
    _isUrgent           = job.isUrgent;

    if (job.recommendedAmountMin != null) {
      _minAmountController.text =
          job.recommendedAmountMin!.toStringAsFixed(0);
    }
    if (job.recommendedAmountMax != null) {
      _maxAmountController.text =
          job.recommendedAmountMax!.toStringAsFixed(0);
    }

    // Keep existing cloud media so the client can remove individual items.
    _existingMediaUrls.addAll(job.mediaUrls);
    _existingMediaTypes.addAll(
        job.mediaTypes.isNotEmpty
            ? job.mediaTypes
            : List.filled(job.mediaUrls.length, 'image'));
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

          // In edit mode: match the job's category name back to an id.
          if (_isEditMode && _selectedCategoryId == null) {
            final jobCategoryName = widget.existingJob!.category;
            final match = _categories.where(
                    (c) => c.name == jobCategoryName).toList();
            if (match.isNotEmpty) _selectedCategoryId = match.first.id;
          }
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
    if (_totalMediaCount >= _maxMedia) {
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
    if (_totalMediaCount >= _maxMedia) {
      _showErrorMessage('Maximum $_maxMedia media items allowed.');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source:      source,
      maxDuration: const Duration(seconds: 60),
    );
    if (picked == null || !mounted) return;

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

  void _removeNewMedia(int index) {
    setState(() {
      _pickedFiles.removeAt(index);
      _mediaTypes.removeAt(index);
    });
  }

  void _removeExistingMedia(int index) {
    setState(() {
      _existingMediaUrls.removeAt(index);
      _existingMediaTypes.removeAt(index);
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
            title: Text(isVideo
                ? 'Choose Video from Gallery'
                : 'Choose from Gallery'),
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
    if (_totalMediaCount >= _maxMedia) {
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
            leading:   const Icon(Icons.videocam_rounded),
            title:     const Text('Add Video'),
            subtitle:  const Text('Max 60 sec · Max 50 MB'),
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

  // ── Scheduled date/time picker ───────────────────────────────────
  Future<void> _pickScheduledAt() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context:     context,
      initialDate: _scheduledAt ?? now.add(const Duration(hours: 1)),
      firstDate:   now,
      lastDate:    now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context:     context,
      initialTime: _scheduledAt != null
          ? TimeOfDay.fromDateTime(_scheduledAt!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    final chosen = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);

    // Must be in the future
    if (chosen.isBefore(DateTime.now())) {
      _showErrorMessage('Please choose a future date and time.');
      return;
    }

    setState(() => _scheduledAt = chosen);
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
    final overall = total == 0 ? 0.0 : ((current - 1) + fileProgress) / total;
    _progressNotifier.value = overall.clamp(0.0, 1.0);
  }

  // ── Validate budget (optional) ──────────────────────────────────────────────
  /// Returns null if valid (both empty or valid min < max), or an error string.
  String? _validateBudget() {
    final minText = _minAmountController.text.trim();
    final maxText = _maxAmountController.text.trim();

    if (minText.isEmpty && maxText.isEmpty) return null;

    if (minText.isEmpty || maxText.isEmpty) {
      return 'Enter both minimum and maximum amounts, or leave both empty.';
    }

    final min = double.tryParse(minText);
    final max = double.tryParse(maxText);

    if (min == null || min < 0) return 'Minimum amount is invalid.';
    if (max == null || max < 0) return 'Maximum amount is invalid.';
    if (min >= max) return 'Minimum must be less than maximum amount.';

    return null;
  }

  // ── Submit (create or update) ────────────────────────────────────
  Future<void> _handleSubmit() async {
    // 1. Validate form fields (title, category)
    if (!_formKey.currentState!.validate()) return;

    // 2. Location is mandatory
    if (_jobLocation == null) {
      _showErrorMessage('Please select a job location.');
      return;
    }

    // 3. Schedule is mandatory: either urgent or a specific future time
    if (!_isUrgent && _scheduledAt == null) {
      _showErrorMessage('Please select either "ASAP / Urgent" or a specific start time.');
      return;
    }

    // 4. Media is mandatory
    if (_pickedFiles.isEmpty && _existingMediaUrls.isEmpty) {
      _showErrorMessage('Please add at least one photo or video of the job.');
      return;
    }

    // 5. Budget validation (optional but must be valid if filled)
    final budgetError = _validateBudget();
    if (budgetError != null) {
      _showErrorMessage(budgetError);
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

      // ── Upload newly picked media to Cloudinary ────────────────
      final List<String> newUrls  = [];
      final List<String> newTypes = List<String>.from(_mediaTypes);

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

          newUrls.add(url);
          _updateProgress(i + 1, _pickedFiles.length, 1.0);
        }

        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }

      // Merge kept existing + newly uploaded
      final finalUrls  = [..._existingMediaUrls,  ...newUrls];
      final finalTypes = [..._existingMediaTypes, ...newTypes];

      // ── Parse budget ───────────────────────────────────────────
      final minText = _minAmountController.text.trim();
      final maxText = _maxAmountController.text.trim();
      final recMin  = minText.isNotEmpty ? double.tryParse(minText) : null;
      final recMax  = maxText.isNotEmpty ? double.tryParse(maxText) : null;

      // ── Scheduled start ────────────────────────────────────────
      final scheduledTs = _scheduledAt != null
          ? Timestamp.fromDate(_scheduledAt!)
          : null;

      final jobService = JobService();

      if (_isEditMode) {
        // ── Edit: build a partial map and call updateJob() ─────
        final updatedFields = <String, dynamic>{
          'title':       _titleController.text.trim(),
          'description': _descriptionController.text.trim(),   // optional
          'category':    selectedCategory.name,
          'mediaUrls':   finalUrls,
          'mediaTypes':  finalTypes,
          'isUrgent':    _isUrgent,
        };

        // Location – mandatory, cannot be cleared in edit mode (but can be updated)
        if (_jobLocation != null) {
          updatedFields['location']        = _jobLocation;
          updatedFields['locationAddress'] = _jobLocationAddress;
          updatedFields['city']            = _jobCity;
        } else {
          // Should never happen because we validated earlier, but keep safe.
          updatedFields['location']        = FieldValue.delete();
          updatedFields['locationAddress'] = FieldValue.delete();
          updatedFields['city']            = FieldValue.delete();
        }

        // Budget – optional (allow clearing)
        if (recMin != null && recMax != null) {
          updatedFields['recommendedAmountMin'] = recMin;
          updatedFields['recommendedAmountMax'] = recMax;
        } else {
          updatedFields['recommendedAmountMin'] = FieldValue.delete();
          updatedFields['recommendedAmountMax'] = FieldValue.delete();
        }

        // Scheduled – mandatory (either urgent or a timestamp)
        if (_isUrgent) {
          updatedFields['scheduledAt'] = FieldValue.delete();
        } else {
          updatedFields['scheduledAt'] = scheduledTs;
        }

        await jobService.updateJob(
          jobId:         widget.existingJob!.id!,
          updatedFields: updatedFields,
        );

        _showSuccessMessage('Job updated successfully.');
      } else {
        // ── Create new job ────────────────────────────────────
        final newJob = JobModel(
          title:                _titleController.text.trim(),
          description:          _descriptionController.text.trim(),
          category:             selectedCategory.name,
          clientId:             clientIdToUse,
          createdAt:            Timestamp.now(),
          status:               'open',
          mediaUrls:            finalUrls,
          mediaTypes:           finalTypes,
          location:             _jobLocation!, // mandatory, non-null at this point
          locationAddress:      _jobLocationAddress,
          city:                 _jobCity,
          recommendedAmountMin: recMin,
          recommendedAmountMax: recMax,
          scheduledAt:          _isUrgent ? null : scheduledTs,
          isUrgent:             _isUrgent,
        );

        await jobService.createJob(newJob);
        _showSuccessMessage('job.job_posted'.tr());
        return; // _showSuccessMessage handles navigation
      }

      // Edit mode — pop back
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
      }
      _showErrorMessage(
          '${_isEditMode ? "Failed to update job" : "errors.post_job_failed".tr()}: '
              '${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
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
            title: _isEditMode ? 'Edit Job' : 'job.post_job'.tr(),
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
                      _isEditMode
                          ? 'Update the job details below.'
                          : 'job.fill_details'.tr(),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: isUrdu ? 20 : 18),
                    ),
                    const SizedBox(height: CSizes.spaceBtwSections),

                    // ── Title (mandatory) ───────────────────────────────────────
                    CTextField(
                      label:      '${'job.job_title'.tr()}',
                      hintText:   'job.title_hint'.tr(),
                      controller: _titleController,
                      validator: (value) => value == null || value.isEmpty
                          ? 'job.title_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Description (optional) ─────────────────────────────────
                    CTextField(
                      label:      'job.job_description'.tr(),
                      hintText:   'job.description_hint'.tr(),
                      controller: _descriptionController,
                      maxLines:   5,
                      // No validator – optional
                    ),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Category (mandatory) ────────────────────────────────────
                    _buildCategoryDropdown(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Budget range (optional) ────────────────────────────────
                    _buildBudgetSection(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Scheduled start time (mandatory: urgent OR specific time) ─
                    _buildSchedulePicker(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Location (mandatory) ─────────────────────────────
                    _buildLocationPicker(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Media Picker (optional) ────────────────────────────────
                    _buildMediaPicker(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwSections),

                    // ── Submit ──────────────────────────────────────
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : CButton(
                      text:      _isEditMode
                          ? 'Save Changes'
                          : 'job.post_job'.tr(),
                      onPressed: _handleSubmit,
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

  // ── Budget range section (optional) ─────────────────────────────────────────
  Widget _buildBudgetSection(bool isDark, bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Budget Range (PKR) — optional',
          style: TextStyle(
            fontSize:   isUrdu ? 16 : 14,
            fontWeight: FontWeight.w500,
            color:      isDark ? CColors.light : CColors.dark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Workers will see this as a reference when placing bids.',
          style: TextStyle(
            fontSize: 11,
            color:    isDark
                ? CColors.textWhite.withValues(alpha: 0.45)
                : CColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller:  _minAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: false),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText:   'Min',
                  prefixText:  'PKR ',
                  hintText:    '500',
                  labelStyle:  TextStyle(
                      fontSize: isUrdu ? 15 : 13,
                      color:    isDark ? CColors.light : CColors.dark),
                  border:      OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          CSizes.borderRadiusMd)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('–',
                style: TextStyle(
                    fontSize: 18,
                    color: isDark ? CColors.light : CColors.dark)),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller:  _maxAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: false),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText:  'Max',
                  prefixText: 'PKR ',
                  hintText:   '2,000',
                  labelStyle: TextStyle(
                      fontSize: isUrdu ? 15 : 13,
                      color:    isDark ? CColors.light : CColors.dark),
                  border:     OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          CSizes.borderRadiusMd)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Schedule picker widget (mandatory: urgent or specific time) ─────────────────
  Widget _buildSchedulePicker(bool isDark, bool isUrdu) {
    final hasSchedule = _scheduledAt != null;
    final formatted   = hasSchedule
        ? DateFormat('EEE, d MMM yyyy  hh:mm a').format(_scheduledAt!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Preferred Start Time',
                style: TextStyle(
                  fontSize:   isUrdu ? 16 : 14,
                  fontWeight: FontWeight.w500,
                  color:      isDark ? CColors.light : CColors.dark,
                ),
              ),
            ),
            Row(
              children: [
                Checkbox(
                  value: _isUrgent,
                  onChanged: (val) {
                    setState(() {
                      _isUrgent = val ?? false;
                      if (_isUrgent) {
                        _scheduledAt = null;
                      }
                    });
                  },
                  activeColor: CColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'ASAP / Urgent',
                  style: TextStyle(
                    fontSize: isUrdu ? 13 : 12,
                    color: isDark ? CColors.light : CColors.dark,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isUrgent ? null : _pickScheduledAt,
          child: Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(CSizes.md),
            decoration: BoxDecoration(
              color:        isDark ? CColors.darkContainer : CColors.white,
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              border: Border.all(
                color: hasSchedule
                    ? CColors.primary
                    : (isDark ? CColors.darkerGrey : CColors.borderPrimary),
                width: hasSchedule ? 1.5 : 1.0,
              ),
            ),
            child: Row(children: [
              Container(
                padding:    const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        CColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  hasSchedule
                      ? Icons.event_available_rounded
                      : Icons.calendar_month_outlined,
                  color: CColors.primary,
                  size:  22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isUrgent
                      ? 'ASAP / Urgent'
                      : (hasSchedule
                      ? formatted!
                      : 'Tap to pick a start date & time'),
                  style: TextStyle(
                    fontSize:   isUrdu ? 14 : 13,
                    fontWeight: hasSchedule
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: hasSchedule
                        ? CColors.primary
                        : (isDark
                        ? CColors.textWhite.withValues(alpha: 0.5)
                        : CColors.darkGrey),
                  ),
                ),
              ),
              if (!_isUrgent)
                Icon(Icons.chevron_right_rounded,
                    color: isDark ? CColors.darkerGrey : CColors.borderPrimary),
            ]),
          ),
        ),
        if (hasSchedule && !_isUrgent)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _scheduledAt = null),
              icon:  const Icon(Icons.clear, size: 14),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
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

  // ── Media picker widget (optional) ──────────────────────────────────────────
  Widget _buildMediaPicker(bool isDark, bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(
            'Job Photos / Videos',
            style: TextStyle(
              fontSize:   isUrdu ? 16 : 14,
              fontWeight: FontWeight.w500,
              color:      isDark ? CColors.light : CColors.dark,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$_totalMediaCount/$_maxMedia',
            style: TextStyle(
              fontSize: 12,
              color:    _totalMediaCount >= _maxMedia
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
              // ── Existing cloud thumbnails (edit mode) ──────────
              ..._existingMediaUrls.asMap().entries.map((entry) {
                final i       = entry.key;
                final url     = entry.value;
                final isVideo = i < _existingMediaTypes.length &&
                    _existingMediaTypes[i] == 'video';
                return _mediaThumbnailCloud(
                    i, url, isVideo, isDark);
              }),

              // ── Newly picked local files ───────────────────────
              ..._pickedFiles.asMap().entries.map((entry) {
                final i       = entry.key;
                final isVideo = _mediaTypes[i] == 'video';
                return _mediaThumbnailLocal(
                    i, _pickedFiles[i], isVideo, isDark);
              }),

              // ── Add button ─────────────────────────────────────
              if (_totalMediaCount < _maxMedia)
                GestureDetector(
                  onTap: _showAddMediaDialog,
                  child: Container(
                    width:  90,
                    height: 90,
                    decoration: BoxDecoration(
                      color:        isDark
                          ? CColors.darkContainer
                          : CColors.lightGrey,
                      borderRadius: BorderRadius.circular(
                          CSizes.borderRadiusMd),
                      border: Border.all(
                        color: isDark
                            ? CColors.darkerGrey
                            : CColors.borderPrimary,
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
                ? CColors.textWhite.withValues(alpha: 0.4)
                : CColors.darkGrey,
          ),
        ),
      ],
    );
  }

  Widget _mediaThumbnailCloud(
      int index, String url, bool isVideo, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      width:  90,
      height: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        border: Border.all(color: CColors.primary.withValues(alpha: 0.4)),
        color:  isDark ? CColors.darkContainer : CColors.lightGrey,
      ),
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
          child: isVideo
              ? Container(
            width:  90,
            height: 90,
            color:  Colors.black87,
            child:  const Center(
              child: Icon(Icons.videocam_rounded,
                  color: Colors.white, size: 32),
            ),
          )
              : Image.network(
            url,
            width:  90,
            height: 90,
            fit:    BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined, size: 32),
          ),
        ),
        if (isVideo)
          const Positioned(
            bottom: 4, left: 4,
            child: Icon(Icons.play_circle_fill_rounded,
                color: Colors.white, size: 22),
          ),
        // Cloud badge to distinguish existing from new
        const Positioned(
          bottom: 4, right: 4,
          child: Icon(Icons.cloud_done_rounded,
              color: Colors.white70, size: 16),
        ),
        Positioned(
          top: 4, right: 4,
          child: GestureDetector(
            onTap: () => _removeExistingMedia(index),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close,
                  color: Colors.white, size: 14),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _mediaThumbnailLocal(
      int index, File file, bool isVideo, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      width:  90,
      height: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
        border: Border.all(color: CColors.primary.withValues(alpha: 0.4)),
        color:  isDark ? CColors.darkContainer : CColors.lightGrey,
      ),
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
          child: isVideo
              ? _VideoThumbnail(file: file)
              : Image.file(file,
              width: 90, height: 90, fit: BoxFit.cover),
        ),
        if (isVideo)
          const Positioned(
            bottom: 4, left: 4,
            child: Icon(Icons.play_circle_fill_rounded,
                color: Colors.white, size: 22),
          ),
        Positioned(
          top: 4, right: 4,
          child: GestureDetector(
            onTap: () => _removeNewMedia(index),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close,
                  color: Colors.white, size: 14),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Location picker widget (mandatory) ───────────────────────────────────────
  Widget _buildLocationPicker(bool isDark, bool isUrdu) {
    final hasLocation = _jobLocation != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${'job.job_location'.tr()}',
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
                  color:        CColors.primary.withValues(alpha: 0.1),
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
                            ? CColors.textWhite.withValues(alpha: 0.5)
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
                              ? CColors.textWhite.withValues(alpha: 0.6)
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

    // Navigate after snackbar
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (widget.onJobPosted != null) {
        // Embedded in dashboard — let dashboard handle navigation
        widget.onJobPosted!();
      } else {
        // Standalone screen — push to MyPostedJobsScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyPostedJobsScreen()),
        );
      }
    });
  }
} // end of _PostJobScreenState

// ── Local video thumbnail ─────────────────────────────────────────────────────
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
      canPop: false,
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
                borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated icon with gradient background
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CColors.primary.withValues(alpha: 0.15),
                          CColors.secondary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CColors.primary.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.cloud_upload_rounded,
                      color: CColors.primary,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isVideo ? 'Uploading Video…' : 'Uploading Photo…',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'File $current of $total',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Stylish progress indicator
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: overall,
                      minHeight: 8,
                      backgroundColor: isDark
                          ? Colors.white12
                          : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(CColors.primary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(overall * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: CColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Decorative secondary color accent
                  Container(
                    height: 2,
                    width: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [CColors.primary, CColors.secondary],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please keep the app open',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
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