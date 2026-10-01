import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/models/org.dart';

/// Same scheme as the server (`sha256("salt:pin")`, hex) so PINs verify offline.
String hashPin(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

StaffMember? matchPin(Iterable<StaffMember> staff, String pin, {String? onlyUserId}) {
  for (final s in staff) {
    if (onlyUserId != null && s.id != onlyUserId) continue;
    if (s.pinSalt == null || s.pinHash == null) continue;
    if (hashPin(s.pinSalt!, pin) == s.pinHash) return s;
  }
  return null;
}
