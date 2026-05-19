// lib/shared/widgets/app_card.dart
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';

class AppCard extends StatelessWidget {
  final Gradient? headerGradient;
  final Color? headerColor;
  final Widget? headerLeading;
  final Widget? headerTitle;
  final Widget? headerTrailing;
  final Widget? headerActions;
  final Widget body;
  final VoidCallback? onTap;
  final double elevation;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry bodyPadding;
  final EdgeInsetsGeometry headerPadding;
  final BorderRadiusGeometry borderRadius;
  final Color? cardBackgroundColor;
  final Clip clipBehavior;

  const AppCard({
    super.key,
    this.headerGradient,
    this.headerColor,
    this.headerLeading,
    this.headerTitle,
    this.headerTrailing,
    this.headerActions,
    required this.body,
    this.onTap,
    this.elevation = 2,
    this.margin = const EdgeInsets.only(bottom: CSizes.md),
    this.bodyPadding = const EdgeInsets.all(CSizes.md),
    this.headerPadding = const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 12),
    this.borderRadius = const BorderRadius.all(Radius.circular(CSizes.cardRadiusMd)),
    this.cardBackgroundColor,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveCardColor = cardBackgroundColor ??
        (isDark ? CColors.darkContainer : Colors.white);

    // ✅ Changed default from grey to primary gradient
    final headerDecoration = headerGradient != null
        ? BoxDecoration(gradient: headerGradient)
        : headerColor != null
        ? BoxDecoration(color: headerColor)
        : BoxDecoration(gradient: AppCardGradients.urgent()); // primary gradient

    return Card(
      margin: margin,
      elevation: elevation,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      clipBehavior: clipBehavior,
      color: effectiveCardColor,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (headerTitle != null || headerLeading != null || headerTrailing != null || headerActions != null)
              Container(
                padding: headerPadding,
                decoration: headerDecoration,
                child: Row(
                  children: [
                    if (headerLeading != null) ...[
                      headerLeading!,
                      const SizedBox(width: 8),
                    ],
                    if (headerTitle != null) Expanded(child: headerTitle!),
                    if (headerTrailing != null) ...[
                      const SizedBox(width: 8),
                      headerTrailing!,
                    ],
                    if (headerActions != null) headerActions!,
                  ],
                ),
              ),
            Padding(padding: bodyPadding, child: body),
          ],
        ),
      ),
    );
  }
}

class AppCardGradients {
  static LinearGradient urgent() => LinearGradient(
    colors: [CColors.primary, CColors.primary.withValues(alpha: 0.75)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static LinearGradient scheduled() => LinearGradient(
    colors: [CColors.secondary, CColors.secondary.withValues(alpha: 0.75)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static LinearGradient normal() => LinearGradient(
    colors: [Colors.grey.shade700, Colors.grey.shade600],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static LinearGradient fromJob({required bool isUrgent, required bool hasSchedule}) {
    if (isUrgent) return urgent();
    if (hasSchedule) return scheduled();
    return normal();
  }
}