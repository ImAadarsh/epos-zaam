import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Non-web fallback: customer marketing video is web-only today.
class YoutubeMarketingPlayer extends StatelessWidget {
  const YoutubeMarketingPlayer({super.key, required this.youtubeUrl, this.storeName = ''});

  final String youtubeUrl;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: ZaamColors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZaamLogo(height: 96, mark: true),
            const SizedBox(height: 24),
            Text(
              storeName.isEmpty ? 'Welcome' : 'Welcome to $storeName',
              style: theme.textTheme.displaySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Marketing video plays on the web customer display.',
              style: theme.textTheme.titleMedium?.copyWith(color: ZaamColors.gold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
