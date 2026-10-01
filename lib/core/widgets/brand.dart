import 'package:flutter/material.dart';

class ZaamLogo extends StatelessWidget {
  const ZaamLogo({super.key, this.height = 40, this.mark = false});

  final double height;

  /// Square mark instead of the horizontal wordmark.
  final bool mark;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = mark ? 'assets/brand/golden.png' : (dark ? 'assets/brand/h-golden.png' : 'assets/brand/h-black.png');
    return Image.asset(asset, height: height, fit: BoxFit.contain, errorBuilder: (_, _, _) => Text('ZAAM', style: TextStyle(fontSize: height * 0.6, fontWeight: FontWeight.w800)));
  }
}
