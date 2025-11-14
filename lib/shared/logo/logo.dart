import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';

class AppLogo extends StatelessWidget {
  final double? fontSize;
  final double minWidth;
  final double maxWidth;

  const AppLogo({
    super.key,
    this.fontSize,
    this.minWidth = 150,
    this.maxWidth = 360,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final responsiveFontSize =
            fontSize ?? (constraints.maxWidth * 0.12).clamp(20, 60);

        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: CColors.secondary,
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                  ),
                  child: Text(
                    "CHAL",
                    style: GoogleFonts.archivoBlack(
                      fontSize: responsiveFontSize,
                      color: CColors.primary,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: CSizes.sm),
                Text(
                  "OSTAAD",
                  style: GoogleFonts.archivoBlack(
                    fontSize: responsiveFontSize,
                    color: CColors.white,
                    height: 1.2,
                    shadows: [
                      Shadow(
                        offset: const Offset(3, 3),
                        blurRadius: 4,
                        color: Colors.black.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
