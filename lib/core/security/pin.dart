import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/session.dart';
import '../network/api_exception.dart';
import '../storage/local_db.dart';
import '../utils/app_log.dart';

/// Result of a PIN check: the staff member (null = no match) and, when not null, a message to
/// show instead of "PIN not recognised". [staffToken] comes with online checks only.
class PinResult {
  const PinResult(this.staff, {this.message, this.staffToken});
  final StaffMember? staff;
  final String? message;
  final String? staffToken;
}

const _cacheKey = 'pin_cache';
const _iterations = 20000;
const _cacheMaxAge = Duration(days: 30);

/// Overrides are honoured by the API for manager-only actions only shortly after approval.
const overrideTokenLifetime = Duration(minutes: 10);

/// Checks staff PINs. The server keeps the PIN hashes and rate limits attempts; while offline the
/// till falls back to a slow, device-salted cache of PINs that were verified online on this device.
class PinVerifier {
  PinVerifier(this._ref);
  final Ref _ref;

  String? _overrideToken;
  DateTime? _overrideAt;

  /// Token of the manager who approved the latest override, while still fresh.
  String? get overrideToken {
    final at = _overrideAt;
    if (_overrideToken == null || at == null || DateTime.now().difference(at) > overrideTokenLifetime) return null;
    return _overrideToken;
  }

  void rememberOverride(String? token) {
    _overrideToken = token;
    _overrideAt = token == null ? null : DateTime.now();
  }

  /// [among] limits who may match (e.g. managers for an override); [onlyUserId] checks one person's PIN.
  Future<PinResult> verify(String pin, {Iterable<StaffMember>? among, String? onlyUserId}) async {
    final boot = _ref.read(bootstrapProvider);
    final allowed = among?.map((s) => s.id).toSet();
    try {
      final res = Map<String, dynamic>.from(await _ref.read(apiClientProvider).post('/api/pos/staff/verify-pin', data: {
        'pin': pin,
        'userId': ?onlyUserId,
      }) as Map);
      final id = '${res['id']}';
      await _remember(id, pin);
      if (allowed != null && !allowed.contains(id)) return const PinResult(null);
      return PinResult(boot.staffMember(id) ?? StaffMember.fromJson(res), staffToken: res['staffToken'] as String?);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return const PinResult(null);
      if (!e.isNetwork && (e.statusCode ?? 500) < 500) return PinResult(null, message: e.message);
      final id = await _matchOffline(pin);
      if (id == null || (onlyUserId != null && id != onlyUserId) || (allowed != null && !allowed.contains(id))) {
        return const PinResult(null, message: 'Offline: this PIN has not been used on this till yet. Reconnect to check it.');
      }
      final staff = boot.staffMember(id);
      if (staff == null) return const PinResult(null);
      AppLog.info('PIN accepted offline for ${staff.name}');
      return PinResult(staff);
    }
  }

  /// Drops cached PINs of staff who no longer have one (called after the staff list refreshes).
  Future<void> prune(List<StaffMember> staff) async {
    final db = _ref.read(localDbProvider);
    final cache = await db.getKv(_cacheKey);
    if (cache == null || cache['entries'] is! Map) return;
    final keep = staff.where((s) => s.hasPin).map((s) => s.id).toSet();
    cache['entries'] = Map<String, dynamic>.from(cache['entries'] as Map)..removeWhere((k, _) => !keep.contains(k));
    await db.putKv(_cacheKey, cache);
  }

  static String _hash(String salt, String pin) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < _iterations; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Url.encode(bytes);
  }

  Future<Map<String, dynamic>> _loadCache() async {
    final cache = await _ref.read(localDbProvider).getKv(_cacheKey) ?? <String, dynamic>{};
    if (cache['salt'] is! String) {
      final rnd = Random.secure();
      cache['salt'] = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
      cache['entries'] = <String, dynamic>{};
    }
    return cache;
  }

  Future<void> _remember(String userId, String pin) async {
    try {
      final cache = await _loadCache();
      final entries = Map<String, dynamic>.from((cache['entries'] as Map?) ?? {});
      final hash = _hash(cache['salt'] as String, pin);
      // PINs are unique per organisation, so another entry with this hash is stale.
      entries.removeWhere((k, v) => v is Map && v['h'] == hash && k != userId);
      entries[userId] = {'h': hash, 'at': DateTime.now().toIso8601String()};
      cache['entries'] = entries;
      await _ref.read(localDbProvider).putKv(_cacheKey, cache);
    } catch (e) {
      AppLog.warn('Could not cache PIN for offline use: $e');
    }
  }

  Future<String?> _matchOffline(String pin) async {
    final cache = await _loadCache();
    final entries = Map<String, dynamic>.from((cache['entries'] as Map?) ?? {});
    if (entries.isEmpty) return null;
    final hash = _hash(cache['salt'] as String, pin);
    final withPin = _ref.read(bootstrapProvider).staff.where((s) => s.hasPin).map((s) => s.id).toSet();
    for (final e in entries.entries) {
      final v = e.value;
      if (v is! Map || v['h'] != hash) continue;
      final at = DateTime.tryParse('${v['at']}');
      if (at == null || DateTime.now().difference(at) > _cacheMaxAge) continue;
      if (!withPin.contains(e.key)) continue;
      return e.key;
    }
    return null;
  }
}

final pinVerifierProvider = Provider<PinVerifier>(PinVerifier.new);
