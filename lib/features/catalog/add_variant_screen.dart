import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/catalog.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../shell/app_shell.dart';
import '../shell/status_bar.dart';
import 'catalog_form_shared.dart';

/// Opens Add Vt's. after a manager gate.
Future<bool> openAddVariantScreen(BuildContext context, WidgetRef ref, {String? initialBarcode}) async {
  if (!await ensureCanAddProduct(context, ref) || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AddVariantScreen(initialBarcode: initialBarcode)),
  );
  return true;
}

/// Create a sellable variant under an existing catalogue product.
class AddVariantScreen extends ConsumerStatefulWidget {
  const AddVariantScreen({super.key, this.embedded = false, this.initialBarcode});

  final bool embedded;
  final String? initialBarcode;

  @override
  ConsumerState<AddVariantScreen> createState() => _AddVariantScreenState();
}

class _AddVariantScreenState extends ConsumerState<AddVariantScreen> {
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _qty = TextEditingController(text: '0');
  final _reorderLevel = TextEditingController();
  final _reorderQty = TextEditingController();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _opt1Name = TextEditingController();
  final _opt1Value = TextEditingController();
  final _opt2Name = TextEditingController();
  final _opt2Value = TextEditingController();
  final _opt3Name = TextEditingController();
  final _opt3Value = TextEditingController();
  final _parentSearch = TextEditingController();

  final _skuFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _qtyFocus = FocusNode();

  CatalogItemRef? _parent;
  List<CatalogItemRef> _parentHits = const [];
  bool _searchingParents = false;

  String? _warehouseId;
  late final String? _defaultWarehouseId;
  late final String _defaultWarehouseLabel;
  late final String? _registerName;
  String? _rackId;
  String? _rackLabel;
  String? _binId;
  String? _binLabel;
  String _currency = 'GBP';
  String _status = 'active';
  bool _autoGenerateBarcode = true;
  String _weightUnit = 'kg';
  String _dimensionUnit = 'cm';

  String? _formError;
  String? _skuError;
  String? _priceError;
  String? _qtyError;
  String? _parentError;
  bool _saving = false;
  bool _defaultsReady = false;

  static const _currencies = ['GBP', 'EUR', 'USD', 'AED', 'AUD', 'CAD', 'CHF', 'INR', 'NZD', 'SAR', 'ZAR'];

  @override
  void initState() {
    super.initState();
    final code = widget.initialBarcode?.trim();
    if (code != null && code.isNotEmpty) _barcode.text = code;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapDefaults());
  }

  Future<void> _bootstrapDefaults() async {
    final boot = ref.read(bootstrapProvider);
    final register = ref.read(currentRegisterProvider);
    _registerName = register?.name;

    final registerWh = register?.warehouseId;
    final registerWhName = register?.warehouseName;
    if (registerWh != null && registerWh.isNotEmpty) {
      _defaultWarehouseId = registerWh;
      _defaultWarehouseLabel = registerWhName?.trim().isNotEmpty == true ? registerWhName!.trim() : 'Register warehouse';
    } else if (boot.warehouses.isNotEmpty) {
      final w = boot.warehouses.first;
      _defaultWarehouseId = w.id;
      _defaultWarehouseLabel = w.name;
    } else {
      _defaultWarehouseId = null;
      _defaultWarehouseLabel = 'No warehouse set';
    }
    _warehouseId = _defaultWarehouseId;
    _currency = 'GBP';
    _autoGenerateBarcode = _barcode.text.trim().isEmpty;

    await _searchParents('');
    if (!mounted) return;
    setState(() => _defaultsReady = true);
    _skuFocus.requestFocus();
  }

  Future<void> _searchParents(String q) async {
    setState(() => _searchingParents = true);
    try {
      final hits = await ref.read(catalogProvider.notifier).searchCatalogItems(q: q.trim().isEmpty ? null : q.trim());
      if (!mounted) return;
      setState(() {
        _parentHits = hits;
        _searchingParents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _parentHits = const [];
        _searchingParents = false;
      });
    }
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.dispose();
    _qty.dispose();
    _reorderLevel.dispose();
    _reorderQty.dispose();
    _weight.dispose();
    _length.dispose();
    _width.dispose();
    _height.dispose();
    _opt1Name.dispose();
    _opt1Value.dispose();
    _opt2Name.dispose();
    _opt2Value.dispose();
    _opt3Name.dispose();
    _opt3Value.dispose();
    _parentSearch.dispose();
    _skuFocus.dispose();
    _priceFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  bool get _warehouseIsDefault => _warehouseId == _defaultWarehouseId;

  String get _warehouseLabel {
    final boot = ref.read(bootstrapProvider);
    final hit = boot.warehouses.where((w) => w.id == _warehouseId).firstOrNull;
    if (hit != null) return hit.name;
    if (_warehouseId == _defaultWarehouseId) return _defaultWarehouseLabel;
    return 'Stock location';
  }

  String get _statusLabel => switch (_status) {
        'inactive' => 'Hidden from Sell',
        'discontinued' => 'Discontinued',
        _ => 'On sale',
      };

  Future<void> _pickWarehouse() async {
    final boot = ref.read(bootstrapProvider);
    if (boot.warehouses.isEmpty) {
      showMessage(context, 'No stock locations are set up for this organisation.', error: true);
      return;
    }
    final choice = await pickOption<String>(
      context,
      title: 'Stock location',
      options: [
        for (final w in boot.warehouses) (w.id, w.name + (w.id == _defaultWarehouseId ? ' · Default' : '')),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() {
      _warehouseId = choice;
      // Rack/bin masters are per warehouse — clear when stock location changes.
      _rackId = null;
      _rackLabel = null;
      _binId = null;
      _binLabel = null;
    });
  }

  Future<void> _pickRack() async {
    final warehouseId = _warehouseId;
    if (warehouseId == null || warehouseId.isEmpty) {
      showMessage(context, 'Pick a stock location first.', error: true);
      return;
    }
    List<StockLocationOption> racks;
    try {
      racks = await ref.read(catalogProvider.notifier).listRacks(warehouseId: warehouseId);
    } catch (e) {
      if (!mounted) return;
      showMessage(context, 'Could not load racks: ${errorMessage(e)}', error: true);
      return;
    }
    if (!mounted) return;
    if (racks.isEmpty) {
      showMessage(
        context,
        'No racks set up for $_warehouseLabel yet. Add them in ERP → Inventory → Racks.',
      );
      return;
    }
    final choice = await pickSearchableOption<String>(
      context,
      title: 'Rack · $_warehouseLabel',
      searchHint: 'Search rack code / name…',
      emptyLabel: 'No rack',
      emptyValue: '',
      selectedValueKey: _rackId,
      valueKey: (v) => v,
      options: [for (final r in racks) (r.id, r.displayLabel)],
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice.isEmpty) {
        _rackId = null;
        _rackLabel = null;
      } else {
        final hit = racks.where((r) => r.id == choice).firstOrNull;
        _rackId = choice;
        _rackLabel = hit?.displayLabel ?? choice;
      }
      // Match ERP: changing rack clears bin (bins are rack-scoped after migration 024).
      _binId = null;
      _binLabel = null;
    });
  }

  Future<void> _pickBin() async {
    final warehouseId = _warehouseId;
    if (warehouseId == null || warehouseId.isEmpty) {
      showMessage(context, 'Pick a stock location first.', error: true);
      return;
    }
    List<StockLocationOption> bins;
    try {
      bins = await ref.read(catalogProvider.notifier).listBins(
            warehouseId: warehouseId,
            rackId: _rackId,
          );
    } catch (e) {
      if (!mounted) return;
      showMessage(context, 'Could not load bins: ${errorMessage(e)}', error: true);
      return;
    }
    if (!mounted) return;
    if (bins.isEmpty) {
      showMessage(
        context,
        _rackId == null
            ? 'No bins set up for $_warehouseLabel yet. Add them in ERP → Inventory → Bins.'
            : 'No bins on rack ${_rackLabel ?? _rackId}. Pick another rack or clear rack filter.',
      );
      return;
    }
    final choice = await pickSearchableOption<String>(
      context,
      title: _rackLabel != null ? 'Bin · $_rackLabel' : 'Bin · $_warehouseLabel',
      searchHint: 'Search bin code / name…',
      emptyLabel: 'No bin',
      emptyValue: '',
      selectedValueKey: _binId,
      valueKey: (v) => v,
      options: [for (final b in bins) (b.id, b.displayLabel)],
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice.isEmpty) {
        _binId = null;
        _binLabel = null;
      } else {
        final hit = bins.where((b) => b.id == choice).firstOrNull;
        _binId = choice;
        _binLabel = hit?.displayLabel ?? choice;
        // Selecting a bin under "all racks" adopts its rack so create sends matching rackId.
        if (_rackId == null && hit?.rackId != null && hit!.rackId!.isNotEmpty) {
          _rackId = hit.rackId;
          _rackLabel = (hit.rackCode != null && hit.rackCode!.isNotEmpty) ? hit.rackCode : hit.rackId;
        }
      }
    });
  }

  Future<void> _pickStatus() async {
    final choice = await pickOption<String>(
      context,
      title: 'Sell status',
      options: const [
        ('active', 'On sale · Default'),
        ('inactive', 'Hidden from Sell'),
        ('discontinued', 'Discontinued'),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() => _status = choice);
  }

  Future<void> _scanBarcode() async {
    final code = await scanWithCamera(context, title: 'Scan variant barcode');
    if (code == null || !mounted) return;
    setState(() {
      _barcode.text = code.trim();
      if (_barcode.text.isNotEmpty) _autoGenerateBarcode = false;
    });
  }

  Future<void> _pickCurrency() async {
    final choice = await pickOption<String>(
      context,
      title: 'Cost / sell currency',
      options: [for (final c in _currencies) (c, c == 'GBP' ? 'GBP · Default' : c)],
    );
    if (choice == null || !mounted) return;
    setState(() => _currency = choice);
  }

  Future<void> _pickWeightUnit() async {
    final choice = await pickOption<String>(
      context,
      title: 'Weight unit',
      options: const [('kg', 'kg'), ('g', 'g'), ('lb', 'lb'), ('oz', 'oz')],
    );
    if (choice == null || !mounted) return;
    setState(() => _weightUnit = choice);
  }

  Future<void> _pickDimensionUnit() async {
    final choice = await pickOption<String>(
      context,
      title: 'Dimension unit',
      options: const [('cm', 'cm'), ('m', 'm'), ('in', 'in'), ('ft', 'ft')],
    );
    if (choice == null || !mounted) return;
    setState(() => _dimensionUnit = choice);
  }

  Future<void> _pickParent() async {
    await _searchParents(_parentSearch.text);
    if (!mounted) return;
    final choice = await showModalBottomSheet<CatalogItemRef>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = _parentSearch.text;
        var hits = List<CatalogItemRef>.from(_parentHits);
        var loading = false;
        Timer? debounce;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Parent product', style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: query)
                        ..selection = TextSelection.collapsed(offset: query.length),
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search name, SKU, brand…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) {
                        query = v;
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 280), () async {
                          setModal(() => loading = true);
                          try {
                            final next = await ref.read(catalogProvider.notifier).searchCatalogItems(
                                  q: v.trim().isEmpty ? null : v.trim(),
                                );
                            setModal(() {
                              hits = next;
                              loading = false;
                            });
                          } catch (_) {
                            setModal(() => loading = false);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    if (loading) const LinearProgressIndicator(),
                    Expanded(
                      child: hits.isEmpty
                          ? Center(
                              child: Text(
                                'No products found. Create one under Add Prod. first.',
                                textAlign: TextAlign.center,
                                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: hits.length,
                              itemBuilder: (_, i) {
                                final item = hits[i];
                                return ListTile(
                                  title: Text(item.name),
                                  subtitle: Text(
                                    [
                                      if (item.sku.isNotEmpty) item.sku,
                                      if (item.brand != null && item.brand!.isNotEmpty) item.brand,
                                      if (item.category != null && item.category!.isNotEmpty) item.category,
                                      '${item.variantCount} variant${item.variantCount == 1 ? '' : 's'}',
                                    ].join(' · '),
                                  ),
                                  onTap: () => Navigator.pop(ctx, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (choice == null || !mounted) return;
    setState(() {
      _parent = choice;
      _parentError = null;
      _parentSearch.text = choice.label;
      if (_sku.text.trim().isEmpty && choice.sku.isNotEmpty) {
        _sku.text = '${choice.sku}-V${choice.variantCount + 1}';
      }
    });
  }

  bool _validate() {
    String? parentErr;
    String? skuErr;
    String? priceErr;
    String? qtyErr;
    if (_parent == null) parentErr = 'Pick a parent product';
    if (_sku.text.trim().isEmpty) skuErr = 'Enter a variant SKU';
    final price = parsePence(_price.text);
    if (price == null) {
      priceErr = 'Enter a sell price, e.g. 12.50';
    } else if (price < 0) {
      priceErr = 'Sell price cannot be negative';
    }
    if (_cost.text.trim().isNotEmpty) {
      final cost = parsePence(_cost.text);
      if (cost == null || cost < 0) {
        setState(() {
          _parentError = parentErr;
          _skuError = skuErr;
          _priceError = 'Check cost price (e.g. 4.50)';
          _qtyError = null;
          _formError = null;
        });
        return false;
      }
    }
    final qty = int.tryParse(_qty.text.trim());
    if (qty == null) {
      qtyErr = 'Enter a whole number for stock';
    } else if (qty < 0) {
      qtyErr = 'Stock cannot be negative';
    }
    if (_warehouseId == null || _warehouseId!.isEmpty) {
      setState(() {
        _parentError = parentErr;
        _skuError = skuErr;
        _priceError = priceErr;
        _qtyError = qtyErr;
        _formError = 'This register has no stock location. Set one under Options → Change Register.';
      });
      return false;
    }
    setState(() {
      _parentError = parentErr;
      _skuError = skuErr;
      _priceError = priceErr;
      _qtyError = qtyErr;
      _formError = null;
    });
    if (parentErr != null) return false;
    if (skuErr != null) {
      _skuFocus.requestFocus();
      return false;
    }
    if (priceErr != null) {
      _priceFocus.requestFocus();
      return false;
    }
    if (qtyErr != null) {
      _qtyFocus.requestFocus();
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_validate()) return;
    if (!ref.read(onlineProvider)) {
      setState(() => _formError = 'You are offline. Reconnect, then save again — your entries are still here.');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      final costPence = _cost.text.trim().isEmpty ? null : parsePence(_cost.text);
      final reorderLevel = _reorderLevel.text.trim().isEmpty ? null : num.tryParse(_reorderLevel.text.trim());
      final reorderQty = _reorderQty.text.trim().isEmpty ? null : num.tryParse(_reorderQty.text.trim());
      final weightVal = _weight.text.trim().isEmpty ? null : num.tryParse(_weight.text.trim());
      final lengthVal = _length.text.trim().isEmpty ? null : num.tryParse(_length.text.trim());
      final widthVal = _width.text.trim().isEmpty ? null : num.tryParse(_width.text.trim());
      final heightVal = _height.text.trim().isEmpty ? null : num.tryParse(_height.text.trim());
      final product = await ref.read(catalogProvider.notifier).createVariant(
            catalogItemId: _parent!.id,
            variantSku: _sku.text.trim(),
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            option1Name: _opt1Name.text.trim().isEmpty ? null : _opt1Name.text.trim(),
            option1Value: _opt1Value.text.trim().isEmpty ? null : _opt1Value.text.trim(),
            option2Name: _opt2Name.text.trim().isEmpty ? null : _opt2Name.text.trim(),
            option2Value: _opt2Value.text.trim().isEmpty ? null : _opt2Value.text.trim(),
            option3Name: _opt3Name.text.trim().isEmpty ? null : _opt3Name.text.trim(),
            option3Value: _opt3Value.text.trim().isEmpty ? null : _opt3Value.text.trim(),
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            autoGenerateBarcode: _autoGenerateBarcode,
            costPricePence: costPence,
            sellPricePence: parsePence(_price.text)!,
            currency: _currency,
            status: _status,
            warehouseId: _warehouseId,
            quantity: int.parse(_qty.text.trim()),
            reorderLevel: reorderLevel,
            reorderQuantity: reorderQty ?? reorderLevel,
            binId: _binId,
            rackId: _rackId,
            weightValue: weightVal,
            weightUnit: weightVal == null ? null : _weightUnit,
            lengthValue: lengthVal,
            widthValue: widthVal,
            heightValue: heightVal,
            dimensionUnit: (lengthVal == null && widthVal == null && heightVal == null) ? null : _dimensionUnit,
          );
      if (!mounted) return;
      showMessage(context, '${product.displayName} added to Sell.');
      final next = await showDialog<_AfterSave>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Variant saved'),
          content: Text(
            '${product.displayName} is on Sell at ${formatPence(product.effectivePricePence)}'
            '${product.stock != null ? ' · ${product.stock} in stock' : ''}.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, _AfterSave.addAnother), child: const Text('Add another')),
            FilledButton(onPressed: () => Navigator.pop(ctx, _AfterSave.backToSell), child: const Text('Back to Sell')),
          ],
        ),
      );
      if (!mounted) return;
      if (next == _AfterSave.addAnother) {
        _resetForAnother();
      } else {
        if (!widget.embedded) Navigator.of(context).pop();
        ref.read(shellTabProvider.notifier).go(0);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = errorMessage(e);
      setState(() {
        _saving = false;
        if (msg.toLowerCase().contains('barcode') || msg.toLowerCase().contains('sku')) {
          _formError = msg;
        } else if (e is ApiException && e.statusCode == 403) {
          _formError = 'Only a till manager can add variants. Ask a manager to enter their PIN, then try again.';
        } else {
          _formError = 'Could not save: $msg. Your entries are still here — fix and try again.';
        }
      });
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  void _resetForAnother() {
    final keepParent = _parent;
    _sku.clear();
    _name.clear();
    _barcode.clear();
    _price.clear();
    _cost.clear();
    _qty.text = '0';
    _reorderLevel.clear();
    _reorderQty.clear();
    _rackId = null;
    _rackLabel = null;
    _binId = null;
    _binLabel = null;
    _weight.clear();
    _length.clear();
    _width.clear();
    _height.clear();
    _opt1Name.clear();
    _opt1Value.clear();
    _opt2Name.clear();
    _opt2Value.clear();
    _opt3Name.clear();
    _opt3Value.clear();
    _warehouseId = _defaultWarehouseId;
    _status = 'active';
    _autoGenerateBarcode = true;
    _weightUnit = 'kg';
    _dimensionUnit = 'cm';
    _skuError = null;
    _priceError = null;
    _qtyError = null;
    _parentError = null;
    _formError = null;
    _saving = false;
    if (keepParent != null) {
      _sku.text = '${keepParent.sku}-V${keepParent.variantCount + 2}';
    }
    setState(() {});
    _skuFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = ref.watch(onlineProvider);
    final register = ref.watch(currentRegisterProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text("Add Vt's."),
        actions: [
          if (!online)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text('Offline', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.error)),
              ),
            ),
          if (widget.embedded) const ShellStatusActions(),
        ],
      ),
      body: !_defaultsReady
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Text(
                      register == null ? 'New variant' : 'New variant · ${register.name}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      register?.warehouseName != null && register!.warehouseName!.trim().isNotEmpty
                          ? 'Stock saves to this register’s warehouse (${register.warehouseName}). Switch register to use another store (e.g. Croma vs Reliance).'
                          : 'Pick the parent product, then set SKU, options, barcode, prices and stock.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    CatalogDefaultsStrip(
                      chips: [
                        CatalogDefaultChip(
                          label: _warehouseIsDefault
                              ? 'Register WH · $_warehouseLabel'
                              : 'Stock · $_warehouseLabel',
                          isDefault: _warehouseIsDefault,
                          onTap: _pickWarehouse,
                        ),
                        CatalogDefaultChip(
                          label: _statusLabel,
                          isDefault: _status == 'active',
                          onTap: _pickStatus,
                        ),
                        CatalogDefaultChip(
                          label: 'Currency $_currency',
                          isDefault: _currency == 'GBP',
                          onTap: _pickCurrency,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_formError != null) ...[
                      CatalogErrorBanner(message: _formError!),
                      const SizedBox(height: 16),
                    ],
                    if (!online) ...[
                      const CatalogErrorBanner(message: 'You are offline. Reconnect to save — your entries stay on this form.'),
                      const SizedBox(height: 16),
                    ],
                    const CatalogSectionTitle(title: 'Parent product'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: _parent == null
                          ? catalogRequiredLabel('Search catalogue product')
                          : Text(_parent!.name),
                      subtitle: Text(
                        _parentError ??
                            (_parent == null
                                ? (_searchingParents ? 'Searching…' : 'Required — tap to search')
                                : _parent!.label),
                        style: _parentError != null ? TextStyle(color: theme.colorScheme.error) : null,
                      ),
                      trailing: const Icon(Icons.search),
                      onTap: _pickParent,
                    ),
                    if (_parentHits.isNotEmpty && _parent == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Recent: ${_parentHits.take(3).map((e) => e.name).join(', ')}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const CatalogSectionTitle(title: 'Variant'),
                    TextFormField(
                      controller: _sku,
                      focusNode: _skuFocus,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        label: catalogRequiredLabel('Variant SKU'),
                        errorText: _skuError,
                        hintText: 'Unique sellable code',
                      ),
                      onChanged: (_) {
                        if (_skuError != null) setState(() => _skuError = null);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Variant name',
                        hintText: 'Optional label on Sell',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _barcode,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Barcode',
                        hintText: 'Leave empty to auto-generate',
                        prefixIcon: const Icon(Icons.qr_code_2_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Scan with camera',
                          onPressed: _scanBarcode,
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                      ),
                      onChanged: (v) {
                        if (v.trim().isNotEmpty && _autoGenerateBarcode) {
                          setState(() => _autoGenerateBarcode = false);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-generate barcode if empty'),
                      subtitle: const Text('Creates a unique internal EAN-13 from the variant SKU.'),
                      value: _autoGenerateBarcode && _barcode.text.trim().isEmpty,
                      onChanged: _barcode.text.trim().isNotEmpty
                          ? null
                          : (v) => setState(() => _autoGenerateBarcode = v),
                    ),
                    const SizedBox(height: 12),
                    const CatalogSectionTitle(title: 'Options'),
                    Text(
                      'Optional size / colour pairs shown on Sell.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    for (final pair in [
                      (_opt1Name, _opt1Value, 'Option 1'),
                      (_opt2Name, _opt2Value, 'Option 2'),
                      (_opt3Name, _opt3Value, 'Option 3'),
                    ]) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: pair.$1,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(labelText: '${pair.$3} name', hintText: 'e.g. Size'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: pair.$2,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(labelText: '${pair.$3} value', hintText: 'e.g. Large'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    const CatalogSectionTitle(title: 'Price & stock'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _price,
                            focusNode: _priceFocus,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              label: catalogRequiredLabel('Sell price'),
                              prefixText: '$_currency ',
                              errorText: _priceError,
                              hintText: '0.00',
                            ),
                            onChanged: (_) {
                              if (_priceError != null) setState(() => _priceError = null);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _cost,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Cost price',
                              prefixText: '$_currency ',
                              hintText: '0.00',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: catalogRequiredLabel(
                        _warehouseIsDefault ? 'Register warehouse' : 'Stock warehouse',
                      ),
                      subtitle: Text(
                        _warehouseIsDefault
                            ? '$_warehouseLabel${_registerName != null ? ' · $_registerName' : ''} (Sell shows this qty)'
                            : '$_warehouseLabel — Sell only shows qty if the till register uses this warehouse',
                      ),
                      trailing: const Icon(Icons.expand_more),
                      onTap: _pickWarehouse,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _qty,
                            focusNode: _qtyFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              label: catalogRequiredLabel('Starting / opening stock'),
                              errorText: _qtyError,
                              helperText: 'Written to stock_items at $_warehouseLabel',
                            ),
                            onChanged: (_) {
                              if (_qtyError != null) setState(() => _qtyError = null);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _reorderLevel,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Reorder level',
                              hintText: 'Optional',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _reorderQty,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Reorder quantity',
                              hintText: 'Optional',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Rack'),
                            subtitle: Text(_rackLabel ?? 'Optional · $_warehouseLabel'),
                            trailing: const Icon(Icons.expand_more),
                            onTap: _pickRack,
                          ),
                        ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bin'),
                      subtitle: Text(
                        _binLabel ??
                            (_rackLabel != null
                                ? 'Optional · filtered by $_rackLabel'
                                : 'Optional · $_warehouseLabel'),
                      ),
                      trailing: const Icon(Icons.expand_more),
                      onTap: _pickBin,
                    ),
                    const SizedBox(height: 22),
                    const CatalogSectionTitle(title: 'Physical properties'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _weight,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Weight', hintText: 'Optional'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Weight unit'),
                            subtitle: Text(_weightUnit),
                            trailing: const Icon(Icons.expand_more),
                            onTap: _pickWeightUnit,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _length,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Length'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _width,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Width'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _height,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Height'),
                          ),
                        ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dimension unit'),
                      subtitle: Text(_dimensionUnit),
                      trailing: const Icon(Icons.expand_more),
                      onTap: _pickDimensionUnit,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving || !online ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.style_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save variant'),
                    ),
                    if (_saving) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Creating variant, stock and price…',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

enum _AfterSave { addAnother, backToSell }
