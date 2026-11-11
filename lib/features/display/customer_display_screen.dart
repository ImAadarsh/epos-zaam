import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/display/customer_display.dart';
import '../../core/display/youtube_player_stub.dart' if (dart.library.js_interop) '../../core/display/youtube_player_web.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';

/// Standalone app for the customer display window (`?display=1`).
/// Shows a YouTube marketing video — never basket line prices.
class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaam – Customer display',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const CustomerDisplayView(),
    );
  }
}

class CustomerDisplayView extends StatefulWidget {
  const CustomerDisplayView({super.key});

  @override
  State<CustomerDisplayView> createState() => _CustomerDisplayViewState();
}

class _CustomerDisplayViewState extends State<CustomerDisplayView> {
  final _display = CustomerDisplay();
  StreamSubscription<DisplayState>? _sub;
  DisplayState _state = const DisplayState();
  Timer? _reset;
  Timer? _request;

  @override
  void initState() {
    super.initState();
    _state = _bootstrapState();
    _sub = _display.updates.listen(_onUpdate);
    // Ask the till to re-broadcast (BroadcastChannel has no history).
    _request = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (_state.youtubeUrl.trim().isNotEmpty) {
        _request?.cancel();
        return;
      }
      _display.requestSync();
    });
    // One immediate request after the channel is listening.
    Future.microtask(() => _display.requestSync());
  }

  DisplayState _bootstrapState() {
    final ytParam = Uri.base.queryParameters['yt']?.trim() ?? '';
    final stored = readStoredDisplayState();
    if (stored != null) {
      if (ytParam.isNotEmpty && stored.youtubeUrl.trim().isEmpty) {
        return DisplayState(mode: stored.mode, storeName: stored.storeName, youtubeUrl: ytParam, changePence: stored.changePence, message: stored.message);
      }
      return stored;
    }
    if (ytParam.isNotEmpty) return DisplayState(youtubeUrl: ytParam);
    return const DisplayState();
  }

  void _onUpdate(DisplayState s) {
    _reset?.cancel();
    if (!mounted) return;
    setState(() => _state = s);
    if (s.youtubeUrl.trim().isNotEmpty) _request?.cancel();
    if (s.mode == 'done') {
      _reset = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        setState(() => _state = DisplayState(storeName: s.storeName, youtubeUrl: s.youtubeUrl));
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reset?.cancel();
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _state;
    return Scaffold(
      backgroundColor: ZaamColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          YoutubeMarketingPlayer(youtubeUrl: s.youtubeUrl, storeName: s.storeName),
          if (s.mode == 'done')
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.72),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 120, color: ZaamColors.green),
                    const SizedBox(height: 16),
                    Text(s.message ?? 'Thank you!', style: theme.textTheme.displaySmall, textAlign: TextAlign.center),
                    if (s.changePence > 0) ...[
                      const SizedBox(height: 24),
                      Text('Your change', style: theme.textTheme.headlineSmall),
                      Text(
                        formatPence(s.changePence),
                        style: theme.textTheme.displayLarge?.copyWith(color: ZaamColors.gold, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
