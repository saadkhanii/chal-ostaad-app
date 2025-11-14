import 'package:flutter/material.dart';
import 'header_clipper.dart';

class CustomShapeContainer extends StatelessWidget {
  final Widget? child;
  final double height; // required
  final double? width; // optional, defaults to screen width
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry alignment;

  const CustomShapeContainer({
    Key? key,
    required this.height, // ✅ must pass height now
    this.width,
    this.child,
    this.color,
    this.padding,
    this.margin,
    this.alignment = Alignment.topCenter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;
    final effectiveWidth = width ?? MediaQuery.of(context).size.width;

    final background = ClipPath(
      clipper: HeaderClipper(),
      child: Container(
        height: height, // ✅ directly use height passed in constructor
        width: effectiveWidth,
        color: effectiveColor,
      ),
    );

    Widget result;
    if (child != null) {
      result = Stack(
        children: [
          background,
          Positioned.fill(
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: Align(alignment: alignment, child: child),
            ),
          ),
        ],
      );
    } else {
      result = background;
    }

    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }

    return result;
  }
}
