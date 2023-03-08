import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import 'src/bindings.dart';

class Updater {
  Updater();

  static UpdaterBindings? _bindings;

  static ffi.DynamicLibrary _loadLibraryInDirectory(
      {required String directory, required String name}) {
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open(path.join(directory, 'lib$name.dylib'));
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open(path.join(directory, '$name.dll'));
    }
    // Assume everything else follows the Linux pattern.
    return ffi.DynamicLibrary.open(path.join(directory, 'lib$name.so'));
  }

  static loadLibrary({required String name, required String directory}) {
    if (_bindings != null) {
      throw Exception('Library already loaded.');
    }
    final updater = _loadLibraryInDirectory(directory: directory, name: name);
    _bindings = UpdaterBindings(updater);
  }

  static loadFlutterLibrary() {
    if (_bindings != null) {
      throw Exception('Library already loaded.');
    }
    final updater = ffi.DynamicLibrary.process();
    _bindings = UpdaterBindings(updater);
  }

  static UpdaterBindings get bindings {
    if (_bindings == null) {
      throw Exception('Must call loadLibrary() first.');
    }
    return _bindings!;
  }

  // This is only used when called from a Dart command line.
  // Shorebird will have initialized the library already for you when
  // inside a Flutter app.
  static void initUpdaterLibrary({
    required String clientId,
    required String productId,
    required String version,
    required String channel,
    required String? updateUrl,
    required String baseLibraryPath,
    required String vmPath,
    required String cacheDir,
  }) {
    var config = AppParameters.allocate(
      productId: productId,
      version: version,
      channel: channel,
      updateUrl: updateUrl,
      libappPath: baseLibraryPath,
      libflutterPath: vmPath,
      clientId: clientId,
      cacheDir: cacheDir,
    );
    try {
      bindings.init(config);
    } finally {
      AppParameters.free(config);
    }
  }

  bool checkForUpdate() {
    return bindings.checkForUpdate();
  }

  void update() {
    return bindings.update();
  }

  String? _returnsMaybeString(ffi.Pointer<Utf8> Function() f) {
    ffi.Pointer<Utf8> cString = ffi.Pointer<Utf8>.fromAddress(0);
    cString = f();
    if (cString.address == 0) {
      return null;
    }
    try {
      return cString.toDartString();
    } finally {
      // Using finally for two reasons:
      // 1. it runs after the return (saving us a local)
      // 2. it runs even if toDartString throws (which it shouldn't)
      bindings.freeString(cString);
    }
  }

  String? activeVersion() {
    return _returnsMaybeString(bindings.activeVersion);
  }

  String? activePath() {
    return _returnsMaybeString(bindings.activePath);
  }
}
