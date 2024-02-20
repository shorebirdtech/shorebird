import 'dart:convert';

/// Converts one of the three base64-encoded parts of a JWT to a JSON object.
Map<String, dynamic> jwtPartToJson(String part) {
  final normalized = base64.normalize(part);
  final base64Decoded = base64.decode(normalized);
  final utf8Decoded = utf8.decode(base64Decoded);
  final jsonDecoded = json.decode(utf8Decoded) as Map<String, dynamic>;
  return jsonDecoded;
}

String base64Padded(String value) {
  final mod = value.length % 4;
  if (mod == 0) {
    return value;
  } else if (mod == 3) {
    return value.padRight(value.length + 1, '=');
  } else if (mod == 2) {
    return value.padRight(value.length + 2, '=');
  } else {
    return value; // let it fail when decoding
  }
}
