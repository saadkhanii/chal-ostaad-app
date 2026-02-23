// lib/features/profile/worker_profile_screen.dart
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/routes/app_routes.dart';
import '../../shared/widgets/common_header.dart';

class WorkerProfileScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  const WorkerProfileScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends ConsumerState<WorkerProfileScreen> {
  // ── Personal Info ──────────────────────────────────────────────
  String _workerId        = '';
  String _fullName        = '';
  String _email           = '';
  String _phone           = '';
  String _cnic            = '';
  String _dateOfBirth     = '';

  // ── Work Info ──────────────────────────────────────────────────
  String       _categoryName    = '';
  String       _experience      = '';
  List<String> _skills          = [];

  // ── Office Info ────────────────────────────────────────────────
  String _officeName = '';
  String _officeCity = '';

  // ── Verification ───────────────────────────────────────────────
  String _verificationStatus = 'pending'; // pending | verified | rejected

  // ── Stats ──────────────────────────────────────────────────────
  int    _bidsPlaced  = 0;
  int    _jobsWon     = 0;
  String _rating      = 'N/A';

  // ── Photo ──────────────────────────────────────────────────────
  File?  _pickedImage;
  String _photoBase64 = '';
  bool   _isSavingPhoto = false;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkerData();
  }

  // ── Load all data ──────────────────────────────────────────────
  Future<void> _loadWorkerData() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final workerId = prefs.getString('user_uid') ?? '';

      if (workerId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(workerId)
          .get();

      if (!doc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data     = doc.data() ?? {};
      final personal = data['personalInfo']    as Map<String, dynamic>? ?? {};
      final work     = data['workInfo']        as Map<String, dynamic>? ?? {};
      final office   = data['officeInfo']      as Map<String, dynamic>? ?? {};
      final verify   = data['verification']    as Map<String, dynamic>? ?? {};
      final ratings  = data['ratings']         as Map<String, dynamic>? ?? {};

      // Fetch category name if categoryId exists
      String categoryName = '';
      final categoryId = work['categoryId'] as String? ?? '';
      if (categoryId.isNotEmpty) {
        try {
          final catDoc = await FirebaseFirestore.instance
              .collection('workCategories')
              .doc(categoryId)
              .get();
          if (catDoc.exists) {
            final catData = catDoc.data() ?? {};
            categoryName = '${catData['icon'] ?? ''} ${catData['name'] ?? ''}'.trim();
          }
        } catch (_) {}
      }

      // Fetch quick stats
      int bidsPlaced = 0, jobsWon = 0;
      try {
        final bidsSnap = await FirebaseFirestore.instance
            .collection('bids')
            .where('workerId', isEqualTo: workerId)
            .get();
        bidsPlaced = bidsSnap.docs.length;
        jobsWon    = bidsSnap.docs.where((d) => d['status'] == 'accepted').length;
      } catch (_) {}

      final avgRating    = ratings['average'] as num?;
      final totalReviews = ratings['totalReviews'] as int? ?? 0;
      final ratingText   = (avgRating != null && avgRating > 0 && totalReviews > 0)
          ? avgRating.toStringAsFixed(1)
          : 'N/A';

      if (mounted) {
        setState(() {
          _workerId           = workerId;
          _fullName           = personal['name']        ?? personal['fullName'] ?? '';
          _email              = personal['email']        ?? '';
          _phone              = personal['phone']        ?? '';
          _cnic               = personal['cnic']         ?? '';
          _dateOfBirth        = personal['dateOfBirth']  ?? '';
          _photoBase64        = personal['photoBase64']  ?? '';
          _categoryName       = categoryName;
          _experience         = work['experience']       ?? '';
          _skills             = List<String>.from(work['skills'] ?? []);
          _officeName         = office['officeName']     ?? '';
          _officeCity         = office['officeCity']     ?? '';
          _verificationStatus = verify['status']         ?? 'pending';
          _bidsPlaced         = bidsPlaced;
          _jobsWon            = jobsWon;
          _rating             = ratingText;
          _isLoading          = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading worker data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Pick & save profile photo ──────────────────────────────────
  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (_pickedImage != null || _photoBase64.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _removeProfilePhoto();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source:       source,
      imageQuality: 60,
      maxWidth:     400,
    );

    if (picked == null || !mounted) return;

    setState(() => _isSavingPhoto = true);
    try {
      final bytes     = await File(picked.path).readAsBytes();
      final base64Str = base64Encode(bytes);

      await FirebaseFirestore.instance
          .collection('workers')
          .doc(_workerId)
          .update({'personalInfo.photoBase64': base64Str});

      if (mounted) {
        setState(() {
          _pickedImage  = File(picked.path);
          _photoBase64  = base64Str;
          _isSavingPhoto = false;
        });
        _showSnack('Profile photo updated', CColors.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingPhoto = false);
        _showSnack('Failed to save photo: $e', CColors.error);
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    setState(() => _isSavingPhoto = true);
    try {
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(_workerId)
          .update({'personalInfo.photoBase64': ''});
      if (mounted) {
        setState(() {
          _pickedImage   = null;
          _photoBase64   = '';
          _isSavingPhoto = false;
        });
        _showSnack('Profile photo removed', CColors.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingPhoto = false);
        _showSnack('Failed to remove photo: $e', CColors.error);
      }
    }
  }

  // ── Reset password ─────────────────────────────────────────────
  Future<void> _resetPassword() async {
    if (_email.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('A password reset link will be sent to\n$_email'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.primary),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email);
      if (mounted) _showSnack('Reset email sent to $_email', CColors.success);
    } catch (e) {
      if (mounted) _showSnack('Failed to send reset email: $e', CColors.error);
    }
  }

  // ── Logout ─────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('profile.logout'.tr()),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CColors.error),
            child: Text('profile.logout'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.login, (route) => false);
      }
    } catch (e) {
      if (mounted) _showSnack('Logout failed: $e', CColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: color,
      behavior:        SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size   = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          // ── Header with avatar overlapping ─────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              CommonHeader(
                title:          'profile.title'.tr(),
                showBackButton: widget.showAppBar,
                onBackPressed:  widget.showAppBar
                    ? () => Navigator.pop(context)
                    : null,
                showThemeToggle: true,
              ),
              Positioned(
                bottom: -30,
                right:  CSizes.xl,
                child: _isSavingPhoto
                    ? const CircleAvatar(
                  radius: 36,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : _buildAvatar(),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // ── Scrollable content ─────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  CSizes.defaultSpace,
                  CSizes.sm,
                  CSizes.defaultSpace,
                  CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name, email, verification badge
                  _buildNameRow(isDark),
                  const SizedBox(height: CSizes.md),

                  // Quick stats
                  _buildStatsRow(isDark),
                  const SizedBox(height: CSizes.md),

                  // Personal info (read-only)
                  _buildSectionCard(
                    context: context,
                    isDark:  isDark,
                    title:   'profile.personal_info'.tr(),
                    child:   _buildPersonalInfo(isDark),
                  ),
                  const SizedBox(height: CSizes.md),

                  // Work info (read-only)
                  _buildSectionCard(
                    context: context,
                    isDark:  isDark,
                    title:   'profile.work_info'.tr(),
                    child:   _buildWorkInfo(isDark),
                  ),
                  const SizedBox(height: CSizes.md),

                  // Office info
                  if (_officeName.isNotEmpty || _officeCity.isNotEmpty) ...[
                    _buildSectionCard(
                      context: context,
                      isDark:  isDark,
                      title:   'profile.office_info'.tr(),
                      child:   _buildOfficeInfo(isDark),
                    ),
                    const SizedBox(height: CSizes.md),
                  ],

                  // Settings
                  _buildSectionCard(
                    context: context,
                    isDark:  isDark,
                    title:   'profile.settings'.tr(),
                    child:   Column(
                      children: [
                        _buildOptionTile(
                          icon:   Icons.lock_reset_rounded,
                          title:  'Reset Password',
                          onTap:  _resetPassword,
                          isDark: isDark,
                        ),
                        _buildOptionTile(
                          icon:   Icons.notifications_outlined,
                          title:  'nav.notifications'.tr(),
                          onTap:  () => Navigator.pushNamed(
                              context, AppRoutes.notificationSettings),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CSizes.md),

                  // Logout
                  _buildSectionCard(
                    context: context,
                    isDark:  isDark,
                    title:   '',
                    child:   _buildOptionTile(
                      icon:   Icons.logout_rounded,
                      title:  'profile.logout'.tr(),
                      onTap:  _logout,
                      isDark: isDark,
                      color:  CColors.error,
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

  // ── Avatar ─────────────────────────────────────────────────────
  Widget _buildAvatar() {
    final initials = _fullName.isNotEmpty
        ? _fullName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'W';

    ImageProvider? imageProvider;
    if (_pickedImage != null) {
      imageProvider = FileImage(_pickedImage!);
    } else if (_photoBase64.isNotEmpty) {
      try { imageProvider = MemoryImage(base64Decode(_photoBase64)); } catch (_) {}
    }

    return GestureDetector(
      onTap: _pickProfilePhoto,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset:     const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius:          36,
              backgroundColor: CColors.secondary,
              backgroundImage: imageProvider,
              child: imageProvider == null
                  ? Text(initials,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))
                  : null,
            ),
          ),
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              padding:    const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:  CColors.primary,
                shape:  BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Name row with verification badge ──────────────────────────
  Widget _buildNameRow(bool isDark) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    switch (_verificationStatus) {
      case 'verified':
        badgeColor = CColors.success;
        badgeIcon  = Icons.verified;
        badgeText  = 'Verified';
        break;
      case 'rejected':
        badgeColor = CColors.error;
        badgeIcon  = Icons.cancel;
        badgeText  = 'Rejected';
        break;
      default:
        badgeColor = CColors.warning;
        badgeIcon  = Icons.access_time;
        badgeText  = 'Pending';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fullName.isNotEmpty ? _fullName : 'Worker',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.bold,
              fontSize:   20,
            ),
          ),
          const SizedBox(height: 4),
          Text(_email,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: CColors.darkGrey, fontSize: 13)),
          const SizedBox(height: 8),
          // Verification badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: badgeColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 14, color: badgeColor),
                const SizedBox(width: 4),
                Text(badgeText,
                    style: TextStyle(
                      color:      badgeColor,
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick stats row ────────────────────────────────────────────
  Widget _buildStatsRow(bool isDark) {
    return Row(
      children: [
        _buildStatChip(isDark, Icons.gavel,        '$_bidsPlaced', 'Bids'),
        const SizedBox(width: CSizes.sm),
        _buildStatChip(isDark, Icons.emoji_events, '$_jobsWon',    'Won'),
        const SizedBox(width: CSizes.sm),
        _buildStatChip(isDark, Icons.star,         _rating,        'Rating'),
      ],
    );
  }

  Widget _buildStatChip(bool isDark, IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color:        isDark ? CColors.darkContainer : CColors.white,
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: CColors.primary, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label,
                style: TextStyle(fontSize: 11, color: CColors.darkGrey)),
          ],
        ),
      ),
    );
  }

  // ── Personal info ──────────────────────────────────────────────
  Widget _buildPersonalInfo(bool isDark) {
    return Column(
      children: [
        _buildInfoRow(Icons.person_outline,   'Full Name',    _fullName,    isDark),
        _buildInfoRow(Icons.email_outlined,   'Email',        _email,       isDark),
        _buildInfoRow(Icons.phone_outlined,   'Phone',        _phone,       isDark),
        _buildInfoRow(Icons.badge_outlined,   'CNIC',         _cnic,        isDark),
        if (_dateOfBirth.isNotEmpty)
          _buildInfoRow(Icons.cake_outlined,  'Date of Birth', _dateOfBirth, isDark),
        // Read-only notice
        Padding(
          padding: const EdgeInsets.only(top: CSizes.sm),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: CColors.darkGrey),
              const SizedBox(width: 6),
              Text(
                'Contact admin to update your info',
                style: TextStyle(fontSize: 11, color: CColors.darkGrey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Work info ──────────────────────────────────────────────────
  Widget _buildWorkInfo(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_categoryName.isNotEmpty)
          _buildInfoRow(Icons.category_outlined, 'Category',   _categoryName, isDark),
        if (_experience.isNotEmpty)
          _buildInfoRow(Icons.timeline_outlined,  'Experience', _experience,   isDark),
        if (_skills.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CSizes.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.construction_outlined, size: 18, color: CColors.primary),
                const SizedBox(width: CSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Skills',
                          style: TextStyle(fontSize: 11, color: CColors.darkGrey)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _skills.map((skill) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:        CColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border:       Border.all(
                                color: CColors.primary.withOpacity(0.3)),
                          ),
                          child: Text(skill,
                              style: TextStyle(
                                  fontSize: 12, color: CColors.primary)),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Office info ────────────────────────────────────────────────
  Widget _buildOfficeInfo(bool isDark) {
    return Column(
      children: [
        if (_officeName.isNotEmpty)
          _buildInfoRow(Icons.business_outlined,     'Office',   _officeName, isDark),
        if (_officeCity.isNotEmpty)
          _buildInfoRow(Icons.location_city_outlined, 'City',    _officeCity, isDark),
      ],
    );
  }

  // ── Shared info row ────────────────────────────────────────────
  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CSizes.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CColors.primary),
          const SizedBox(width: CSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: CColors.darkGrey)),
                Text(value.isNotEmpty ? value : '—',
                    style: TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? CColors.white : CColors.textPrimary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card ───────────────────────────────────────────────
  Widget _buildSectionCard({
    required BuildContext context,
    required bool isDark,
    required String title,
    required Widget child,
  }) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize:   15,
                )),
            const Divider(height: CSizes.lg),
          ],
          child,
        ],
      ),
    );
  }

  // ── Option tile ────────────────────────────────────────────────
  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required bool isDark,
    Color? color,
  }) {
    final tileColor = color ?? (isDark ? CColors.white : CColors.textPrimary);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading:  Icon(icon, color: tileColor, size: 22),
      title:    Text(title,
          style: TextStyle(
              fontSize: 15, color: tileColor, fontWeight: FontWeight.w500)),
      trailing: Icon(Icons.arrow_forward_ios,
          size: 14, color: tileColor.withOpacity(0.5)),
      onTap: onTap,
    );
  }
}