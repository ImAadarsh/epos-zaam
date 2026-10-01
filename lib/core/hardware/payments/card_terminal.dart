import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/settings.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../utils/app_log.dart';

enum CardOutcome { approved, declined, cancelled, needsConfirmation, error }

class CardResult {
  const CardResult(this.outcome, {this.reference, this.cardBrand, this.last4, this.message, this.provider});
  final CardOutcome outcome;
  final String? reference;
  final String? cardBrand;
  final String? last4;
  final String? message;
  final String? provider;

  bool get approved => outcome == CardOutcome.approved;
}

/// Card acceptance behind one interface so new providers (iZettle, Adyen,
/// Paymentsense, Payment Express) only need a new implementation.
abstract class CardTerminal {
  String get name;
  String get providerCode;

  /// True when the cashier must confirm on the till that the separate terminal approved it.
  bool get manualConfirmation => false;

  Future<CardResult> charge({required int amountPence, required String reference, void Function(String status)? onStatus});

  Future<void> cancel() async {}
}

/// Any standalone card machine: the cashier keys the amount into the terminal
/// and confirms the result here.
class ExternalTerminal extends CardTerminal {
  @override
  String get name => 'Card terminal';
  @override
  String get providerCode => 'external';
  @override
  bool get manualConfirmation => true;

  @override
  Future<CardResult> charge({required int amountPence, required String reference, void Function(String status)? onStatus}) async =>
      const CardResult(CardOutcome.needsConfirmation, provider: 'external');
}

/// SumUp Solo via the SumUp Cloud API (reader paired to the merchant account).
/// Docs: https://developer.sumup.com/terminal-payments/cloud-api
class SumUpSoloTerminal extends CardTerminal {
  SumUpSoloTerminal({required this.apiKey, required this.merchantCode, required this.readerId})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.sumup.com',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
        ));

  final String apiKey;
  final String merchantCode;
  final String readerId;
  final Dio _dio;
  bool _cancelled = false;

  @override
  String get name => 'SumUp Solo';
  @override
  String get providerCode => 'sumup';

  @override
  Future<CardResult> charge({required int amountPence, required String reference, void Function(String status)? onStatus}) async {
    if (apiKey.isEmpty || merchantCode.isEmpty || readerId.isEmpty) {
      return const CardResult(CardOutcome.error, message: 'Add the SumUp API key, merchant code and reader ID in Settings → Payment.', provider: 'sumup');
    }
    _cancelled = false;
    try {
      onStatus?.call('Sending £${(amountPence / 100).toStringAsFixed(2)} to the SumUp reader…');
      final res = await _dio.post('/v0.1/merchants/$merchantCode/readers/$readerId/checkout', data: {
        'total_amount': {'value': amountPence, 'currency': 'GBP', 'minor_unit': 2},
        'description': reference,
      });
      final txId = (res.data is Map ? (res.data['data']?['client_transaction_id']) : null)?.toString();
      if (txId == null) return const CardResult(CardOutcome.error, message: 'SumUp did not return a transaction id.', provider: 'sumup');
      onStatus?.call('Present card on the reader…');
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (_cancelled) return const CardResult(CardOutcome.cancelled, provider: 'sumup');
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          final t = await _dio.get('/v0.1/me/transactions', queryParameters: {'client_transaction_id': txId});
          final data = t.data is Map ? Map<String, dynamic>.from(t.data as Map) : <String, dynamic>{};
          final status = '${data['status'] ?? data['simple_status'] ?? ''}'.toUpperCase();
          if (status == 'SUCCESSFUL' || status == 'PAID') {
            final card = data['card'] is Map ? Map<String, dynamic>.from(data['card'] as Map) : const <String, dynamic>{};
            return CardResult(CardOutcome.approved,
                reference: '${data['transaction_code'] ?? txId}',
                cardBrand: card['type']?.toString(),
                last4: card['last_4_digits']?.toString(),
                provider: 'sumup');
          }
          if (status == 'FAILED' || status == 'CANCELLED' || status == 'CANCEL_FAILED') {
            return CardResult(status == 'CANCELLED' ? CardOutcome.cancelled : CardOutcome.declined, message: 'SumUp: $status', provider: 'sumup');
          }
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
        }
      }
      return const CardResult(CardOutcome.error, message: 'Timed out waiting for the SumUp reader. Check the reader before retrying.', provider: 'sumup');
    } on DioException catch (e) {
      AppLog.error('SumUp checkout failed', e.message);
      final msg = e.response?.data is Map ? '${(e.response!.data as Map)['message'] ?? (e.response!.data as Map)['detail'] ?? e.message}' : e.message;
      return CardResult(CardOutcome.error, message: 'SumUp error: $msg', provider: 'sumup');
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _dio.post('/v0.1/merchants/$merchantCode/readers/$readerId/terminate');
    } catch (_) {}
  }
}

/// SumUp Air/Solo over Bluetooth needs SumUp's native iOS/Android SDK, which
/// requires an affiliate key and a platform channel. Not bundled yet.
class SumUpBluetoothTerminal extends CardTerminal {
  @override
  String get name => 'SumUp Bluetooth';
  @override
  String get providerCode => 'sumup_bt';

  @override
  Future<CardResult> charge({required int amountPence, required String reference, void Function(String status)? onStatus}) async => const CardResult(
        CardOutcome.error,
        message: 'SumUp Bluetooth needs the native SumUp SDK (affiliate key) which is not bundled yet. Use SumUp Solo (Cloud API) or a standalone terminal.',
        provider: 'sumup_bt',
      );
}

final cardTerminalProvider = Provider<CardTerminal>((ref) {
  final s = ref.watch(settingsProvider);
  return switch (s.cardProvider) {
    CardProviderType.external => ExternalTerminal(),
    CardProviderType.sumupSolo => SumUpSoloTerminal(apiKey: s.sumupApiKey, merchantCode: s.sumupMerchantCode, readerId: s.sumupReaderId),
    CardProviderType.sumupBluetooth => SumUpBluetoothTerminal(),
  };
});
