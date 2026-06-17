import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';

class CButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final double borderRadius;
  final bool isLoading;
  final String? loadingText;

  const CButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.width,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.borderRadius = 12,
    this.isLoading = false,
    this.loadingText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: width, // Let it be null to use intrinsic width
      height: height ?? 48, // Default height, but text will determine width
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 2,
          backgroundColor: backgroundColor ??
              (isDark ? CColors.primary : CColors.secondary),
          disabledBackgroundColor: disabledBackgroundColor ??
              (backgroundColor ?? (isDark ? CColors.primary : CColors.secondary))
                  .withValues(alpha: 0.6),
          foregroundColor: foregroundColor ?? CColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 0, // Reduced vertical padding to prevent clipping
          ),
        ),
        child: isLoading
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: foregroundColor ?? CColors.white,
              ),
            ),
            if (loadingText != null) ...[
              const SizedBox(width: 12),
              Text(
                loadingText!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: foregroundColor ?? CColors.white,
                ),
              ),
            ],
          ],
        )
            : Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            height: 1.0, // Adjust line height to prevent cutting
            color: foregroundColor ?? CColors.white,
          ),
        ),
      ),
    );
  }
}