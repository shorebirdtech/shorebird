// This eventually moves to its own package.
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'bindings.dart';

class Updater {
  final String clientId;
  final String cacheDir;

  Updater(this.clientId, this.cacheDir);

  static UpdaterBindings? _bindings;

  static loadLibrary() {
    if (_bindings != null) {
      throw Exception('Library already loaded.');
    }
    _bindings = UpdaterBindings();
  }

  static UpdaterBindings get bindings {
    if (_bindings == null) {
      throw Exception('Must call loadLibrary() first.');
    }
    return _bindings!;
  }

  // Currently bindings passes context as two separate char*, if it ever
  // uses a struct instead at least we only have one place to change.
  T _callWithContext<T>(
      T Function(ffi.Pointer<Utf8> clientId, ffi.Pointer<Utf8> cacheDir) f) {
    // Will this leak if the second toNativeUtf8 throws an exception?
    var clientId = this.clientId.toNativeUtf8();
    var cacheDir = this.cacheDir.toNativeUtf8();
    try {
      return f(clientId, cacheDir);
    } finally {
      calloc.free(clientId);
      calloc.free(cacheDir);
    }
  }

  bool checkForUpdate() {
    return _callWithContext(bindings.checkForUpdate);
  }

  void update() {
    return _callWithContext(bindings.update);
  }

  String? activeVersion() {
    return _callWithContext((clientId, cacheDir) {
      ffi.Pointer<Utf8> cVersion = ffi.Pointer<Utf8>.fromAddress(0);
      try {
        cVersion = bindings.activeVersion(clientId, cacheDir);
        if (cVersion.address == 0) {
          return null;
        }
        return cVersion.toDartString();
      } finally {
        // Can toDartString ever throw an exception, such that this finally
        // block is necessary?
        bindings.freeString(cVersion);
      }
    });
  }

  String? activePath() {
    return _callWithContext((clientId, cacheDir) {
      ffi.Pointer<Utf8> cVersion = ffi.Pointer<Utf8>.fromAddress(0);
      try {
        cVersion = bindings.activePath(clientId, cacheDir);
        if (cVersion.address == 0) {
          return null;
        }
        return cVersion.toDartString();
      } finally {
        // Can toDartString ever throw an exception, such that this finally
        // block is necessary?
        bindings.freeString(cVersion);
      }
    });
  }
}
