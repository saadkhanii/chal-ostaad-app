// lib/features/client/client_dashboard_header.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/Ccontainer.dart';

class ClientDashboardHeader extends ConsumerWidget {
  final String userName;
  final String photoUrl;
  final VoidCallback? onNotificationTap;

  const ClientDashboardHeader({
    super.key,
    required this.userName,
    this.photoUrl = '',
    this.onNotificationTap,
  });

  String _getDisplayName(String fullName) {
    if (fullName.isEmpty) return 'dashboard.client'.tr();
    final nameParts = fullName.trim().split(' ');
    if (nameParts.isEmpty) return 'dashboard.client'.tr();
    final firstName = nameParts.first;
    if (firstName.toLowerCase() == 'muhammad' && nameParts.length > 1) {
      return nameParts.last;
    }
    return firstName;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = _getDisplayName(userName);
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomShapeContainer(
      height: 200,
      color: CColors.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, 24, CSizes.defaultSpace, 24),
        child: Directionality(
          textDirection: ui.TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Left: greeting text ──────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: CColors.secondary.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '👋 ${'dashboard.welcome_client'.tr()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'dashboard.hello'.tr(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isDark ? CColors.white : CColors.secondary,
                        fontWeight: FontWeight.w400,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: isDark ? CColors.white : CColors.secondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // ── Right: notification bell on top of avatar ────────
              SizedBox(
                width: 70,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // Avatar positioned lower
                    Positioned(
                      bottom: 0,
                      child: InkWell(
                        onTap: () {
                          final isUrdu = context.locale.languageCode == 'ur';
                          if (isUrdu) {
                            Scaffold.of(context).openDrawer();
                          } else {
                            Scaffold.of(context).openEndDrawer();
                          }
                        },
                        borderRadius: BorderRadius.circular(35),
                        child: Builder(builder: (_) {
                          ImageProvider? img;
                          if (photoUrl.isNotEmpty) {
                            try { img = MemoryImage(base64Decode(photoUrl)); } catch (_) {}
                          }
                          return Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? CColors.white : CColors.secondary,
                                width: 2,
                              ),
                              gradient: img == null
                                  ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [CColors.secondary, CColors.secondary.withOpacity(0.9)],
                              )
                                  : null,
                              image: img != null
                                  ? DecorationImage(image: img, fit: BoxFit.cover)
                                  : null,
                            ),
                            child: img == null
                                ? Center(
                              child: Text(
                                userName.trim().isNotEmpty
                                    ? userName.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
                                    : 'C',
                                style: const TextStyle(
                                  color: CColors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                                : null,
                          );
                        }),
                      ),
                    ),

                    // Notification icon — just the icon, no background circle or border
                    if (onNotificationTap != null)
                      Positioned(
                        top: 24, // 12px padding from top as requested
                        left: 22, // Centered above avatar
                        child: GestureDetector(
                          onTap: onNotificationTap,
                          child: StreamBuilder<QuerySnapshot>(
                            stream: user == null ? null : FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .collection('notifications')
                                .where('isRead', isEqualTo: false)
                                .snapshots(),
                            builder: (context, snap) {
                              final unread = snap.hasData ? snap.data!.docs.length : 0;
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.notifications,
                                    size: 24,
                                    color: isDark ? CColors.white : CColors.secondary,
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      right: 2,
                                      top: 2,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: CColors.error,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
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
    );
  }
}