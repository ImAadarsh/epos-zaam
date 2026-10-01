import 'package:intl/intl.dart';

/// All money in the app is held as integer pence to avoid float drift.
final NumberFormat _gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);

String formatPence(int pence) => _gbp.format(pence / 100);

String formatPenceSigned(int pence) => pence < 0 ? '-${formatPence(-pence)}' : formatPence(pence);

int toPence(num? value) => value == null ? 0 : (value * 100).round();

double fromPence(int pence) => pence / 100;

/// Parses user input such as "12", "12.5", "£12.50" into pence.
int? parsePence(String input) {
  final cleaned = input.replaceAll(RegExp(r'[£,\s]'), '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null) return null;
  return (value * 100).round();
}
