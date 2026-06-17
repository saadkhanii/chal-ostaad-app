// lib/shared/widgets/confirmation_dialog.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import 'app_card.dart';

class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmText;
  final String cancelText;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final bool isDestructive;
  final bool isLoading;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    required this.cancelText,
    required this.onConfirm,
    this.onCancel,
    this.isDestructive = true,
    this.isLoading = false,
  });

  static Future<bool?> show(
      BuildContext context, {
        required String title,
        required String content,
        String confirmText = 'Confirm',
        String cancelText = 'Cancel',
        required VoidCallback onConfirm,
        VoidCallback? onCancel,
        bool isDestructive = true,
        bool isLoading = false,
      }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: !isLoading,
      builder: (context) => Dialog(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        ),
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: IntrinsicHeight(
          child: ConfirmationDialog(
            title: title,
            content: content,
            confirmText: confirmText,
            cancelText: cancelText,
            onConfirm: onConfirm,
            onCancel: onCancel,
            isDestructive: isDestructive,
            isLoading: isLoading,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return AppCard(
      showTopBorder: false,
      margin: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
      headerGradient: LinearGradient(
        colors: isDestructive
            ? [CColors.error, CColors.error.withValues(alpha: 0.8)]
            : [CColors.primary, CColors.primary.withValues(alpha: 0.8)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      headerPadding: const EdgeInsets.symmetric(horizontal: CSizes.md, vertical: 3),
      headerTitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDestructive ? Icons.warning_amber_rounded : Icons.info_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
      headerTrailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.white, size: 18),
        onPressed: isLoading ? null : () => Navigator.pop(context, false),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(CSizes.md, CSizes.md, CSizes.md, CSizes.md),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content,
            style: TextStyle(
              color: isDark ? CColors.lightGrey : CColors.textPrimary,
              fontSize: isUrdu ? 15 : 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: CSizes.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: isLoading ? null : () {
                  onCancel?.call();
                  Navigator.pop(context, false);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(70, 35),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: isDestructive ? CColors.error : CColors.primary,
                  side: BorderSide(
                    color: isDestructive ? CColors.error : CColors.primary,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                ),
                child: Text(
                  cancelText,
                  style: TextStyle(
                    fontSize: isUrdu ? 14 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: CSizes.sm),
              ElevatedButton(
                onPressed: isLoading ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDestructive ? CColors.error : CColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(70, 35),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Text(
                  confirmText,
                  style: TextStyle(
                    fontSize: isUrdu ? 14 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}