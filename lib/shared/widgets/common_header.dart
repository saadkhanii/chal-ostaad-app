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
  final bool showThemeToggle;

  const CommonHeader({
    super.key,
    required this.title,
    this.showBackButton  = true,
    this.onBackPressed,
    this.backgroundColor = CColors.primary,
    this.textColor       = CColors.secondary,
    this.heightFactor     = 0.25,
    this.showThemeToggle  = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final size       = MediaQuery.of(context).size;
    final textTheme  = Theme.of(context).textTheme;

    return CustomShapeContainer(
      height:  size.height * heightFactor,
      color:   backgroundColor,
      padding: const EdgeInsets.only(top: 45), // logo row down 5px
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Logo / nav row ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.sm),
            child: Row(
              textDirection:      TextDirection.ltr,
              mainAxisAlignment:  MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showBackButton)
                  IconButton(
                    icon: Transform(
                      transform: Matrix4.identity(),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.arrow_back_ios,
                        size: 24,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    color:     textColor,
                    onPressed: onBackPressed ?? () {
                      if (Navigator.canPop(context)) Navigator.pop(context);
                    },
                  )
                else
                  const SizedBox(width: 48),

                const Expanded(
                  child: Center(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: AppLogo(fontSize: 28, minWidth: 140, maxWidth: 240),
                    ),
                  ),
                ),

                if (showThemeToggle)
                  IconButton(
                    icon: Icon(
                      themeState.isDark ? Icons.light_mode : Icons.dark_mode,
                      size: 24,
                    ),
                    color:     textColor,
                    onPressed: () =>
                        ref.read(themeProvider.notifier).toggleTheme(),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),

          // ── Title ───────────────────────────────────────────────
          // Spacer pushes title toward bottom but not all the way —
          // we use Expanded + bottom padding to control final position
          const Spacer(),
          SizedBox(
            width: size.width - (CSizes.xl * 2),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(CSizes.xl, 0, CSizes.xl, 50),
              child: Text(
                title,
                textAlign: TextAlign.left,
                maxLines:  2,
                softWrap:  true,
                overflow:  TextOverflow.ellipsis,
                style: textTheme.displayMedium?.copyWith(
                  color:    themeState.isDark ? CColors.white : textColor,
                  fontSize: 22,
                  height:   1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}