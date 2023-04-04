import 'dart:convert';

/// Jwt Utilities
class Jwt {
  /// Decode and extract claims from a JWT token.
  static Map<String, dynamic>? decodeClaims(String value) {
    final parts = value.split('.');
    if (parts.length != 3) return null;
    try {
      return _decodePart(parts[1]);
    } catch (_) {}
    return null;
  }
}

Map<String, dynamic> _decodePart(String part) {
  final normalized = base64.normalize(part);
  final base64Decoded = base64.decode(normalized);
  final utf8Decoded = utf8.decode(base64Decoded);
  final jsonDecoded = json.decode(utf8Decoded) as Map<String, dynamic>;
  return jsonDecoded;
}
