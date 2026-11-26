import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/audio/till_click.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';

/// Bank of England polymer note denominations used for cash quick-select.
class CashNote {
  const CashNote({required this.pence, required this.asset, required this.label});

  final int pence;
  final String asset;
  final String label;

  static const values = <CashNote>[
    CashNote(pence: 500, asset: 'assets/notes/note_5.jpg', label: '£5'),
    CashNote(pence: 1000, asset: 'assets/notes/note_10.jpg', label: '£10'),
    CashNote(pence: 2000, asset: 'assets/notes/note_20.jpg', label: '£20'),
    CashNote(pence: 5000, asset: 'assets/notes/note_50.jpg', label: '£50'),
  ];
}

/// Amount to Pay | Paid | Balance | Change — one equal-width horizontal row.
class CashPaymentDetails extends StatelessWidget {
  const CashPaymentDetails({
    super.key,
    required this.amountDuePence,
    required this.paidPence,
    this.compact = false,
  });

  final int amountDuePence;
  final int paidPence;
  final bool compact;

  int get balance => (amountDuePence - paidPence).clamp(0, 1 << 31);
  int get change => (paidPence - amountDuePence).clamp(0, 1 << 31);
  bool get covered => paidPence >= amountDuePence && amountDuePence > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = compact ? 10.0 : 12.0;
    final pad = compact ? 12.0 : 14.0;
    // Use start (not stretch): this strip often sits in a scroll view with
    // unbounded height, where Row stretch collapses cells to zero on web.
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: covered ? ZaamColors.green.withValues(alpha: 0.55) : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: EdgeInsets.all(pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cell(context, 'Amount to Pay', formatPence(amountDuePence))),
          SizedBox(width: gap),
          Expanded(child: _cell(context, 'Paid Amount', paidPence > 0 ? formatPence(paidPence) : '—')),
          SizedBox(width: gap),
          Expanded(child: _cell(context, 'Balance', formatPence(balance))),
          SizedBox(width: gap),
          Expanded(
            child: _cell(
              context,
              'Change',
              formatPence(change),
              emphasize: change > 0,
              valueColor: change > 0 ? ZaamColors.green : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: emphasize ? ZaamColors.green.withValues(alpha: 0.14) : theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: emphasize ? Border.all(color: ZaamColors.green.withValues(alpha: 0.45)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              fontSize: compact ? 13 : 14,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: (compact ? theme.textTheme.headlineSmall : theme.textTheme.headlineMedium)?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontSize: compact ? 26 : 30,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal row of £5 / £10 / £20 / £50 note image buttons. Tap adds that denomination.
class CashNoteBar extends StatelessWidget {
  const CashNoteBar({
    super.key,
    required this.onNote,
    this.enabled = true,
    this.height = 110,
  });

  final ValueChanged<int> onNote;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < CashNote.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _NoteButton(
                note: CashNote.values[i],
                enabled: enabled,
                onTap: () => onNote(CashNote.values[i].pence),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteButton extends StatelessWidget {
  const _NoteButton({required this.note, required this.onTap, required this.enabled});

  final CashNote note;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF3A4554), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  note.asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerLeft,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: const Color(0xFF243041),
                    child: Center(
                      child: Text(
                        note.label,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26),
                      ),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0x77000000), Color(0x00000000)],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        note.label,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                  ),
                ),
                if (!enabled) ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cash tender panel before completing a sale. Returns tendered pence, or null if cancelled.
/// Completing is only allowed when [paid] >= [amountDuePence].
Future<int?> showCashTenderDialog(
  BuildContext context, {
  required int amountDuePence,
  bool playClick = false,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CashTenderDialog(amountDuePence: amountDuePence, playClick: playClick),
  );
}

class _CashTenderDialog extends StatefulWidget {
  const _CashTenderDialog({required this.amountDuePence, required this.playClick});

  final int amountDuePence;
  final bool playClick;

  @override
  State<_CashTenderDialog> createState() => _CashTenderDialogState();
}

class _CashTenderDialogState extends State<_CashTenderDialog> {
  String _digits = '';

  int get _paid => _digits.isEmpty ? 0 : (int.tryParse(_digits) ?? 0);
  int get _change => (_paid - widget.amountDuePence).clamp(0, 1 << 31);
  bool get _canComplete => _paid >= widget.amountDuePence && widget.amountDuePence > 0;

  void _click() {
    if (widget.playClick) TillClick.play();
  }

  void _setDigits(String next) {
    if (next.length > 9) return;
    setState(() => _digits = next);
  }

  void _digit(String d) {
    _click();
    if (d == '.') return;
    final next = '$_digits$d';
    if (next.length > 9) return;
    var cleaned = next.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (cleaned.isEmpty && (d == '0' || d == '00')) cleaned = '0';
    _setDigits(cleaned);
  }

  void _addNote(int pence) {
    _click();
    final next = _paid + pence;
    if (next > 99999999) return;
    _setDigits('$next');
  }

  void _exact() {
    _click();
    _setDigits('${widget.amountDuePence}');
  }

  void _back() {
    _click();
    if (_digits.isEmpty) return;
    _setDigits(_digits.substring(0, _digits.length - 1));
  }

  void _clear() {
    _click();
    _setDigits('');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final screenH = media.size.height;
    // Wide till modal: ~78% of width, capped for ultra-wide displays.
    final dialogW = (screenW * 0.78).clamp(640.0, 1080.0);
    // Leave room for title + pinned actions so nothing overflows the bottom.
    final maxContentHeight = (screenH - media.viewInsets.bottom - 168).clamp(320.0, 820.0);
    final shortViewport = maxContentHeight < 520;
    final noteH = shortViewport ? 88.0 : 118.0;
    final keyH = shortViewport ? 52.0 : 58.0;

    Widget key(String label, {VoidCallback? onTap, Color? color, int flex = 1, double? height}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: color ?? const Color(0xFF243041),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: height ?? keyH,
                child: Center(
                  child: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: shortViewport ? 20 : 22)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget changeBanner() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: ZaamColors.green.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ZaamColors.green.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.payments_outlined, color: ZaamColors.green, size: 26),
            const SizedBox(width: 12),
            const Text('Change due', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17)),
            const Spacer(),
            Text(formatPence(_change), style: const TextStyle(color: ZaamColors.green, fontWeight: FontWeight.w800, fontSize: 26)),
          ],
        ),
      );
    }

    final keypad = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [key('1', onTap: () => _digit('1')), key('2', onTap: () => _digit('2')), key('3', onTap: () => _digit('3')), key('C', onTap: _clear, color: const Color(0xFF3A4A5C))]),
        Row(children: [key('4', onTap: () => _digit('4')), key('5', onTap: () => _digit('5')), key('6', onTap: () => _digit('6')), key('⌫', onTap: _back, color: const Color(0xFF3A4A5C))]),
        Row(children: [key('7', onTap: () => _digit('7')), key('8', onTap: () => _digit('8')), key('9', onTap: () => _digit('9')), key('00', onTap: () => _digit('00'))]),
        Row(children: [key('0', onTap: () => _digit('0'), flex: 3), const Expanded(child: SizedBox())]),
      ],
    );

    // No Spacer/Expanded here — this column sits inside IntrinsicHeight / scroll
    // children where flex widgets collapse to zero height on Flutter web.
    final sidePanel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: shortViewport ? 48 : 56,
          child: OutlinedButton(
            onPressed: _exact,
            style: OutlinedButton.styleFrom(
              foregroundColor: ZaamColors.gold,
              side: BorderSide(color: ZaamColors.gold.withValues(alpha: 0.65), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(
              'Exact ${formatPence(widget.amountDuePence)}',
              style: TextStyle(color: ZaamColors.gold, fontWeight: FontWeight.w800, fontSize: shortViewport ? 16 : 18),
            ),
          ),
        ),
        SizedBox(height: shortViewport ? 16 : 24),
        if (_change > 0) ...[
          changeBanner(),
          SizedBox(height: shortViewport ? 12 : 16),
        ],
        Text(
          _paid > 0 ? 'Tendered ${formatPence(_paid)}' : 'Enter cash received',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );

    return AlertDialog(
      backgroundColor: const Color(0xFF1A222D),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ((screenW - dialogW) / 2).clamp(16.0, 80.0),
        vertical: 16,
      ),
      titlePadding: const EdgeInsets.fromLTRB(28, 22, 28, 6),
      contentPadding: const EdgeInsets.fromLTRB(28, 10, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      title: const Text('Cash payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 26)),
      // Do NOT wrap scroll content in Flexible/Expanded inside a min-height Column —
      // AlertDialog on Flutter web then allocates 0 height and the body paints empty.
      content: SizedBox(
        width: dialogW,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogW, maxHeight: maxContentHeight),
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final ch = event.character;
              if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
                _digit(ch);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.backspace) {
                _back();
                return KeyEventResult.handled;
              }
              if ((event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) && _canComplete) {
                Navigator.pop(context, _paid);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CashPaymentDetails(amountDuePence: widget.amountDuePence, paidPence: _paid),
                  SizedBox(height: shortViewport ? 14 : 18),
                  CashNoteBar(onNote: _addNote, height: noteH),
                  SizedBox(height: shortViewport ? 14 : 18),
                  // Till layout: keypad + Exact / change side-by-side on wide dialogs.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sideBySide = constraints.maxWidth >= 720;
                      if (!sideBySide) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _exact,
                                child: Text(
                                  'Exact ${formatPence(widget.amountDuePence)}',
                                  style: const TextStyle(color: ZaamColors.gold, fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                              ),
                            ),
                            keypad,
                            if (_change > 0) ...[
                              const SizedBox(height: 12),
                              changeBanner(),
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: keypad),
                          const SizedBox(width: 20),
                          Expanded(flex: 4, child: sidePanel),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            minimumSize: const Size(100, 52),
          ),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 17)),
        ),
        FilledButton(
          onPressed: _canComplete
              ? () {
                  // Capture before click sound — never let audio/haptics block completing the sale.
                  final paid = _paid;
                  try {
                    _click();
                  } catch (_) {}
                  Navigator.pop(context, paid);
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1F8A4C),
            disabledBackgroundColor: const Color(0xFF2A3A45),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            minimumSize: const Size(160, 52),
          ),
          child: const Text('Take cash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
