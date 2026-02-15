// lib/shared/widgets/curved_nav_bar.dart
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

    // Scroll listener for hide/show
    useEffect(() {
      double lastScrollOffset = 0;
      const threshold = 10.0;

      void listener() {
        if (!scrollController.hasClients) return;

        final currentOffset = scrollController.offset;
        final isScrollingDown = currentOffset > lastScrollOffset && currentOffset > threshold;
        final isScrollingUp = currentOffset < lastScrollOffset;

        if (isScrollingDown && isVisible) {
          ref.read(navBarVisibilityProvider.notifier).state = false;
        } else if (isScrollingUp && !isVisible) {
          ref.read(navBarVisibilityProvider.notifier).state = true;
        }

        lastScrollOffset = currentOffset;
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: isVisible ? 70 : 0,
      child: isVisible
          ? CurvedNavigationBar(
        items: _buildItems(context, user),
        index: currentIndex,
        onTap: (index) => _handleTap(context, index),
        color: CColors.primary,
        backgroundColor: Colors.transparent,
        buttonBackgroundColor: CColors.primary,
        animationCurve: Curves.easeOutBack, // ✨ POP OUT EFFECT!
        animationDuration: const Duration(milliseconds: 600),
        height: 70,
      )
          : const SizedBox.shrink(),
    );
  }

  List<Widget> _buildItems(BuildContext context, User? user) {
    if (userRole == 'client') {
      return [
        const Icon(Icons.home_outlined, size: 28),
        const Icon(Icons.work_outline, size: 28),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CColors.primary.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.add_circle, size: 48, color: Colors.white),
        ),
        _buildNotificationIcon(context, user),
        const Icon(Icons.person_outline, size: 28),
      ];
    } else {
      return [
        const Icon(Icons.home_outlined, size: 28),
        const Icon(Icons.search, size: 28),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CColors.primary.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.gavel, size: 48, color: Colors.white),
        ),
        _buildNotificationIcon(context, user),
        const Icon(Icons.person_outline, size: 28),
      ];
    }
  }

  Widget _buildNotificationIcon(BuildContext context, User? user) {
    if (user == null) return const Icon(Icons.notifications_outlined, size: 28);

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
            const Icon(Icons.notifications_outlined, size: 28),
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

  void _handleTap(BuildContext context, int index) {
    // Center button (index 2) has special navigation
    if (index == 2) {
      if (userRole == 'client') {
        Navigator.pushNamed(context, AppRoutes.postJob);
      } else {
        Navigator.pushNamed(context, AppRoutes.myBids);
      }
      return;
    }

    // Handle notifications tap (index 3)
    if (index == 3) {
      Navigator.pushNamed(context, AppRoutes.notifications);
      return;
    }

    // Handle profile tap (index 4) - to be implemented
    if (index == 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('common.coming_soon'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Regular navigation for other tabs
    onTap(index);
  }
}