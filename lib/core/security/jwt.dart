import 'dart:convert';

/// Lightweight JWT helpers (no signature verify — server remains source of truth).
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final map = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (map is! Map) return null;
    final exp = map['exp'];
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true).toLocal();
    }
  } catch (_) {}
  return null;
}

/// True when the token has an `exp` claim that is already past (with optional skew).
bool isJwtExpired(String token, {Duration skew = Duration.zero}) {
  final exp = jwtExpiry(token);
  if (exp == null) return false;
  return DateTime.now().isAfter(exp.subtract(skew));
}

bool hasUsableToken(String? token) => token != null && token.trim().isNotEmpty;
