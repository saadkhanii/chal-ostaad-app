import 'package:flutter/material.dart';

class HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);

    // left edge down
    path.lineTo(0, size.height);

    // S-curve to the right edge
    path.cubicTo(
        size.width * 0.55, // control 1 x
        size.height * 1.0, // control 1 y
        size.width * 0.55, // control 2 x
        size.height * 0.35, // control 2 y
        size.width,        // end x
        size.height * 0.42 // end y
    );

    // top-right corner and close
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}
