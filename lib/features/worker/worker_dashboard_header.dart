// lib/features/worker/widgets/worker_dashboard_header.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import 'dart:ui' as ui;

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Ccontainer.dart';

class WorkerDashboardHeader extends ConsumerWidget {
  final String userName;
  final String photoUrl;

  const WorkerDashboardHeader({
    super.key,
    required this.userName,
    this.photoUrl = '',
  });

  String _getDisplayName(String fullName) {
    if (fullName.isEmpty) return 'dashboard.worker'.tr();

    final nameParts = fullName.trim().split(' ');
    if (nameParts.isEmpty) return 'dashboard.worker'.tr();

    final firstName = nameParts.first;

    if (firstName.toLowerCase() == 'muhammad' && nameParts.length > 1) {
      return nameParts.last;
    }

    return firstName;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = _getDisplayName(userName);
    final isUrdu = context.locale.languageCode == 'ur';

    return CustomShapeContainer(
      height: 200,
      color: CColors.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, 24, CSizes.defaultSpace, 24),
        child: Directionality(
          textDirection: ui.TextDirection.ltr, // Force LTR for entire header (like client)
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                        '👋 ${'dashboard.welcome_worker'.tr()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10, // Same as client (10)
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'dashboard.hello'.tr(),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: CColors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w400,
                            fontSize: 18, // Same as client (18)
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 32, // Same as client (32)
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  // Worker header doesn't have notification icon - matches client
                  InkWell(
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
                          border: Border.all(color: CColors.white, width: 2),
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
                                : 'W',
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}