import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [NativePlatform] instance.
ScopedRef<NativePlatform> platformRef = create(_currentPlatform);

/// The [NativePlatform] instance available in the current zone.
///
/// Read this where it is used rather than storing it in a field. Tests swap
/// in a new `TestNativePlatform` instead of mutating one, so an object that
/// captured the platform at construction keeps the old one.
NativePlatform get platform => read(platformRef, orElse: _currentPlatform);

/// The process's [NativePlatform]. shorebird_cli always runs on the Dart VM,
/// so this only throws if it is somehow compiled for the web.
NativePlatform _currentPlatform() =>
    NativePlatform.current ??
    // coverage:ignore-start
    (throw UnsupportedError(
      'shorebird_cli requires a native (dart:io) platform.',
    ));
// coverage:ignore-end
