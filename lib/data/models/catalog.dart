import '../../core/utils/money.dart';

class ProductOption {
  const ProductOption(this.name, this.value);
  final String name;
  final String value;

  Map<String, dynamic> toJson() => {'name': name, 'value': value};
  factory ProductOption.fromJson(Map<String, dynamic> j) => ProductOption('${j['name']}', '${j['value']}');
}

/// A sellable variant (the unit the till scans and sells).
class Product {
  const Product({
    required this.variantId,
    required this.catalogItemId,
    required this.sku,
    required this.name,
    this.variantName,
    this.options = const [],
    this.category,
    this.subCategory,
    this.brand,
    this.description,
    required this.pricePence,
    this.promoPricePence,
    this.costPence,
    required this.taxRate,
    this.taxCode,
    this.barcodes = const [],
    this.imageUrl,
    this.stock,
    this.available = true,
    this.active = true,
    this.modifierGroupIds = const [],
    this.updatedAt,
  });

  final String variantId;
  final String catalogItemId;
  final String sku;
  final String name;
  final String? variantName;
  final List<ProductOption> options;
  final String? category;
  final String? subCategory;
  final String? brand;
  final String? description;
  final int pricePence;
  final int? promoPricePence;
  final int? costPence;
  final double taxRate;
  final String? taxCode;
  final List<String> barcodes;
  final String? imageUrl;
  final int? stock;
  final bool available;
  final bool active;
  final List<String> modifierGroupIds;
  final String? updatedAt;

  int get effectivePricePence => promoPricePence ?? pricePence;

  bool get outOfStock => stock != null && stock! <= 0;

  /// Label for the variant part only, e.g. "Red / Large".
  String? get variantLabel {
    if (variantName != null && variantName!.isNotEmpty) return variantName;
    if (options.isEmpty) return null;
    return options.map((o) => o.value).join(' / ');
  }

  String get displayName => variantLabel == null ? name : '$name – $variantLabel';

  Product copyWith({bool? available, int? stock, bool clearStock = false}) => Product(
        variantId: variantId,
        catalogItemId: catalogItemId,
        sku: sku,
        name: name,
        variantName: variantName,
        options: options,
        category: category,
        subCategory: subCategory,
        brand: brand,
        description: description,
        pricePence: pricePence,
        promoPricePence: promoPricePence,
        costPence: costPence,
        taxRate: taxRate,
        taxCode: taxCode,
        barcodes: barcodes,
        imageUrl: imageUrl,
        stock: clearStock ? null : (stock ?? this.stock),
        available: available ?? this.available,
        active: active,
        modifierGroupIds: modifierGroupIds,
        updatedAt: updatedAt,
      );

  /// Parses the `/api/pos/catalog` product shape.
  factory Product.fromApi(Map<String, dynamic> j) => Product(
        variantId: '${j['variantId']}',
        catalogItemId: '${j['catalogItemId']}',
        sku: '${j['sku'] ?? ''}',
        name: '${j['name'] ?? 'Item'}',
        variantName: j['variantName'] as String?,
        options: ((j['options'] as List?) ?? []).map((o) => ProductOption.fromJson(Map<String, dynamic>.from(o as Map))).toList(),
        category: j['category'] as String?,
        subCategory: j['subCategory'] as String?,
        brand: j['brand'] as String?,
        description: j['description'] as String?,
        pricePence: toPence(j['price'] as num?),
        promoPricePence: j['promoPrice'] == null ? null : toPence(j['promoPrice'] as num),
        costPence: j['costPrice'] == null ? null : toPence(j['costPrice'] as num),
        taxRate: () {
          final raw = ((j['taxRate'] as num?) ?? 0.2).toDouble();
          return raw > 1 ? raw / 100 : raw;
        }(),
        taxCode: j['taxCode'] as String?,
        barcodes: ((j['barcodes'] as List?) ?? []).map((e) => '$e').toList(),
        imageUrl: j['imageUrl'] as String?,
        stock: (j['stock'] as num?)?.toInt(),
        available: j['available'] != false,
        active: j['active'] != false,
        modifierGroupIds: ((j['modifierGroupIds'] as List?) ?? []).map((e) => '$e').toList(),
        updatedAt: j['updatedAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'catalogItemId': catalogItemId,
        'sku': sku,
        'name': name,
        'variantName': variantName,
        'options': options.map((o) => o.toJson()).toList(),
        'category': category,
        'subCategory': subCategory,
        'brand': brand,
        'description': description,
        'pricePence': pricePence,
        'promoPricePence': promoPricePence,
        'costPence': costPence,
        'taxRate': taxRate,
        'taxCode': taxCode,
        'barcodes': barcodes,
        'imageUrl': imageUrl,
        'stock': stock,
        'available': available,
        'active': active,
        'modifierGroupIds': modifierGroupIds,
        'updatedAt': updatedAt,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        variantId: '${j['variantId']}',
        catalogItemId: '${j['catalogItemId']}',
        sku: '${j['sku'] ?? ''}',
        name: '${j['name'] ?? 'Item'}',
        variantName: j['variantName'] as String?,
        options: ((j['options'] as List?) ?? []).map((o) => ProductOption.fromJson(Map<String, dynamic>.from(o as Map))).toList(),
        category: j['category'] as String?,
        subCategory: j['subCategory'] as String?,
        brand: j['brand'] as String?,
        description: j['description'] as String?,
        pricePence: (j['pricePence'] as num?)?.toInt() ?? 0,
        promoPricePence: (j['promoPricePence'] as num?)?.toInt(),
        costPence: (j['costPence'] as num?)?.toInt(),
        taxRate: () {
          final raw = ((j['taxRate'] as num?) ?? 0.2).toDouble();
          return raw > 1 ? raw / 100 : raw;
        }(),
        taxCode: j['taxCode'] as String?,
        barcodes: ((j['barcodes'] as List?) ?? []).map((e) => '$e').toList(),
        imageUrl: j['imageUrl'] as String?,
        stock: (j['stock'] as num?)?.toInt(),
        available: j['available'] != false,
        active: j['active'] != false,
        modifierGroupIds: ((j['modifierGroupIds'] as List?) ?? []).map((e) => '$e').toList(),
        updatedAt: j['updatedAt'] as String?,
      );
}

class Modifier {
  const Modifier({required this.id, required this.name, this.priceDeltaPence = 0, this.available = true});
  final String id;
  final String name;
  final int priceDeltaPence;
  final bool available;

  Modifier copyWith({bool? available}) =>
      Modifier(id: id, name: name, priceDeltaPence: priceDeltaPence, available: available ?? this.available);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'priceDeltaPence': priceDeltaPence, 'available': available};

  factory Modifier.fromJson(Map<String, dynamic> j) => Modifier(
        id: '${j['id']}',
        name: '${j['name']}',
        priceDeltaPence: (j['priceDeltaPence'] as num?)?.toInt() ?? toPence(j['priceDelta'] as num?),
        available: j['available'] != false,
      );
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    this.minSelect = 0,
    this.maxSelect = 1,
    this.catalogItemIds = const [],
    this.modifiers = const [],
  });

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<String> catalogItemIds;
  final List<Modifier> modifiers;

  ModifierGroup copyWith({List<Modifier>? modifiers}) => ModifierGroup(
        id: id,
        name: name,
        minSelect: minSelect,
        maxSelect: maxSelect,
        catalogItemIds: catalogItemIds,
        modifiers: modifiers ?? this.modifiers,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minSelect': minSelect,
        'maxSelect': maxSelect,
        'catalogItemIds': catalogItemIds,
        'modifiers': modifiers.map((m) => m.toJson()).toList(),
      };

  factory ModifierGroup.fromJson(Map<String, dynamic> j) => ModifierGroup(
        id: '${j['id']}',
        name: '${j['name']}',
        minSelect: (j['minSelect'] as num?)?.toInt() ?? 0,
        maxSelect: (j['maxSelect'] as num?)?.toInt() ?? 1,
        catalogItemIds: ((j['catalogItemIds'] as List?) ?? []).map((e) => '$e').toList(),
        modifiers: ((j['modifiers'] as List?) ?? []).map((m) => Modifier.fromJson(Map<String, dynamic>.from(m as Map))).toList(),
      );
}
