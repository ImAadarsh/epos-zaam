import 'package:flutter/widgets.dart';

/// Layout classes used across the app.
///
/// * compact  (< 600dp)  – phones: bottom navigation, cart as a sheet.
/// * medium   (600–1023) – tablets / small windows: rail + side cart.
/// * expanded (>= 1024)  – desktop / web / large tablets landscape.
enum ScreenSize { compact, medium, expanded }

class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1024;
}

ScreenSize screenSizeOf(BuildContext context) => screenSizeForWidth(MediaQuery.sizeOf(context).width);

ScreenSize screenSizeForWidth(double width) {
  if (width >= Breakpoints.expanded) return ScreenSize.expanded;
  if (width >= Breakpoints.medium) return ScreenSize.medium;
  return ScreenSize.compact;
}

extension ScreenSizeX on BuildContext {
  ScreenSize get screenSize => screenSizeOf(this);
  bool get isCompact => screenSize == ScreenSize.compact;
  bool get isExpanded => screenSize == ScreenSize.expanded;
}
