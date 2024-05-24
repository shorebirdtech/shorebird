import 'dart:io';

import 'package:shorebird_cli/src/code_signer.dart';

extension NullOrEmtpy on String? {
  /// Returns `true` if this string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

extension SignString on (String, File?) {
  String? get signature {
    final privateKeyFile = this.$2;

    return privateKeyFile != null
        ? codeSigner.sign(
            message: this.$1,
            privateKeyPemFile: privateKeyFile,
          )
        : null;
  }
}
