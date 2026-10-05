import 'dart:math';

import 'package:flutter/material.dart';

/// The game uses a 400-unit ground line. Always retain the full 500-unit height,
/// including 100 units of ground, regardless of screen size or ad height.
class GameCanvas extends StatelessWidget {
  const GameCanvas({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = max(900.0, 500 * constraints.maxWidth / constraints.maxHeight);
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(width: width, height: 500, child: child),
        );
      },
    );
  }
}
