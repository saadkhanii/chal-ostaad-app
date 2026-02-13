import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/services/localization_service.dart';

class LanguageSwitch extends ConsumerWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final isUrdu = currentLocale.languageCode == 'ur';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : CColors.softGrey,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // English Button
          _buildLanguageButton(
            context,
            ref,
            language: 'EN',
            isSelected: !isUrdu,
            onTap: () {
              if (isUrdu) {
                ref
                    .read(localeProvider.notifier)
                    .changeLocale(context, const Locale('en'));
              }
            },
          ),
          // Urdu Button
          _buildLanguageButton(
            context,
            ref,
            language: 'اردو',
            isSelected: isUrdu,
            onTap: () {
              if (!isUrdu) {
                ref
                    .read(localeProvider.notifier)
                    .changeLocale(context, const Locale('ur'));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageButton(
      BuildContext context,
      WidgetRef ref, {
        required String language,
        required bool isSelected,
        required VoidCallback onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? CColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          language,
          style: TextStyle(
            color: isSelected
                ? CColors.white
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}