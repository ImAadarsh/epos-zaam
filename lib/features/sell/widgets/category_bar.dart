import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Horizontal category chips that scroll the same way with touch, mouse drag,
/// mouse wheel, trackpad and the arrow buttons.
class CategoryBar extends StatefulWidget {
  const CategoryBar({super.key, required this.categories, required this.selected, required this.onSelected});

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  State<CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<CategoryBar> {
  final _scroll = ScrollController();
  final _keys = <String?, GlobalKey>{};
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void didUpdateWidget(CategoryBar old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateArrows();
      if (old.selected != widget.selected) _reveal(widget.selected);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final back = p.pixels > p.minScrollExtent + 1;
    final forward = p.pixels < p.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _reveal(String? category) {
    final ctx = _keys[category]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() ? event.scrollDelta.dx : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final p = _scroll.position;
      _scroll.jumpTo((p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent));
    });
  }

  Widget _chip(String? category, String label) {
    final key = _keys.putIfAbsent(category, GlobalKey.new);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: widget.selected == category,
        onSelected: (_) => widget.onSelected(category == null || widget.selected == category ? null : category),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onPressed) => SizedBox(
        width: 36,
        child: IconButton(padding: EdgeInsets.zero, iconSize: 22, visualDensity: VisualDensity.compact, icon: Icon(icon), onPressed: onPressed),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (_canBack) _arrow(Icons.chevron_left, () => _page(-1)),
          Expanded(
            child: Listener(
              onPointerSignal: _onWheel,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
                  scrollbars: false,
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: _canBack || _canForward,
                  thickness: 3,
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
                      return false;
                    },
                    child: ListView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(_canBack ? 4 : 12, 4, _canForward ? 4 : 12, 8),
                      children: [
                        _chip(null, 'All'),
                        for (final c in widget.categories) _chip(c, c),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_canForward) _arrow(Icons.chevron_right, () => _page(1)),
        ],
      ),
    );
  }
}
