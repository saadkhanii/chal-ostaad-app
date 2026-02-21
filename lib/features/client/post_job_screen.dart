// lib/features/client/post_job_screen.dart
import 'package:chal_ostaad/core/models/job_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/services/job_service.dart';
import '../../core/services/map_service.dart';           // ← NEW
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
  final _formKey              = GlobalKey<FormState>();
  final _titleController      = TextEditingController();
  final _descriptionController= TextEditingController();
  final _mapService           = MapService();           // ← NEW

  String?  _selectedCategoryId;
  bool     _isLoading            = false;
  List<Category> _categories     = [];
  bool     _isFetchingCategories = true;
  String?  _clientId;
  String?  _clientName;

  // ── Location state ──────────────────────────────────────────────
  GeoPoint? _jobLocation;       // picked GeoPoint
  String?   _jobLocationAddress;// reverse-geocoded address string
  String?   _jobCity;           // city extracted from address
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
          _categories            = categoriesData;
          _isFetchingCategories  = false;
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
            // Try to extract city from address string
            if (address != null) {
              final parts = address.split(',');
              if (parts.length >= 2) {
                // city is usually second-to-last or third-to-last part
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

      // Build job — includes location fields if user picked one
      final newJob = JobModel(
        title:           _titleController.text.trim(),
        description:     _descriptionController.text.trim(),
        category:        selectedCategory.name,
        clientId:        clientIdToUse,
        createdAt:       Timestamp.now(),
        status:          'open',
        location:        _jobLocation,        // ← NEW
        locationAddress: _jobLocationAddress, // ← NEW
        city:            _jobCity,            // ← NEW
      );

      final jobService = JobService();
      // createJob() handles Firestore save + proximity-filtered notifications
      // internally (Phase 5) — no need to send notifications here separately
      await jobService.createJob(newJob);

      _showSuccessMessage('job.job_posted'.tr());

      if (mounted) {
        if (widget.onJobPosted != null) {
          widget.onJobPosted!();
        } else {
          Navigator.pop(context);
        }
      }
    } on FirebaseException catch (e) {
      _showErrorMessage('${'errors.firebase_error'.tr()}: ${e.message}');
    } on Exception catch (e) {
      _showErrorMessage('${'errors.post_job_failed'.tr()}: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
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
                      label:    'job.job_title'.tr(),
                      hintText: 'job.title_hint'.tr(),
                      controller: _titleController,
                      validator: (value) => value == null || value.isEmpty
                          ? 'job.title_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // Description
                    CTextField(
                      label:    'job.job_description'.tr(),
                      hintText: 'job.description_hint'.tr(),
                      controller: _descriptionController,
                      maxLines: 5,
                      validator: (value) => value == null || value.isEmpty
                          ? 'job.description_required'.tr()
                          : null,
                    ),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // Category
                    _buildCategoryDropdown(isDark, isUrdu),
                    const SizedBox(height: CSizes.spaceBtwItems),

                    // ── Location Picker ──────────────────────────────
                    _buildLocationPicker(isDark, isUrdu),
                    // ─────────────────────────────────────────────────

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

  // ── Location picker widget ────────────────────────────────────────
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
            child: Row(
              children: [
                Container(
                  padding:    const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:       CColors.primary.withOpacity(0.1),
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
                            ? 'job.location_selected'
                            .tr()
                            : 'job.tap_to_pick_location'
                            .tr(),
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
                          maxLines:  2,
                          overflow:  TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? CColors.darkerGrey : CColors.borderPrimary,
                ),
              ],
            ),
          ),
        ),
        // optional: clear button
        if (hasLocation)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _jobLocation        = null;
                _jobLocationAddress = null;
                _jobCity            = null;
              }),
              icon: const Icon(Icons.clear, size: 14),
              label: Text(
                'job.clear_location'.tr(),
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: CColors.error,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryDropdown(bool isDark, bool isUrdu) {
    return DropdownButtonFormField<String>(
      value: _selectedCategoryId,
      hint: Text(
        _isFetchingCategories
            ? 'job.loading_categories'.tr()
            : 'job.select_category'.tr(),
        style: TextStyle(fontSize: isUrdu ? 16 : 14),
      ),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'job.category'.tr(),
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
          : (newValue) => setState(() => _selectedCategoryId = newValue),
      items: _categories.map((Category category) {
        return DropdownMenuItem<String>(
          value: category.id,
          child: Text(category.name,
              style: TextStyle(fontSize: isUrdu ? 16 : 14)),
        );
      }).toList(),
      validator: (value) =>
      value == null ? 'job.category_required'.tr() : null,
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:          Text(message),
      backgroundColor:  CColors.error,
      duration:         const Duration(seconds: 4),
      behavior:         SnackBarBehavior.floating,
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