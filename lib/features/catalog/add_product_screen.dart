import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/security/permissions.dart';
import '../../core/sync/connectivity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../shell/app_shell.dart';
import '../shell/status_bar.dart';

const _currencyOptions = ['GBP', 'EUR', 'USD', 'AED', 'AUD', 'CAD', 'CHF', 'INR', 'NZD', 'SAR', 'ZAR'];

/// Manager + online gate shared by the sidebar tab and Options → Add product.
Future<bool> ensureCanAddProduct(BuildContext context, WidgetRef ref) async {
  if (!await requirePermission(context, ref, Perm.createCatalogProduct) || !context.mounted) return false;
  if (!ref.read(onlineProvider)) {
    showMessage(context, 'Adding a product needs an online connection.', error: true);
    return false;
  }
  return true;
}

/// Opens the Add Product page after a manager gate. Returns true if the page was shown.
Future<bool> openAddProductScreen(BuildContext context, WidgetRef ref, {String? initialBarcode}) async {
  if (!await ensureCanAddProduct(context, ref) || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AddProductScreen(initialBarcode: initialBarcode)),
  );
  return true;
}

/// Full-page form to create a catalogue product into inventory from the till.
/// Field set mirrors ERP Catalog Items → Add Item (create).
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, this.embedded = false, this.initialBarcode});

  /// True when shown as a shell tab (no back button; status actions in the app bar).
  final bool embedded;

  /// Prefill barcode when opened from an unknown scan on Sell.
  final String? initialBarcode;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _qty = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final _sku = TextEditingController();
  final _category = TextEditingController();
  final _subCategory = TextEditingController();
  final _brand = TextEditingController();
  final _packSize = TextEditingController();
  final _uom = TextEditingController(text: 'each');
  final _description = TextEditingController();
  final _remarks = TextEditingController();
  final _reorderLevel = TextEditingController();
  final _reorderQty = TextEditingController();
  final _binCode = TextEditingController();
  final _lotNumber = TextEditingController();
  final _supplierName = TextEditingController();
  final _supplierSku = TextEditingController();
  final _leadTime = TextEditingController();

  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _qtyFocus = FocusNode();

  String? _taxCodeId;
  String? _warehouseId;
  String _status = 'active';
  String _currency = 'GBP';
  DateTime? _expiryDate;
  final List<_AttrRow> _attributes = [];

  late final TaxCodeInfo _defaultTax;
  late final String? _defaultWarehouseId;
  late final String _defaultWarehouseLabel;
  late final String _defaultCategory;
  late final String _defaultUom;
  late final String _defaultStatus;
  late final String _defaultCurrency;
  late final String _defaultPriceListLabel;

  String? _nameError;
  String? _priceError;
  String? _qtyError;
  String? _formError;
  bool _saving = false;
  bool _defaultsReady = false;
  bool _showMoreDetails = false;
  bool _loadingClassifications = false;
  String? _classificationsHint;
  bool _classificationsFromProducts = false;

  Map<String, List<String>> _classifications = const {
    'category': [],
    'sub_category': [],
    'brand': [],
    'uom': [],
    'pack_size': [],
  };

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
    final catalog = ref.read(catalogProvider);

    _defaultTax = pickOrgOrUkVat(boot.taxCodes);
    _taxCodeId = _defaultTax.id.isEmpty ? null : _defaultTax.id;

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

    await _reloadClassifications(silent: true);

    final masterCats = _classifications['category'] ?? const <String>[];
    _defaultCategory = masterCats.isNotEmpty ? _mostCommonCategory(masterCats) : _mostCommonCategory(catalog.categories);
    if (_defaultCategory.isNotEmpty) _category.text = _defaultCategory;

    final masterUoms = _classifications['uom'] ?? const <String>[];
    _defaultUom = masterUoms.contains('each')
        ? 'each'
        : (masterUoms.isNotEmpty ? masterUoms.first : 'each');
    _uom.text = _defaultUom;
    _defaultStatus = 'active';
    _status = _defaultStatus;
    _defaultCurrency = 'GBP';
    _currency = _defaultCurrency;

    _defaultPriceListLabel = register?.priceListId != null && register!.priceListId!.isNotEmpty
        ? 'Register price list'
        : 'Catalogue sell price';

    if (!mounted) return;
    setState(() => _defaultsReady = true);
    _nameFocus.requestFocus();
  }

  String _mostCommonCategory(List<String> cats) {
    if (cats.isEmpty) return '';
    final counts = <String, int>{};
    for (final p in ref.read(catalogProvider).products.values) {
      final c = p.category?.trim();
      if (c == null || c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    if (counts.isEmpty) return cats.first;
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  Future<void> _reloadClassifications({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingClassifications = true);
    try {
      final result = await ref.read(catalogProvider.notifier).listClassifications();
      if (!mounted) return;
      setState(() {
        _classifications = result.lists;
        _classificationsHint = result.hint;
        _classificationsFromProducts = result.fromProducts;
        _loadingClassifications = false;
      });
      if (!silent) {
        final n = (_classifications['category'] ?? const []).length;
        showMessage(context, n > 0 ? 'Loaded $n categories.' : 'Still no categories — ask an admin to Import from products in ERP.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingClassifications = false);
      if (!silent) showMessage(context, 'Could not refresh classifications. Check the connection.', error: true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _qty.dispose();
    _barcode.dispose();
    _sku.dispose();
    _category.dispose();
    _subCategory.dispose();
    _brand.dispose();
    _packSize.dispose();
    _uom.dispose();
    _description.dispose();
    _remarks.dispose();
    _reorderLevel.dispose();
    _reorderQty.dispose();
    _binCode.dispose();
    _lotNumber.dispose();
    _supplierName.dispose();
    _supplierSku.dispose();
    _leadTime.dispose();
    for (final a in _attributes) {
      a.key.dispose();
      a.value.dispose();
    }
    _nameFocus.dispose();
    _priceFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  bool get _warehouseIsDefault => _warehouseId == _defaultWarehouseId;
  bool get _taxIsDefault {
    final defId = _defaultTax.id.isEmpty ? null : _defaultTax.id;
    return _taxCodeId == defId;
  }

  bool get _categoryIsDefault {
    final current = _category.text.trim();
    if (_defaultCategory.isEmpty) return current.isEmpty;
    return current == _defaultCategory;
  }

  bool get _uomIsDefault => _uom.text.trim().toLowerCase() == _defaultUom;
  bool get _statusIsDefault => _status == _defaultStatus;
  bool get _currencyIsDefault => _currency == _defaultCurrency;

  TaxCodeInfo get _selectedTax {
    final boot = ref.read(bootstrapProvider);
    return boot.taxCodes.where((t) => t.id == _taxCodeId).firstOrNull ?? _defaultTax;
  }

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
    setState(() => _warehouseId = choice);
  }

  Future<void> _pickTax() async {
    final boot = ref.read(bootstrapProvider);
    final codes = [...boot.taxCodes];
    if (codes.isEmpty) {
      showMessage(context, 'No VAT codes on this organisation. Product will use 20%.', error: true);
      return;
    }
    codes.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.rate.compareTo(b.rate);
    });
    final choice = await pickOption<String>(
      context,
      title: 'VAT / tax',
      options: [
        for (final t in codes)
          (t.id, '${t.name} (${t.percentLabel})${t.isDefault ? ' · Default' : ''}'),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() => _taxCodeId = choice);
  }

  Future<void> _pickFromClassifications({
    required String type,
    required String title,
    required TextEditingController controller,
    String? defaultValue,
    bool allowEmpty = true,
    String emptyLabel = 'None',
  }) async {
    final options = List<String>.from(_classifications[type] ?? const []);
    final current = controller.text.trim();
    if (current.isNotEmpty && !options.contains(current)) options.insert(0, current);
    if (options.isEmpty) {
      final refresh = await confirm(
        context,
        title: 'No ${title.toLowerCase()}s yet',
        message:
            'Ask an admin in ERP → Catalog → Classifications (Manage Classifications) to add values or Import from products, then tap Refresh here.\n\nRefresh now?',
        confirmLabel: 'Refresh',
      );
      if (refresh && mounted) await _reloadClassifications();
      return;
    }
    final choice = await pickOption<String>(
      context,
      title: title,
      options: [
        if (allowEmpty) ('', emptyLabel),
        for (final o in options) (o, o + (defaultValue != null && o == defaultValue ? ' · Default' : '')),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() => controller.text = choice);
  }

  Future<void> _pickCategory() => _pickFromClassifications(
        type: 'category',
        title: 'Category',
        controller: _category,
        defaultValue: _defaultCategory,
        emptyLabel: 'No category',
      );

  Future<void> _pickSubCategory() => _pickFromClassifications(
        type: 'sub_category',
        title: 'Sub-category',
        controller: _subCategory,
        emptyLabel: 'None',
      );

  Future<void> _pickBrand() => _pickFromClassifications(
        type: 'brand',
        title: 'Brand',
        controller: _brand,
        emptyLabel: 'None',
      );

  Future<void> _pickPackSize() => _pickFromClassifications(
        type: 'pack_size',
        title: 'Pack size',
        controller: _packSize,
        emptyLabel: 'None',
      );

  Future<void> _pickUom() => _pickFromClassifications(
        type: 'uom',
        title: 'Sold as',
        controller: _uom,
        defaultValue: _defaultUom,
        allowEmpty: false,
      );

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
    final code = await scanWithCamera(context, title: 'Scan product barcode');
    if (code == null || !mounted) return;
    setState(() => _barcode.text = code.trim());
  }

  Future<void> _pickCurrency() async {
    final choice = await pickOption<String>(
      context,
      title: 'Currency',
      options: [
        for (final c in _currencyOptions) (c, c + (c == _defaultCurrency ? ' · Default' : '')),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() => _currency = choice);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() => _expiryDate = picked);
  }

  void _addAttribute() {
    setState(() => _attributes.add(_AttrRow()));
  }

  void _removeAttribute(int i) {
    setState(() {
      final row = _attributes.removeAt(i);
      row.key.dispose();
      row.value.dispose();
    });
  }

  Map<String, dynamic>? _collectAttributes() {
    final map = <String, dynamic>{};
    for (final a in _attributes) {
      final k = a.key.text.trim();
      if (k.isEmpty) continue;
      map[k] = a.value.text.trim();
    }
    return map.isEmpty ? null : map;
  }

  num? _optionalNumber(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  int? _optionalInt(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  bool _validate() {
    String? nameErr;
    String? priceErr;
    String? qtyErr;
    final name = _name.text.trim();
    if (name.isEmpty) nameErr = 'Enter a product name';
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
          _nameError = nameErr;
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
    final reorder = _optionalNumber(_reorderLevel);
    if (_reorderLevel.text.trim().isNotEmpty && (reorder == null || reorder < 0)) {
      setState(() {
        _formError = 'Reorder level must be a number zero or greater.';
        _nameError = nameErr;
        _priceError = priceErr;
        _qtyError = qtyErr;
      });
      return false;
    }
    final reorderQ = _optionalNumber(_reorderQty);
    if (_reorderQty.text.trim().isNotEmpty && (reorderQ == null || reorderQ < 0)) {
      setState(() {
        _formError = 'Reorder quantity must be a number zero or greater.';
        _nameError = nameErr;
        _priceError = priceErr;
        _qtyError = qtyErr;
      });
      return false;
    }
    if (_leadTime.text.trim().isNotEmpty && _optionalInt(_leadTime) == null) {
      setState(() {
        _formError = 'Lead time must be a whole number of days.';
        _nameError = nameErr;
        _priceError = priceErr;
        _qtyError = qtyErr;
      });
      return false;
    }
    if (_warehouseId == null || _warehouseId!.isEmpty) {
      setState(() {
        _nameError = nameErr;
        _priceError = priceErr;
        _qtyError = qtyErr;
        _formError = 'This register has no stock location. Set one under Options → Change Register.';
      });
      return false;
    }
    setState(() {
      _nameError = nameErr;
      _priceError = priceErr;
      _qtyError = qtyErr;
      _formError = null;
    });
    if (nameErr != null) {
      _nameFocus.requestFocus();
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
      final product = await ref.read(catalogProvider.notifier).createProduct(
            name: _name.text.trim(),
            sellPricePence: parsePence(_price.text)!,
            quantity: int.parse(_qty.text.trim()),
            sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            category: _category.text.trim().isEmpty ? null : _category.text.trim(),
            subCategory: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim(),
            brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
            packSize: _packSize.text.trim().isEmpty ? null : _packSize.text.trim(),
            costPricePence: costPence,
            currency: _currency,
            taxCodeId: _taxCodeId,
            uom: _uom.text.trim().isEmpty ? _defaultUom : _uom.text.trim(),
            status: _status,
            warehouseId: _warehouseId,
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
            reorderLevel: _optionalNumber(_reorderLevel),
            reorderQuantity: _optionalNumber(_reorderQty),
            binCode: _binCode.text.trim().isEmpty ? null : _binCode.text.trim(),
            lotNumber: _lotNumber.text.trim().isEmpty ? null : _lotNumber.text.trim(),
            expiryDate: _expiryDate == null ? null : DateFormat('yyyy-MM-dd').format(_expiryDate!),
            supplierName: _supplierName.text.trim().isEmpty ? null : _supplierName.text.trim(),
            supplierSku: _supplierSku.text.trim().isEmpty ? null : _supplierSku.text.trim(),
            leadTimeDays: _optionalInt(_leadTime),
            attributes: _collectAttributes(),
          );
      if (!mounted) return;
      showMessage(context, '${product.displayName} added to inventory.');
      final next = await showDialog<_AfterSave>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Product saved'),
          content: Text(
            '${product.displayName} is in the catalogue at ${formatPence(product.effectivePricePence)}'
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
        unawaited(_reloadClassifications(silent: true));
      } else {
        if (!widget.embedded) Navigator.of(context).pop();
        ref.read(shellTabProvider.notifier).go(0);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = errorMessage(e);
      setState(() {
        _saving = false;
        if (msg.toLowerCase().contains('barcode')) {
          _formError = msg;
        } else if (msg.toLowerCase().contains('sku')) {
          _formError = msg;
        } else if (e is ApiException && e.statusCode == 403) {
          _formError = 'Only a till manager can add products. Ask a manager to enter their PIN, then try again.';
        } else {
          _formError = 'Could not save: $msg. Your entries are still here — fix and try again.';
        }
      });
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  void _resetForAnother() {
    _name.clear();
    _price.clear();
    _cost.clear();
    _qty.text = '0';
    _barcode.clear();
    _sku.clear();
    _description.clear();
    _remarks.clear();
    _subCategory.clear();
    _brand.clear();
    _packSize.clear();
    _reorderLevel.clear();
    _reorderQty.clear();
    _binCode.clear();
    _lotNumber.clear();
    _supplierName.clear();
    _supplierSku.clear();
    _leadTime.clear();
    _expiryDate = null;
    for (final a in _attributes) {
      a.key.dispose();
      a.value.dispose();
    }
    _attributes.clear();
    _category.text = _defaultCategory;
    _uom.text = _defaultUom;
    _taxCodeId = _defaultTax.id.isEmpty ? null : _defaultTax.id;
    _warehouseId = _defaultWarehouseId;
    _status = _defaultStatus;
    _currency = _defaultCurrency;
    _nameError = null;
    _priceError = null;
    _qtyError = null;
    _formError = null;
    _saving = false;
    setState(() {});
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = ref.watch(onlineProvider);
    final register = ref.watch(currentRegisterProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Add product'),
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
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    children: [
                      Text(
                        register == null ? 'New inventory item' : 'New inventory item · ${register.name}',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Name, price and stock are enough for most items. Tap a chip above to change warehouse, VAT or category.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _DefaultsStrip(
                        chips: [
                          _DefaultChip(
                            label: 'Warehouse $_warehouseLabel',
                            isDefault: _warehouseIsDefault,
                            onTap: _pickWarehouse,
                          ),
                          _DefaultChip(
                            label: 'Tax ${_selectedTax.percentLabel}',
                            isDefault: _taxIsDefault,
                            onTap: _pickTax,
                          ),
                          _DefaultChip(
                            label: _category.text.trim().isEmpty ? 'Category —' : 'Category ${_category.text.trim()}',
                            isDefault: _categoryIsDefault,
                            onTap: _pickCategory,
                          ),
                          _DefaultChip(
                            label: 'Sold as ${_uom.text.trim().isEmpty ? _defaultUom : _uom.text.trim()}',
                            isDefault: _uomIsDefault,
                            onTap: _pickUom,
                          ),
                          _DefaultChip(
                            label: _statusLabel,
                            isDefault: _statusIsDefault,
                            onTap: _pickStatus,
                          ),
                          _DefaultChip(
                            label: 'Currency $_currency',
                            isDefault: _currencyIsDefault,
                            onTap: _pickCurrency,
                          ),
                          _DefaultChip(
                            label: _defaultPriceListLabel,
                            isDefault: true,
                            onTap: null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_formError != null) ...[
                        _ErrorBanner(message: _formError!),
                        const SizedBox(height: 16),
                      ],
                      if (!online) ...[
                        _ErrorBanner(message: 'You are offline. Reconnect to save — your entries stay on this form.'),
                        const SizedBox(height: 16),
                      ],

                      _SectionTitle(title: 'Identity'),
                      TextFormField(
                        controller: _name,
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Product name',
                          errorText: _nameError,
                          hintText: 'Name on Sell and receipts',
                        ),
                        onChanged: (_) {
                          if (_nameError != null) setState(() => _nameError = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _sku,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Item code',
                                hintText: 'Leave blank to auto-create',
                                helperText: 'Optional on the till',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _barcode,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Barcode',
                                hintText: 'Scan or type',
                                prefixIcon: const Icon(Icons.qr_code_2_outlined),
                                suffixIcon: IconButton(
                                  tooltip: 'Scan with camera',
                                  onPressed: _scanBarcode,
                                  icon: const Icon(Icons.qr_code_scanner),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 22),
                      _SectionTitle(title: 'Category & unit'),
                      if (_classificationsHint != null ||
                          _classificationsFromProducts ||
                          (_classifications['category'] ?? const []).isEmpty) ...[
                        _HintBanner(
                          message: _classificationsHint ??
                              (_classificationsFromProducts
                                  ? 'Using categories from products already on this till. An admin can save them in ERP → Catalog → Classifications (Manage Classifications) → Import from products.'
                                  : 'No categories yet. In ERP open Catalog → Classifications (Manage Classifications), add values or Import from products, then tap Refresh.'),
                          actionLabel: _loadingClassifications ? 'Refreshing…' : 'Refresh',
                          onAction: _loadingClassifications ? null : () => _reloadClassifications(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Category'),
                              subtitle: Text(_category.text.trim().isEmpty ? 'Tap to choose' : _category.text.trim()),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickCategory,
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Sub-category'),
                              subtitle: Text(_subCategory.text.trim().isEmpty ? 'Optional' : _subCategory.text.trim()),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickSubCategory,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Brand'),
                              subtitle: Text(_brand.text.trim().isEmpty ? 'Optional' : _brand.text.trim()),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickBrand,
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Sold as'),
                              subtitle: Text(_uom.text.trim().isEmpty ? _defaultUom : _uom.text.trim()),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickUom,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Pack size'),
                              subtitle: Text(_packSize.text.trim().isEmpty ? 'Optional' : _packSize.text.trim()),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickPackSize,
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Sell status'),
                              subtitle: Text(_statusLabel),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickStatus,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      _SectionTitle(title: 'Price'),
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
                                labelText: 'Sell price',
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
                                labelText: 'Cost (optional)',
                                prefixText: '$_currency ',
                                hintText: '0.00',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Currency'),
                              subtitle: Text(_currency),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickCurrency,
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('VAT'),
                              subtitle: Text('${_selectedTax.name} (${_selectedTax.percentLabel})'),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickTax,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      _SectionTitle(title: 'Stock'),
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
                                labelText: 'Starting stock',
                                errorText: _qtyError,
                                helperText: 'How many you have now at $_warehouseLabel',
                              ),
                              onChanged: (_) {
                                if (_qtyError != null) setState(() => _qtyError = null);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Stock location'),
                              subtitle: Text(_warehouseLabel),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickWarehouse,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Material(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _showMoreDetails = !_showMoreDetails),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _showMoreDetails ? 'Hide extra details' : 'More details (optional)',
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Icon(_showMoreDetails ? Icons.expand_less : Icons.expand_more),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_showMoreDetails) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText: 'Short product description',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _reorderLevel,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Reorder when stock hits',
                                  hintText: 'Optional',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _reorderQty,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Reorder quantity',
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
                                controller: _binCode,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Shelf / bin', hintText: 'Optional'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _lotNumber,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Batch / lot', hintText: 'Optional'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Expiry date'),
                          subtitle: Text(
                            _expiryDate == null ? 'Not set' : DateFormat.yMMMd().format(_expiryDate!),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_expiryDate != null)
                                IconButton(
                                  tooltip: 'Clear',
                                  onPressed: () => setState(() => _expiryDate = null),
                                  icon: const Icon(Icons.clear),
                                ),
                              const Icon(Icons.calendar_today_outlined),
                            ],
                          ),
                          onTap: _pickExpiry,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _supplierName,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Supplier', hintText: 'Optional'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _supplierSku,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Supplier code', hintText: 'Optional'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _leadTime,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Days to restock',
                            hintText: 'Optional',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _remarks,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Internal note',
                            hintText: 'Staff only',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('Extra fields', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _addAttribute,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add'),
                            ),
                          ],
                        ),
                        Text(
                          'Optional pairs such as colour → black.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _attributes.length; i++) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _attributes[i].key,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. colour'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _attributes[i].value,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(labelText: 'Value', hintText: 'e.g. black'),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _removeAttribute(i),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 8),
                        _AdvancedNote(
                          message:
                              'Photos and size/colour matrices stay in ERP. Everything else for a simple product is on this screen.',
                        ),
                      ],

                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving || !online ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add_box_outlined),
                        label: Text(_saving ? 'Saving…' : 'Save product'),
                      ),
                      if (_saving) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Creating catalogue item, stock and price…',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

enum _AfterSave { addAnother, backToSell }

class _AttrRow {
  _AttrRow()
      : key = TextEditingController(),
        value = TextEditingController();
  final TextEditingController key;
  final TextEditingController value;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _DefaultsStrip extends StatelessWidget {
  const _DefaultsStrip({required this.chips});
  final List<_DefaultChip> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? ZaamColors.charcoal : const Color(0xFFF5EADA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZaamColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Using',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}

class _DefaultChip extends StatelessWidget {
  const _DefaultChip({required this.label, required this.isDefault, this.onTap});
  final String label;
  final bool isDefault;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isDefault
        ? (theme.brightness == Brightness.dark ? ZaamColors.gold.withValues(alpha: 0.22) : Colors.white)
        : theme.colorScheme.surfaceContainerHighest;
    final border = isDefault ? ZaamColors.gold.withValues(alpha: 0.45) : theme.dividerColor;
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDefault ? ZaamColors.gold.withValues(alpha: 0.18) : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isDefault ? 'Default' : 'Custom',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDefault ? theme.colorScheme.primary : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                Icon(Icons.expand_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.message, required this.actionLabel, this.onAction});
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _AdvancedNote extends StatelessWidget {
  const _AdvancedNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
