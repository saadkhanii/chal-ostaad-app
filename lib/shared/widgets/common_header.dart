import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../logo/logo.dart';
import '../widgets/Ccontainer.dart';
import '../../core/providers/theme_provider.dart';

class CommonHeader extends ConsumerWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Color backgroundColor;
  final Color textColor;
  final double heightFactor;

  const CommonHeader({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.onBackPressed,
    this.backgroundColor = CColors.primary,
    this.textColor = CColors.secondary,
    this.heightFactor = 0.25,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;

    return CustomShapeContainer(
      height: size.height * heightFactor,
      color: backgroundColor,
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Back Button
                if (showBackButton)
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: textColor, size: 24),
                    onPressed: onBackPressed ?? () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                  )
                else
                  const SizedBox(width: 48),

                // Logo
                const Expanded(
                  child: Center(
                    child: AppLogo(fontSize: 28, minWidth: 140, maxWidth: 240),
                  ),
                ),

                // Theme Switcher
                IconButton(
                  icon: Icon(
                    themeState.isDark ? Icons.light_mode : Icons.dark_mode,
                    color: textColor,
                    size: 24,
                  ),
                  onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(CSizes.xl, CSizes.sm, CSizes.xl, 30),
            child: Text(
              title,
              textAlign: TextAlign.left,
              style: textTheme.displayMedium?.copyWith(
                color: themeState.isDark ? CColors.white : textColor,
                fontSize: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
