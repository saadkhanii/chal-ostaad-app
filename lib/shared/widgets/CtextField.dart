import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';

class CTextField extends StatelessWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool autoFocus;
  final int? maxLines;
  final int? maxLength;
  final bool enabled;
  final TextInputAction textInputAction;
  final FocusNode? focusNode;
  final String? initialValue;
  final bool isRequired;

  const CTextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autoFocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.focusNode,
    this.initialValue,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with required indicator
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? CColors.white : CColors.textPrimary,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CColors.error,
                ),
              ),
          ],
        ),

        const SizedBox(height: CSizes.xs),

        // Text Field
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          autofocus: autoFocus,
          maxLines: maxLines,
          maxLength: maxLength,
          enabled: enabled,
          textInputAction: textInputAction,
          focusNode: focusNode,
          initialValue: initialValue,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? CColors.white : CColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: CColors.darkGrey,
            ),
            prefixIcon: prefixIcon != null
                ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
              child: prefixIcon,
            )
                : null,
            suffixIcon: suffixIcon != null
                ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
              child: suffixIcon,
            )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              borderSide: BorderSide(color: CColors.borderPrimary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              borderSide: BorderSide(color: CColors.borderPrimary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              borderSide: BorderSide(color: CColors.primary, width: 2.0),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              borderSide: BorderSide(color: CColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              borderSide: BorderSide(color: CColors.error, width: 2.0),
            ),
            filled: true,
            fillColor: isDark ? CColors.darkContainer : CColors.lightContainer,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: CSizes.md,
              vertical: CSizes.sm,
            ),
          ),
        ),
      ],
    );
  }
}