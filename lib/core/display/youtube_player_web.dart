import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'youtube_id.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Full-bleed muted looping YouTube embed for the customer-facing monitor.
class YoutubeMarketingPlayer extends StatefulWidget {
  const YoutubeMarketingPlayer({super.key, required this.youtubeUrl, this.storeName = ''});

  final String youtubeUrl;
  final String storeName;

  @override
  State<YoutubeMarketingPlayer> createState() => _YoutubeMarketingPlayerState();
}

class _YoutubeMarketingPlayerState extends State<YoutubeMarketingPlayer> {
  String? _viewType;
  String? _embedUrl;
  String? _registeredFor;

  @override
  void initState() {
    super.initState();
    _sync(widget.youtubeUrl);
  }

  @override
  void didUpdateWidget(covariant YoutubeMarketingPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeUrl != widget.youtubeUrl) {
      _sync(widget.youtubeUrl);
    }
  }

  void _sync(String url) {
    final embed = youtubeEmbedUrl(url);
    if (embed == _registeredFor && _viewType != null) {
      _embedUrl = embed;
      return;
    }
    _embedUrl = embed;
    _registeredFor = embed;
    if (embed == null) {
      _viewType = null;
      return;
    }
    // New viewType per URL — Flutter web factories are one-shot; reusing an empty
    // factory after the till pushes the YT id left a blank iframe.
    final type = 'zaam-yt-${identityHashCode(this)}-${embed.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    _viewType = type;
    ui_web.platformViewRegistry.registerViewFactory(type, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = embed
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen'
        ..allowFullscreen = true;
      iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
      iframe.setAttribute('loading', 'eager');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewType = _viewType;
    if (_embedUrl == null || viewType == null) {
      return ColoredBox(
        color: ZaamColors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ZaamLogo(height: 96, mark: true),
                const SizedBox(height: 24),
                Text(
                  widget.storeName.isEmpty ? 'Welcome' : 'Welcome to ${widget.storeName}',
                  style: theme.textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.youtubeUrl.trim().isEmpty
                      ? 'Set a YouTube link in Settings → Customer display,\nthen reopen Connect Display.'
                      : 'That YouTube link could not be used. Paste a watch URL or 11-character video id.',
                  style: theme.textTheme.titleMedium?.copyWith(color: ZaamColors.gold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return HtmlElementView(viewType: viewType);
  }
}
