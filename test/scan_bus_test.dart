import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaam_epos/core/scanner/scan_bus.dart';

const _digits = {
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
};

Future<void> _type(WidgetTester tester, String code, {Duration gap = Duration.zero, bool enter = true}) async {
  for (final ch in code.split('')) {
    await tester.sendKeyEvent(_digits[ch]!, character: ch);
    if (gap > Duration.zero) await tester.runAsync(() => Future<void>.delayed(gap));
  }
  if (enter) await tester.sendKeyEvent(LogicalKeyboardKey.enter);
}

void main() {
  late ScanBus bus;
  late List<ScanEvent> scans;

  Future<void> setUpBus(WidgetTester tester, {bool withField = false}) async {
    bus = ScanBus();
    scans = [];
    bus.stream.listen(scans.add);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: withField ? const TextField(autofocus: true) : const SizedBox())));
    await tester.pump();
  }

  tearDown(() => bus.dispose());

  testWidgets('Enter-terminated fast burst (S700 Basic mode) is a scan', (tester) async {
    await setUpBus(tester);
    await _type(tester, '5012345678900');
    await tester.pump();
    expect(scans.map((e) => e.code), ['5012345678900']);
    expect(scans.single.source, ScanSource.keyboardWedge);
  });

  testWidgets('Bluetooth jitter (30 ms between keys) still counts', (tester) async {
    await setUpBus(tester);
    await _type(tester, '96385074', gap: const Duration(milliseconds: 30));
    await tester.pump();
    expect(scans.map((e) => e.code), ['96385074']);
  });

  testWidgets('scanner configured without a suffix flushes after a pause', (tester) async {
    await setUpBus(tester);
    await _type(tester, '5012345678900', enter: false);
    await tester.pump(const Duration(milliseconds: 260));
    expect(scans.map((e) => e.code), ['5012345678900']);
  });

  testWidgets('human-speed typing is not treated as a scan', (tester) async {
    await setUpBus(tester);
    await _type(tester, '123456', gap: const Duration(milliseconds: 90));
    await tester.pump();
    expect(scans, isEmpty);
  });

  testWidgets('with a text field focused the keys are left to the field', (tester) async {
    await setUpBus(tester, withField: true);
    await _type(tester, '5012345678900');
    await tester.pump();
    expect(scans, isEmpty);
  });
}
