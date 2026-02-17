// lib/shared/widgets/curved_nav_bar.dart

import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/colors.dart';
import '../../core/routes/app_routes.dart';

// Provider for nav bar visibility
final navBarVisibilityProvider = StateProvider<bool>((ref) => true);

class CurvedNavBar extends HookConsumerWidget {
  final int currentIndex;
  final Function(int) onTap;
  final String userRole;
  final ScrollController scrollController;

  const CurvedNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.userRole,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final isVisible = ref.watch(navBarVisibilityProvider);

    // Track scroll position and direction
    final lastOffset = useRef(0.0);
    final isScrollingDown = useRef(false);

    // Scroll listener for hide/show
    useEffect(() {
      void listener() {
        if (!scrollController.hasClients) return;

        final currentOffset = scrollController.offset;
        final maxScrollExtent = scrollController.position.maxScrollExtent;

        // Determine scroll direction
        if (currentOffset > lastOffset.value) {
          isScrollingDown.value = true;
        } else if (currentOffset < lastOffset.value) {
          isScrollingDown.value = false;
        }

        // 🔥 FIX: ALWAYS show when at the top (offset <= 10)
        if (currentOffset <= 10) {
          if (!isVisible) {
            ref.read(navBarVisibilityProvider.notifier).state = true;
          }
          lastOffset.value = currentOffset;
          return;
        }

        // Hide when scrolling down and past threshold
        if (isScrollingDown.value && currentOffset > 50 && isVisible) {
          ref.read(navBarVisibilityProvider.notifier).state = false;
        }

        // Show when scrolling up (even slightly) and not at bottom
        else if (!isScrollingDown.value &&
            currentOffset < maxScrollExtent - 50 &&
            !isVisible) {
          ref.read(navBarVisibilityProvider.notifier).state = true;
        }

        lastOffset.value = currentOffset;
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController, isVisible]); // Added isVisible to dependencies

    // Reset visibility when page changes
    useEffect(() {
      // Small delay to ensure controller is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          // Always show nav bar when switching tabs
          ref.read(navBarVisibilityProvider.notifier).state = true;

          // If at top, keep it shown, otherwise it will hide on scroll
          if (scrollController.offset <= 10) {
            ref.read(navBarVisibilityProvider.notifier).state = true;
          }
        }
      });
      return null;
    }, [currentIndex]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: isVisible ? 70 : 0,
      child: isVisible
          ? Directionality(
        textDirection: ui.TextDirection.ltr,
        child: CurvedNavigationBar(
          items: _buildItems(context, user),
          index: currentIndex,
          onTap: (index) => _handleTap(context, index, ref),
          color: CColors.primary,
          backgroundColor: Colors.transparent,
          buttonBackgroundColor: CColors.primary,
          animationCurve: Curves.easeOutCubic,
          animationDuration: const Duration(milliseconds: 300),
          height: 70,
        ),
      )
          : const SizedBox.shrink(),
    );
  }

  List<Widget> _buildItems(BuildContext context, User? user) {
    if (userRole == 'client') {
      return [
        // Index 0: My Posted Jobs (left)
        _buildNavItem(Icons.work_outline, Icons.work, 0),

        // Index 1: Post Job (left-center)
        _buildNavItem(Icons.add_circle_outline, Icons.add_circle, 1),

        // Index 2: HOME (center)
        _buildHomeButton(),

        // Index 3: Notifications (right-center)
        _buildNotificationIcon(context, user, 3),

        // Index 4: Profile (right)
        _buildNavItem(Icons.person_outline, Icons.person, 4),
      ];
    } else {
      return [
        // Index 0: Find Jobs (left)
        _buildNavItem(Icons.search_outlined, Icons.search, 0),

        // Index 1: My Bids (left-center)
        _buildNavItem(Icons.gavel_outlined, Icons.gavel, 1),

        // Index 2: HOME (center)
        _buildHomeButton(),

        // Index 3: Notifications (right-center)
        _buildNotificationIcon(context, user, 3),

        // Index 4: Profile (right)
        _buildNavItem(Icons.person_outline, Icons.person, 4),
      ];
    }
  }

  Widget _buildNavItem(IconData outlineIcon, IconData filledIcon, int index) {
    final isActive = currentIndex == index;
    return Icon(
      isActive ? filledIcon : outlineIcon,
      size: isActive ? 32 : 28,
      color: Colors.white,
    );
  }

  Widget _buildHomeButton() {
    final isActive = currentIndex == 2;
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      child: Icon(
        isActive ? Icons.home : Icons.home_outlined,
        size: 48,
        color: CColors.secondary,
      ),
    );
  }

  Widget _buildNotificationIcon(BuildContext context, User? user, int index) {
    final isActive = currentIndex == index;

    if (user == null) {
      return Icon(
        isActive ? Icons.notifications : Icons.notifications_outlined,
        size: isActive ? 32 : 28,
        color: Colors.white,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              isActive ? Icons.notifications : Icons.notifications_outlined,
              size: isActive ? 32 : 28,
              color: Colors.white,
            ),
            if (unreadCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: CColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleTap(BuildContext context, int index, WidgetRef ref) {
    // Direct mapping - visual index matches actual index
    if (userRole == 'client') {
      switch (index) {
        case 0: // My Posted Jobs
        case 1: // Post Job
        case 2: // Home Dashboard
        case 3: // Notifications
        case 4: // Profile
          onTap(index);
          break;
      }
    } else {
      // Worker - same direct mapping
      switch (index) {
        case 0: // Find Jobs
        case 1: // My Bids
        case 2: // Home Dashboard
        case 3: // Notifications
        case 4: // Profile
          onTap(index);
          break;
      }
    }

    // Ensure nav bar is visible after tapping
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        ref.read(navBarVisibilityProvider.notifier).state = true;
      }
    });
  }
}