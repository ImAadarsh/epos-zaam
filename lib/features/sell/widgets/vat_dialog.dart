import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/org.dart';
import '../../../data/repositories/bootstrap_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../cart_controller.dart';

class VatChoice {
  const VatChoice._({required this.enabled, this.rate, this.taxCodeId, this.name});

  const VatChoice.off() : this._(enabled: false);

  const VatChoice.on({required double rate, String? taxCodeId, String? name})
      : this._(enabled: true, rate: rate, taxCodeId: taxCodeId, name: name);

  final bool enabled;
  final double? rate;
  final String? taxCodeId;
  final String? name;
}

Future<VatChoice?> showVatPicker(
  BuildContext context, {
  required List<TaxCodeInfo> taxCodes,
  double? currentRate,
  String? currentTaxCodeId,
}) {
  return showDialog<VatChoice>(
    context: context,
    builder: (_) => _VatDialog(taxCodes: taxCodes, currentRate: currentRate, currentTaxCodeId: currentTaxCodeId),
  );
}

class _VatDialog extends StatelessWidget {
  const _VatDialog({required this.taxCodes, this.currentRate, this.currentTaxCodeId});
  final List<TaxCodeInfo> taxCodes;
  final double? currentRate;
  final String? currentTaxCodeId;

  bool _selected(TaxCodeInfo code) =>
      code.id.isNotEmpty && code.id == currentTaxCodeId ||
      (currentRate != null && (code.rate - currentRate!).abs() < 0.0005);

  @override
  Widget build(BuildContext context) {
    final codes = [...taxCodes]..sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.rate.compareTo(b.rate);
      });
    final hasTwenty = codes.any((c) => (c.rate - 0.2).abs() < 0.0005);
    return AlertDialog(
      title: const Text('VAT'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use 20% (standard UK) or a VAT code from this organisation (Catalog → Tax Codes). Custom till rates are not allowed.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.money_off_outlined),
                title: const Text('VAT off'),
                subtitle: const Text('This sale charges no VAT'),
                onTap: () => Navigator.pop(context, const VatChoice.off()),
              ),
              if (!hasTwenty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.percent),
                  title: const Text('VAT 20%'),
                  subtitle: const Text('Standard UK rate'),
                  trailing: currentRate != null && (currentRate! - 0.2).abs() < 0.0005 ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, const VatChoice.on(rate: 0.2, name: 'VAT 20%')),
                ),
              if (codes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Organisation tax codes', style: Theme.of(context).textTheme.labelLarge),
                for (final code in codes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(code.name),
                    subtitle: Text('${code.code} · ${code.percentLabel}${code.isDefault ? ' · default' : ''}'),
                    trailing: _selected(code) ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, VatChoice.on(rate: code.rate, taxCodeId: code.id, name: code.name)),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

Future<void> editSaleVat(BuildContext context, WidgetRef ref, {required bool enable}) async {
  if (!enable) {
    ref.read(cartProvider.notifier).setVat(enabled: false);
    return;
  }
  if (!context.mounted) return;
  final cart = ref.read(cartProvider);
  final choice = await showVatPicker(
    context,
    taxCodes: ref.read(bootstrapProvider).taxCodes,
    currentRate: cart.vatRate,
    currentTaxCodeId: cart.vatTaxCodeId,
  );
  if (choice == null || !context.mounted) return;
  _applyVatChoice(ref, choice, toCart: true, toSettings: false);
}

Future<void> editSettingsVat(BuildContext context, WidgetRef ref, {required bool enable}) async {
  final settingsCtrl = ref.read(settingsProvider.notifier);
  if (!enable) {
    await settingsCtrl.update((s) => s.copyWith(vatEnabled: false, clearVatRate: true, vatTaxCodeId: ''));
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) ref.read(cartProvider.notifier).setVat(enabled: false);
    return;
  }
  if (!context.mounted) return;
  final s = ref.read(settingsProvider);
  final choice = await showVatPicker(
    context,
    taxCodes: ref.read(bootstrapProvider).taxCodes,
    currentRate: s.vatRate,
    currentTaxCodeId: s.vatTaxCodeId.isEmpty ? null : s.vatTaxCodeId,
  );
  if (choice == null || !context.mounted) return;
  _applyVatChoice(ref, choice, toCart: ref.read(cartProvider).isEmpty, toSettings: true);
}

void _applyVatChoice(WidgetRef ref, VatChoice choice, {required bool toCart, required bool toSettings}) {
  if (toCart) {
    ref.read(cartProvider.notifier).setVat(enabled: choice.enabled, rate: choice.rate, taxCodeId: choice.taxCodeId);
  }
  if (toSettings) {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          vatEnabled: choice.enabled,
          vatRate: choice.rate,
          clearVatRate: !choice.enabled || choice.rate == null,
          vatTaxCodeId: choice.taxCodeId ?? '',
        ));
  }
}
