import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/colors.dart';
import '../constants/sizes.dart';

class CTextTheme {
  CTextTheme._();

  /// Light theme text styles
  static final TextTheme lightTheme = TextTheme(
    displayLarge: GoogleFonts.archivoBlack(
      fontSize: CSizes.fontSizeXXLg,
      fontWeight: FontWeight.bold,
      color: CColors.textPrimary,
    ),
    displayMedium: GoogleFonts.audiowide(
      fontSize: CSizes.fontSizeXLg,
      fontWeight: FontWeight.w600,
      color: CColors.textPrimary,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: CSizes.fontSizeMd,
      fontWeight: FontWeight.normal,
      color: CColors.textPrimary,
    ),
    titleLarge: GoogleFonts.poppins(
      fontSize: CSizes.fontSizeXLg,
      fontWeight: FontWeight.w600,
      color: CColors.textPrimary,
    ),
    titleMedium: GoogleFonts.poppins(
      fontSize: CSizes.fontSizeLg,
      fontWeight: FontWeight.w400,
      color: CColors.textPrimary,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: CSizes.fontSizeMd,
      fontWeight: FontWeight.w500,
      color: CColors.textPrimary,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: CSizes.fontSizeLg,
      fontWeight: FontWeight.w700,
      color: CColors.textPrimary,
    ),
  );

  /// Dark theme text styles
  static final TextTheme darkTheme = lightTheme.apply(
    bodyColor: CColors.white,
    displayColor: CColors.white,
  );
}
