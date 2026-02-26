// lib/features/review/star_rating_bar.dart
//
// Read-only star display. Use anywhere you need to show a rating.

import 'package:flutter/material.dart';

class StarRatingBar extends StatelessWidget {
  final double rating;   // 0.0 – 5.0
  final double size;     // icon size, default 16
  final Color? color;

  const StarRatingBar({
    super.key,
    required this.rating,
    this.size  = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Colors.amber;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1.0;
        IconData icon;
        if (rating >= starValue) {
          icon = Icons.star_rounded;             // full
        } else if (rating >= starValue - 0.5) {
          icon = Icons.star_half_rounded;        // half
        } else {
          icon = Icons.star_outline_rounded;     // empty
        }
        return Icon(icon, size: size, color: starColor);
      }),
    );
  }
}