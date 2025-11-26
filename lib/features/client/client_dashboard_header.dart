// lib/features/client/client_dashboard_header.dart
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/Ccontainer.dart';

class ClientDashboardHeader extends StatefulWidget {
  final String userName;
  final VoidCallback? onNotificationTap;

  const ClientDashboardHeader({
    super.key,
    required this.userName,
    this.onNotificationTap,
  });

  @override
  State<ClientDashboardHeader> createState() => _ClientDashboardHeaderState();
}

class _ClientDashboardHeaderState extends State<ClientDashboardHeader> {
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
  }

  void _loadNotificationCount() {
    // Implementation for loading notification count
  }

  @override
  Widget build(BuildContext context) {
    return CustomShapeContainer(
      height: 200,
      color: CColors.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CSizes.defaultSpace, 24, CSizes.defaultSpace, 24),
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
                      '👋 WELCOME CLIENT',
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
                        'Hello,',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: CColors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w400,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.userName,
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
                  onTap: () => Scaffold.of(context).openEndDrawer(),
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
    );
  }
}