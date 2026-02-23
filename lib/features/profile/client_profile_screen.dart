// lib/features/profile/client_profile_screen.dart
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

class ClientProfileScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  const ClientProfileScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState
    extends ConsumerState<ClientProfileScreen> {
  // ── State ──────────────────────────────────────────────────────
  String  _clientId   = '';
  String  _fullName   = '';
  String  _email      = '';
  String  _phone      = '';
  String  _cnic       = '';
  bool    _isLoading  = true;

  // Profile photo
  File?   _pickedImage;
  String  _photoBase64 = ''; // Base64-encoded photo stored in Firestore

  // Edit mode
  bool _isEditing = false;
  final _formKey          = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController();
    _phoneCtrl = TextEditingController();
    _loadClientData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Load data ──────────────────────────────────────────────────
  Future<void> _loadClientData() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final clientId = prefs.getString('user_uid') ?? '';

      if (clientId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .get();

      if (doc.exists) {
        final info = doc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _clientId    = clientId;
            _fullName    = info['fullName']    ?? '';
            _email       = info['email']       ?? '';
            _phone       = info['phone']       ?? '';
            _cnic        = info['cnic']        ?? '';
            _photoBase64 = info['photoBase64'] ?? '';
            _isLoading   = false;
            _nameCtrl.text  = _fullName;
            _phoneCtrl.text = _phone;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading client data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Pick image, convert to Base64, save to Firestore ──────────
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
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
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
      imageQuality: 60,   // lower quality = smaller Base64 string
      maxWidth:     400,  // keep it small for Firestore (< 1MB limit per field)
    );

    if (picked == null || !mounted) return;

    // Show saving indicator
    setState(() => _isSaving = true);

    try {
      final bytes      = await File(picked.path).readAsBytes();
      final base64Str  = base64Encode(bytes);

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(_clientId)
          .update({'personalInfo.photoBase64': base64Str});

      if (mounted) {
        setState(() {
          _pickedImage  = File(picked.path);
          _photoBase64  = base64Str;
          _isSaving     = false;
        });
        _showSnack('Profile photo updated', CColors.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Failed to save photo: $e', CColors.error);
      }
    }
  }

  // ── Remove profile photo ───────────────────────────────────────
  Future<void> _removeProfilePhoto() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(_clientId)
          .update({'personalInfo.photoBase64': ''});
      if (mounted) {
        setState(() {
          _pickedImage  = null;
          _photoBase64  = '';
          _isSaving     = false;
        });
        _showSnack('Profile photo removed', CColors.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Failed to remove photo: $e', CColors.error);
      }
    }
  }

  // ── Save personal info ─────────────────────────────────────────
  Future<void> _savePersonalInfo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(_clientId)
          .update({
        'personalInfo.fullName': _nameCtrl.text.trim(),
        'personalInfo.phone':    _phoneCtrl.text.trim(),
      });

      if (mounted) {
        setState(() {
          _fullName  = _nameCtrl.text.trim();
          _phone     = _phoneCtrl.text.trim();
          _isEditing = false;
          _isSaving  = false;
        });
        _showSnack('Profile updated successfully', CColors.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Failed to update profile: $e', CColors.error);
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
        content: Text(
            'A password reset link will be sent to\n$_email'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary),
            child: const Text('Send',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _email);
      if (mounted) {
        _showSnack('Reset email sent to $_email', CColors.success);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to send reset email: $e', CColors.error);
      }
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
            style: ElevatedButton.styleFrom(
                backgroundColor: CColors.error),
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
          context,
          AppRoutes.login,
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Logout failed: $e', CColors.error);
      }
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
          // ── Header with avatar on the RIGHT at title position ──
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
              // Avatar — positioned at bottom-RIGHT of header,
              // horizontally aligned with where the title text ends
              Positioned(
                bottom: -30,
                right:  CSizes.xl,
                child: _buildAvatar(size),
              ),
            ],
          ),

          // Space for avatar overlap
          const SizedBox(height: 40),

          // ── Content ────────────────────────────────────────────
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
                  // Name + email under avatar area
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 4, bottom: CSizes.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullName.isNotEmpty
                              ? _fullName
                              : 'Client',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge!
                              .copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _email,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium!
                              .copyWith(
                            color:    CColors.darkGrey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Personal info card
                  _buildSectionCard(
                    context:  context,
                    isDark:   isDark,
                    title:    'profile.personal_info'.tr(),
                    child:    _isEditing
                        ? _buildEditForm(isDark)
                        : _buildInfoView(isDark),
                  ),
                  const SizedBox(height: CSizes.md),

                  // Account actions card
                  _buildSectionCard(
                    context: context,
                    isDark:  isDark,
                    title:   'profile.settings'.tr(),
                    child:   Column(
                      children: [
                        _buildOptionTile(
                          icon:    Icons.lock_reset_rounded,
                          title:   'Reset Password',
                          onTap:   _resetPassword,
                          isDark:  isDark,
                        ),
                        _buildOptionTile(
                          icon:    Icons.language_outlined,
                          title:   'profile.language'.tr(),
                          onTap:   () {},
                          isDark:  isDark,
                        ),
                        _buildOptionTile(
                          icon:    Icons.notifications_outlined,
                          title:   'nav.notifications'.tr(),
                          onTap:   () => Navigator.pushNamed(
                              context,
                              AppRoutes.notificationSettings),
                          isDark:  isDark,
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
                      icon:    Icons.logout_rounded,
                      title:   'profile.logout'.tr(),
                      onTap:   _logout,
                      isDark:  isDark,
                      color:   CColors.error,
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

  // ── Avatar (with photo support + edit button) ──────────────────
  Widget _buildAvatar(Size size) {
    final initials = _fullName.isNotEmpty
        ? _fullName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'C';

    // Priority: newly picked file → saved Base64 → initials
    ImageProvider? imageProvider;
    if (_pickedImage != null) {
      imageProvider = FileImage(_pickedImage!);
    } else if (_photoBase64.isNotEmpty) {
      imageProvider = MemoryImage(base64Decode(_photoBase64));
    }

    return GestureDetector(
      onTap: _pickProfilePhoto,
      child: Stack(
        children: [
          // Avatar circle
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
                  ? Text(
                initials,
                style: const TextStyle(
                  fontSize:   22,
                  fontWeight: FontWeight.bold,
                  color:      Colors.white,
                ),
              )
                  : null,
            ),
          ),

          // Small camera badge at bottom-right of avatar
          Positioned(
            bottom: 0,
            right:  0,
            child: Container(
              padding:    const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:  CColors.primary,
                shape:  BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.camera_alt,
                size:  12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Info view (read only) ──────────────────────────────────────
  Widget _buildInfoView(bool isDark) {
    return Column(
      children: [
        _buildInfoRow(Icons.person_outline,  'Full Name', _fullName, isDark),
        _buildInfoRow(Icons.email_outlined,  'Email',     _email,    isDark),
        _buildInfoRow(Icons.phone_outlined,  'Phone',     _phone,    isDark),
        _buildInfoRow(Icons.badge_outlined,  'CNIC',      _cnic,     isDark),
        const SizedBox(height: CSizes.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _isEditing = true),
            icon:  const Icon(Icons.edit_outlined, size: 16),
            label: Text('profile.personal_info'.tr()),
            style: OutlinedButton.styleFrom(
              foregroundColor: CColors.primary,
              side: const BorderSide(color: CColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, bool isDark) {
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
                    style: TextStyle(
                        fontSize: 11,
                        color:    CColors.darkGrey)),
                Text(value.isNotEmpty ? value : '—',
                    style: TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w500,
                        color:      isDark
                            ? CColors.white
                            : CColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Edit form ──────────────────────────────────────────────────
  Widget _buildEditForm(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText:   'Full Name',
              prefixIcon:  const Icon(Icons.person_outline),
              border:      OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
            ),
            validator: (v) =>
            v == null || v.isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: CSizes.md),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText:  'Phone',
              prefixIcon: const Icon(Icons.phone_outlined),
              border:     OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
            ),
            validator: (v) =>
            v == null || v.isEmpty ? 'Phone is required' : null,
          ),
          const SizedBox(height: CSizes.md),
          // Email — read only
          TextFormField(
            initialValue: _email,
            readOnly:     true,
            decoration: InputDecoration(
              labelText:   'Email (cannot be changed)',
              prefixIcon:  const Icon(Icons.email_outlined),
              filled:      true,
              fillColor:   isDark
                  ? CColors.darkerGrey.withOpacity(0.3)
                  : CColors.lightGrey,
              border:      OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
            ),
          ),
          const SizedBox(height: CSizes.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _isEditing = false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CColors.darkGrey,
                    side:            const BorderSide(color: CColors.grey),
                    padding:         const EdgeInsets.symmetric(vertical: 12),
                    shape:           RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            CSizes.borderRadiusMd)),
                  ),
                  child: Text('common.cancel'.tr()),
                ),
              ),
              const SizedBox(width: CSizes.md),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _savePersonalInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.primary,
                    foregroundColor: Colors.white,
                    padding:         const EdgeInsets.symmetric(vertical: 12),
                    shape:           RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            CSizes.borderRadiusMd)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                      width:  18,
                      height: 18,
                      child:  CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : Text('common.save'.tr()),
                ),
              ),
            ],
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
      leading:        Icon(icon, color: tileColor, size: 22),
      title:          Text(title,
          style: TextStyle(
              fontSize:   15,
              color:      tileColor,
              fontWeight: FontWeight.w500)),
      trailing:       Icon(Icons.arrow_forward_ios,
          size: 14, color: tileColor.withOpacity(0.5)),
      onTap:          onTap,
    );
  }
}