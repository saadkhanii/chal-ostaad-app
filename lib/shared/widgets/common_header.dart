import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../logo/logo.dart';
import 'Ccontainer.dart';


class CommonHeader extends StatelessWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Color backgroundColor;
  final Color textColor;
  final double heightFactor;

  const CommonHeader({
    Key? key,
    required this.title,
    this.showBackButton = true,
    this.onBackPressed,
    this.backgroundColor = CColors.primary,
    this.textColor = CColors.secondary,
    this.heightFactor = 0.25,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;

    return CustomShapeContainer(
      height: size.height * heightFactor,
      color: backgroundColor,
      padding: const EdgeInsets.only(top: 20),
      child: Stack(
        children: [
          // Centered Content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(fontSize: 32, minWidth: 200, maxWidth: 280),
              const SizedBox(height: 60),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: CSizes.xl),
                child: Text(
                  title,
                  textAlign: TextAlign.left,
                  style: textTheme.displayMedium?.copyWith(
                    color: textColor,
                    fontSize: 26,
                  ),
                ),
              ),
            ],
          ),
          // Back Button
          if (showBackButton)
            Positioned(
              top: 35,
              left: CSizes.md,
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios, color: textColor, size: 30),
                onPressed: onBackPressed ?? () {
                  Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
    );
  }
}