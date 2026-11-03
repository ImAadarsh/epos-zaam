import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/sync/connectivity.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../shell/app_shell.dart';
import '../shell/status_bar.dart';
import 'catalog_form_shared.dart';

export 'catalog_form_shared.dart' show ensureCanAddProduct;

const _currencyOptions = ['GBP', 'EUR', 'USD', 'AED', 'AUD', 'CAD', 'CHF', 'INR', 'NZD', 'SAR', 'ZAR'];

/// Opens Add Prod. after a manager gate. Returns true if the page was shown.
Future<bool> openAddProductScreen(BuildContext context, WidgetRef ref) async {
  if (!await ensureCanAddProduct(context, ref) || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const AddProductScreen()),
  );
  return true;
}

/// Create a catalogue product (`catalog_items` only). Variants → Add Vt's.
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, this.embedded = false});

  /// True when shown as a shell tab (no back button; status actions in the app bar).
  final bool embedded;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _category = TextEditingController();
  final _subCategory = TextEditingController();
  final _brand = TextEditingController();
  final _packSize = TextEditingController();
  final _uom = TextEditingController(text: 'each');
  final _description = TextEditingController();
  final _remarks = TextEditingController();
  final _supplierSku = TextEditingController();
  final _leadTime = TextEditingController();
  final _hsCode = TextEditingController();
  final _country = TextEditingController();

  final _nameFocus = FocusNode();

  String? _taxCodeId;
  String _status = 'active';
  String _currency = 'GBP';

  late final TaxCodeInfo _defaultTax;
  late final String _defaultCategory;
  late final String _defaultUom;
  late final String _defaultStatus;
  late final String _defaultCurrency;

  String? _nameError;
  String? _formError;
  bool _saving = false;
  bool _defaultsReady = false;
  bool _showMoreDetails = false;
  bool _loadingClassifications = false;
  String? _classificationsHint;
  bool _classificationsFromProducts = false;

  Map<String, List<({String id, String name})>> _classifications = const {
    'category': [],
    'sub_category': [],
    'brand': [],
    'uom': [],
    'pack_size': [],
  };
  String? _categoryId;
  String? _subCategoryId;
  String? _brandId;
  String? _packSizeId;
  String? _uomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapDefaults());
  }

  Future<void> _bootstrapDefaults() async {
    final boot = ref.read(bootstrapProvider);
    final catalog = ref.read(catalogProvider);

    _defaultTax = pickOrgOrUkVat(boot.taxCodes);
    _taxCodeId = _defaultTax.id.isEmpty ? null : _defaultTax.id;

    await _reloadClassifications(silent: true);

    final masterCats = _classifications['category'] ?? const <({String id, String name})>[];
    final catNames = masterCats.map((o) => o.name).toList();
    _defaultCategory = catNames.isNotEmpty ? _mostCommonCategory(catNames) : _mostCommonCategory(catalog.categories);
    if (_defaultCategory.isNotEmpty) {
      _category.text = _defaultCategory;
      final match = masterCats.where((o) => o.name == _defaultCategory).toList();
      _categoryId = match.isNotEmpty ? match.first.id : null;
    }

    final masterUoms = _classifications['uom'] ?? const <({String id, String name})>[];
    final each = masterUoms.where((o) => o.name == 'each').toList();
    if (each.isNotEmpty) {
      _defaultUom = 'each';
      _uomId = each.first.id;
    } else if (masterUoms.isNotEmpty) {
      _defaultUom = masterUoms.first.name;
      _uomId = masterUoms.first.id;
    } else {
      _defaultUom = 'each';
      _uomId = null;
    }
    _uom.text = _defaultUom;
    _defaultStatus = 'active';
    _status = _defaultStatus;
    _defaultCurrency = 'GBP';
    _currency = _defaultCurrency;

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
        _classifications = result.options;
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
    _sku.dispose();
    _category.dispose();
    _subCategory.dispose();
    _brand.dispose();
    _packSize.dispose();
    _uom.dispose();
    _description.dispose();
    _remarks.dispose();
    _supplierSku.dispose();
    _leadTime.dispose();
    _hsCode.dispose();
    _country.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

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

  String get _statusLabel => switch (_status) {
        'inactive' => 'Hidden from Sell',
        'discontinued' => 'Discontinued',
        _ => 'On sale',
      };

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
        for (final t in codes) (t.id, '${t.name} (${t.percentLabel})${t.isDefault ? ' · Default' : ''}'),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() => _taxCodeId = choice);
  }

  Future<void> _pickFromClassifications({
    required String type,
    required String title,
    required TextEditingController controller,
    required void Function(String? id) setId,
    String? currentId,
    String? defaultValue,
    bool allowEmpty = true,
    String emptyLabel = 'None',
  }) async {
    final options = List<({String id, String name})>.from(_classifications[type] ?? const []);
    final current = controller.text.trim();
    if (current.isNotEmpty && !options.any((o) => o.name == current)) {
      options.insert(0, (id: currentId ?? 'product:$type:$current', name: current));
    }
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
        for (final o in options)
          (o.id, o.name + (defaultValue != null && o.name == defaultValue ? ' · Default' : '')),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice.isEmpty) {
      setState(() {
        controller.text = '';
        setId(null);
      });
      return;
    }
    final match = options.where((o) => o.id == choice).toList();
    final name = match.isNotEmpty ? match.first.name : choice;
    setState(() {
      controller.text = name;
      setId(choice);
    });
  }

  Future<void> _pickCategory() => _pickFromClassifications(
        type: 'category',
        title: 'Category',
        controller: _category,
        currentId: _categoryId,
        setId: (id) => _categoryId = id,
        defaultValue: _defaultCategory,
        emptyLabel: 'No category',
      );

  Future<void> _pickSubCategory() => _pickFromClassifications(
        type: 'sub_category',
        title: 'Sub-category',
        controller: _subCategory,
        currentId: _subCategoryId,
        setId: (id) => _subCategoryId = id,
      );

  Future<void> _pickBrand() => _pickFromClassifications(
        type: 'brand',
        title: 'Brand',
        controller: _brand,
        currentId: _brandId,
        setId: (id) => _brandId = id,
      );

  Future<void> _pickPackSize() => _pickFromClassifications(
        type: 'pack_size',
        title: 'Pack size',
        controller: _packSize,
        currentId: _packSizeId,
        setId: (id) => _packSizeId = id,
      );

  Future<void> _pickUom() => _pickFromClassifications(
        type: 'uom',
        title: 'Sold as',
        controller: _uom,
        currentId: _uomId,
        setId: (id) => _uomId = id,
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

  int? _optionalInt(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  bool _validate() {
    String? nameErr;
    final name = _name.text.trim();
    if (name.isEmpty) nameErr = 'Enter a product name';
    if (_leadTime.text.trim().isNotEmpty && _optionalInt(_leadTime) == null) {
      setState(() {
        _formError = 'Lead time must be a whole number of days.';
        _nameError = nameErr;
      });
      return false;
    }
    setState(() {
      _nameError = nameErr;
      _formError = null;
    });
    if (nameErr != null) {
      _nameFocus.requestFocus();
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
      final item = await ref.read(catalogProvider.notifier).createCatalogItem(
            name: _name.text.trim(),
            sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
            categoryId: _categoryId,
            category: _category.text.trim().isEmpty ? null : _category.text.trim(),
            subCategoryId: _subCategoryId,
            subCategory: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim(),
            brandId: _brandId,
            brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
            packSizeId: _packSizeId,
            packSize: _packSize.text.trim().isEmpty ? null : _packSize.text.trim(),
            currency: _currency,
            taxCodeId: _taxCodeId,
            uomId: _uomId,
            uom: _uom.text.trim().isEmpty ? _defaultUom : _uom.text.trim(),
            status: _status,
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
            supplierSku: _supplierSku.text.trim().isEmpty ? null : _supplierSku.text.trim(),
            leadTimeDays: _optionalInt(_leadTime),
            hsCode: _hsCode.text.trim().isEmpty ? null : _hsCode.text.trim(),
            countryOfOrigin: _country.text.trim().isEmpty ? null : _country.text.trim().toUpperCase(),
          );
      if (!mounted) return;
      final displayName = '${item['name'] ?? _name.text.trim()}';
      showMessage(context, '$displayName saved. Add a variant under Add Vt\'s. to sell it.');
      final next = await showDialog<_AfterSave>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Product saved'),
          content: Text(
            '$displayName is in the catalogue. Add sell price, barcode and stock under Add Vt\'s.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, _AfterSave.addAnother), child: const Text('Add another')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _AfterSave.addVariant),
              child: const Text('Add variant'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, _AfterSave.backToSell), child: const Text('Back to Sell')),
          ],
        ),
      );
      if (!mounted) return;
      if (next == _AfterSave.addAnother) {
        _resetForAnother();
        unawaited(_reloadClassifications(silent: true));
      } else if (next == _AfterSave.addVariant) {
        if (!widget.embedded) Navigator.of(context).pop();
        ref.read(shellTabProvider.notifier).go(AppShell.addVariantTab);
      } else {
        if (!widget.embedded) Navigator.of(context).pop();
        ref.read(shellTabProvider.notifier).go(0);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = errorMessage(e);
      setState(() {
        _saving = false;
        if (msg.toLowerCase().contains('sku')) {
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
    _sku.clear();
    _description.clear();
    _remarks.clear();
    _subCategory.clear();
    _brand.clear();
    _packSize.clear();
    _supplierSku.clear();
    _leadTime.clear();
    _hsCode.clear();
    _country.clear();
    _category.text = _defaultCategory;
    final catMatch = (_classifications['category'] ?? const []).where((o) => o.name == _defaultCategory).toList();
    _categoryId = catMatch.isNotEmpty ? catMatch.first.id : null;
    _subCategoryId = null;
    _brandId = null;
    _packSizeId = null;
    _uom.text = _defaultUom;
    final uomMatch = (_classifications['uom'] ?? const []).where((o) => o.name == _defaultUom).toList();
    _uomId = uomMatch.isNotEmpty ? uomMatch.first.id : null;
    _taxCodeId = _defaultTax.id.isEmpty ? null : _defaultTax.id;
    _status = _defaultStatus;
    _currency = _defaultCurrency;
    _nameError = null;
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
        title: const Text('Add Prod.'),
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
                        register == null ? 'New catalogue product' : 'New catalogue product · ${register.name}',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Creates the parent product only. Use Add Vt\'s. for SKU, barcode, cost, sell price and stock.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      CatalogDefaultsStrip(
                        chips: [
                          CatalogDefaultChip(
                            label: 'Tax ${_selectedTax.percentLabel}',
                            isDefault: _taxIsDefault,
                            onTap: _pickTax,
                          ),
                          CatalogDefaultChip(
                            label: _category.text.trim().isEmpty ? 'Category —' : 'Category ${_category.text.trim()}',
                            isDefault: _categoryIsDefault,
                            onTap: _pickCategory,
                          ),
                          CatalogDefaultChip(
                            label: 'Sold as ${_uom.text.trim().isEmpty ? _defaultUom : _uom.text.trim()}',
                            isDefault: _uomIsDefault,
                            onTap: _pickUom,
                          ),
                          CatalogDefaultChip(
                            label: _statusLabel,
                            isDefault: _statusIsDefault,
                            onTap: _pickStatus,
                          ),
                          CatalogDefaultChip(
                            label: 'Currency $_currency',
                            isDefault: _currencyIsDefault,
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
                      const CatalogSectionTitle(title: 'Identity'),
                      TextFormField(
                        controller: _name,
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          label: catalogRequiredLabel('Product name'),
                          errorText: _nameError,
                          hintText: 'Name on catalogue and receipts',
                        ),
                        onChanged: (_) {
                          if (_nameError != null) setState(() => _nameError = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _sku,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Product SKU',
                          hintText: 'Leave blank to auto-create',
                          helperText: 'Base product code — sellable SKUs live on variants',
                        ),
                      ),
                      const SizedBox(height: 22),
                      const CatalogSectionTitle(title: 'Category & unit'),
                      if (_classificationsHint != null ||
                          _classificationsFromProducts ||
                          (_classifications['category'] ?? const []).isEmpty) ...[
                        CatalogHintBanner(
                          message: _classificationsHint ??
                              (_classificationsFromProducts
                                  ? 'Using categories from products already on this till. An admin can save them in ERP → Catalog → Classifications → Import from products.'
                                  : 'No categories yet. In ERP open Catalog → Classifications, add values or Import from products, then tap Refresh.'),
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
                              title: const Text('Status'),
                              subtitle: Text(_statusLabel),
                              trailing: const Icon(Icons.expand_more),
                              onTap: _pickStatus,
                            ),
                          ),
                        ],
                      ),
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
                        TextFormField(
                          controller: _supplierSku,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Supplier code', hintText: 'Optional'),
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
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _hsCode,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'HS code',
                                  hintText: 'Trade code',
                                  helperText: 'Not a barcode',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _country,
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 2,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Country of origin',
                                  hintText: 'GB',
                                  counterText: '',
                                ),
                              ),
                            ),
                          ],
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
                          'Creating catalogue product…',
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

enum _AfterSave { addAnother, addVariant, backToSell }
