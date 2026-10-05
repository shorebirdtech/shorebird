import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [NativePlatform] instance.
ScopedRef<NativePlatform> platformRef = create(() => NativePlatform.current!);

/// The [NativePlatform] instance available in the current zone.
///
/// Read this where it is used rather than storing it in a field. Tests swap
/// in a new `TestNativePlatform` instead of mutating one, so an object that
/// captured the platform at construction keeps the old one.
NativePlatform get platform =>
    read(platformRef, orElse: () => NativePlatform.current!);
