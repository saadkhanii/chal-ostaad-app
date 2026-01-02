import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final void Function()? onTap;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final EdgeInsetsGeometry? contentPadding;
  final bool expands;
  final int? minLines;
  final TextAlign textAlign;
  final bool autocorrect;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final bool enableSuggestions;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final Color? cursorColor;
  final Brightness? keyboardAppearance;
  final String? counterText;
  final bool? showCursor;

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
    this.inputFormatters,
    this.readOnly = false,
    this.onTap,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.contentPadding,
    this.expands = false,
    this.minLines,
    this.textAlign = TextAlign.start,
    this.autocorrect = true,
    this.smartDashesType,
    this.smartQuotesType,
    this.enableSuggestions = true,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorColor,
    this.keyboardAppearance,
    this.counterText,
    this.showCursor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with required indicator
        if (label.isNotEmpty) ...[
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12, // Reduced label size
                  color: isDark ? CColors.white : CColors.textPrimary,
                ),
              ),
              if (isRequired)
                Text(
                  ' *',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: CColors.error,
                    fontSize: 12, // Reduced size for asterisk too
                  ),
                ),
            ],
          ),
          const SizedBox(height: CSizes.xs),
        ],

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
          inputFormatters: inputFormatters,
          readOnly: readOnly,
          onTap: onTap,
          textCapitalization: textCapitalization,
          expands: expands,
          minLines: minLines,
          textAlign: textAlign,
          autocorrect: autocorrect,
          smartDashesType: smartDashesType,
          smartQuotesType: smartQuotesType,
          enableSuggestions: enableSuggestions,
          cursorHeight: cursorHeight,
          cursorRadius: cursorRadius,
          cursorColor: cursorColor ?? (isDark ? CColors.white : CColors.primary),
          keyboardAppearance: keyboardAppearance,
          showCursor: showCursor,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? CColors.white : CColors.textPrimary,
            fontSize: 12, // Reduced input text size
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: CColors.darkGrey,
              fontSize: 12, // Reduced hint text size
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
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
              borderSide: BorderSide(color: CColors.borderPrimary.withOpacity(0.5)),
            ),
            filled: true,
            fillColor: isDark ? CColors.darkContainer : CColors.lightContainer,
            contentPadding: contentPadding ?? const EdgeInsets.symmetric(
              horizontal: CSizes.md,
              vertical: CSizes.xs, // Reduced vertical padding
            ),
            errorText: errorText,
            counterText: counterText,
            // Add floating label behavior
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
        ),
      ],
    );
  }
}
