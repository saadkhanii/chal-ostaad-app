// lib/features/client/client_dashboard_header.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:ui' as ui;  // Add this import

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/Ccontainer.dart';

class ClientDashboardHeader extends ConsumerStatefulWidget {
  final String userName;
  final VoidCallback? onNotificationTap;

  const ClientDashboardHeader({
    super.key,
    required this.userName,
    this.onNotificationTap,
  });

  @override
  ConsumerState<ClientDashboardHeader> createState() => _ClientDashboardHeaderState();
}

class _ClientDashboardHeaderState extends ConsumerState<ClientDashboardHeader> {
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
  }

  void _loadNotificationCount() {
    // Implementation for loading notification count
  }

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
  Widget build(BuildContext context) {
    final displayName = _getDisplayName(widget.userName);

    return CustomShapeContainer(
      height: 200,
      color: CColors.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, 24, CSizes.defaultSpace, 24),
        child: Directionality(
          textDirection: ui.TextDirection.ltr, // Force LTR for entire header
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'dashboard.hello'.tr(),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: CColors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w400,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
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
                  if (widget.onNotificationTap != null)
                    Stack(
                      children: [
                        IconButton(
                          onPressed: widget.onNotificationTap,
                          icon: const Icon(Icons.notifications_outlined, color: CColors.white),
                        ),
                        if (_notificationCount > 0)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: CColors.error,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                '$_notificationCount',
                                style: const TextStyle(color: CColors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      final isUrdu = context.locale.languageCode == 'ur';
                      if (isUrdu) {
                        Scaffold.of(context).openDrawer();  // Opens drawer (right in RTL)
                      } else {
                        Scaffold.of(context).openEndDrawer();  // Opens endDrawer (right in LTR)
                      }
                    },
                    borderRadius: BorderRadius.circular(35),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [CColors.secondary, CColors.secondary.withOpacity(0.9)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person, color: CColors.primary, size: 32),
                        ),
                      ],
                    ),
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