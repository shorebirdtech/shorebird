import 'dart:convert';

/// Converts one of the three base64-encoded parts of a JWT to a JSON object.
Map<String, dynamic> decodedJwtPart(String part) {
  final normalized = base64.normalize(part);
  final base64Decoded = base64.decode(normalized);
  final utf8Decoded = utf8.decode(base64Decoded);
  return json.decode(utf8Decoded) as Map<String, dynamic>;
}
