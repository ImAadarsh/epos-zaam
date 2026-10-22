import 'package:collection/collection.dart';

class OrgInfo {
  const OrgInfo({required this.name, this.legalName, this.vatNumber, this.phone, this.email, this.website, this.logoUrl, this.address});

  final String name;
  final String? legalName;
  final String? vatNumber;
  final String? phone;
  final String? email;
  final String? website;
  final String? logoUrl;
  final String? address;

  factory OrgInfo.fromJson(Map<String, dynamic> j) => OrgInfo(
        name: '${j['name'] ?? 'Zaam'}',
        legalName: j['legalName'] as String?,
        vatNumber: j['vatNumber'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        website: j['website'] as String?,
        logoUrl: j['logoUrl'] as String?,
        address: j['address'] as String?,
      );

  OrgInfo withAddress(String? value) => OrgInfo(
        name: name,
        legalName: legalName,
        vatNumber: vatNumber,
        phone: phone,
        email: email,
        website: website,
        logoUrl: logoUrl,
        address: value,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'legalName': legalName,
        'vatNumber': vatNumber,
        'phone': phone,
        'email': email,
        'website': website,
        'logoUrl': logoUrl,
        'address': address,
      };
}

class Register {
  const Register({
    required this.id,
    required this.name,
    required this.code,
    this.warehouseId,
    this.warehouseName,
    this.warehouseAddress,
    this.receiptPrefix,
    this.settings = const {},
  });

  final String id;
  final String name;
  final String code;
  final String? warehouseId;
  final String? warehouseName;

  /// Address of the stock location; printed on this register's receipts.
  final String? warehouseAddress;
  final String? receiptPrefix;
  final Map<String, dynamic> settings;

  factory Register.fromJson(Map<String, dynamic> j) => Register(
        id: '${j['id']}',
        name: '${j['name']}',
        code: '${j['code'] ?? 'REG'}',
        warehouseId: j['warehouseId']?.toString(),
        warehouseName: j['warehouseName'] as String?,
        warehouseAddress: j['warehouseAddress'] as String?,
        receiptPrefix: j['receiptPrefix'] as String?,
        settings: j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'warehouseId': warehouseId,
        'warehouseName': warehouseName,
        'warehouseAddress': warehouseAddress,
        'receiptPrefix': receiptPrefix,
        'settings': settings,
      };
}

/// A stock location a register can sell from.
class WarehouseInfo {
  const WarehouseInfo({required this.id, required this.name, this.code, this.address});
  final String id;
  final String name;
  final String? code;
  final String? address;

  factory WarehouseInfo.fromJson(Map<String, dynamic> j) =>
      WarehouseInfo(id: '${j['id']}', name: '${j['name']}', code: j['code'] as String?, address: j['address'] as String?);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'address': address};
}

enum PosRole { cashier, supervisor, manager }

PosRole posRoleFrom(String? v) => PosRole.values.firstWhere((r) => r.name == v, orElse: () => PosRole.cashier);

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    this.email,
    this.roles = const [],
    this.posRole = PosRole.cashier,
    this.hasPin = false,
  });

  final String id;
  final String name;
  final String? email;
  final List<String> roles;
  final PosRole posRole;
  final bool hasPin;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: '${j['id']}',
        name: '${j['name'] ?? j['email'] ?? 'Staff'}',
        email: j['email'] as String?,
        roles: ((j['roles'] as List?) ?? []).map((e) => '$e').toList(),
        posRole: posRoleFrom(j['posRole'] as String?),
        hasPin: j['hasPin'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'roles': roles,
        'posRole': posRole.name,
        'hasPin': hasPin,
      };
}

/// Accepts a fraction (`0.2`) or a percent (`20`) and returns a fraction.
double normalizeVatRate(double rate) {
  if (rate > 1) return rate / 100;
  return rate;
}

/// Formats a VAT fraction (0.2) as a percent label (`20%`).
String formatVatPercent(double rate) {
  final p = normalizeVatRate(rate) * 100;
  if ((p - p.round()).abs() < 0.051) return '${p.round()}%';
  return '${p.toStringAsFixed(1)}%';
}

/// Organisation default VAT, else the 20% code, else a synthetic UK 20% rate.
TaxCodeInfo pickOrgOrUkVat(List<TaxCodeInfo> codes) {
  for (final c in codes) {
    if (c.isDefault) return c;
  }
  for (final c in codes) {
    if ((c.rate - 0.2).abs() < 0.0005) return c;
  }
  return const TaxCodeInfo(id: '', code: 'VAT20', name: 'VAT 20%', rate: 0.2, isDefault: true);
}

class DiscountPreset {
  const DiscountPreset({required this.id, required this.name, required this.type, required this.value});
  final String id;
  final String name;
  /// `percent` or `amount` (pounds).
  final String type;
  final double value;
  bool get isAmount => type == 'amount';
  factory DiscountPreset.fromJson(Map<String, dynamic> j) => DiscountPreset(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        type: '${j['type']}' == 'amount' ? 'amount' : 'percent',
        value: (j['value'] is num ? j['value'] as num : num.tryParse('${j['value'] ?? 0}') ?? 0).toDouble(),
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'value': value};
}

class TaxCodeInfo {
  const TaxCodeInfo({required this.id, required this.code, required this.name, required this.rate, this.isDefault = false});
  final String id;
  final String code;
  final String name;

  /// Fraction, e.g. `0.2` for 20%.
  final double rate;
  final bool isDefault;

  String get percentLabel => formatVatPercent(rate);

  factory TaxCodeInfo.fromJson(Map<String, dynamic> j) => TaxCodeInfo(
        id: '${j['id']}',
        code: '${j['code']}',
        name: '${j['name']}',
        rate: normalizeVatRate((j['rate'] is num ? j['rate'] as num : num.tryParse('${j['rate'] ?? 0}') ?? 0).toDouble()),
        isDefault: j['isDefault'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name, 'rate': rate, 'isDefault': isDefault};
}

/// Everything returned by `GET /api/pos/bootstrap`, cached for offline starts.
class BootstrapData {
  const BootstrapData({this.org, this.registers = const [], this.warehouses = const [], this.staff = const [], this.taxCodes = const [], this.discountPresets = const [], this.currency = 'GBP'});

  final OrgInfo? org;
  final List<Register> registers;
  final List<WarehouseInfo> warehouses;
  final List<StaffMember> staff;
  final List<TaxCodeInfo> taxCodes;
  final List<DiscountPreset> discountPresets;
  final String currency;

  Register? register(String? id) => registers.firstWhereOrNull((r) => r.id == id);
  StaffMember? staffMember(String? id) => staff.firstWhereOrNull((s) => s.id == id);

  factory BootstrapData.fromJson(Map<String, dynamic> j) => BootstrapData(
        org: j['organization'] is Map ? OrgInfo.fromJson(Map<String, dynamic>.from(j['organization'] as Map)) : null,
        registers: ((j['registers'] as List?) ?? []).map((e) => Register.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        warehouses: ((j['warehouses'] as List?) ?? []).map((e) => WarehouseInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        staff: ((j['staff'] as List?) ?? []).map((e) => StaffMember.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        taxCodes: ((j['taxCodes'] as List?) ?? []).map((e) => TaxCodeInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        discountPresets: ((j['discountPresets'] as List?) ?? []).map((e) => DiscountPreset.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        currency: '${j['currency'] ?? 'GBP'}',
      );

  Map<String, dynamic> toJson() => {
        'organization': org?.toJson(),
        'registers': registers.map((r) => r.toJson()).toList(),
        'warehouses': warehouses.map((w) => w.toJson()).toList(),
        'staff': staff.map((s) => s.toJson()).toList(),
        'taxCodes': taxCodes.map((t) => t.toJson()).toList(),
        'discountPresets': discountPresets.map((t) => t.toJson()).toList(),
        'currency': currency,
      };
}
