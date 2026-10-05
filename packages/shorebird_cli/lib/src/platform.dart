import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [NativePlatform] instance.
ScopedRef<NativePlatform> platformRef = create(() => NativePlatform.current!);

/// The [NativePlatform] instance available in the current zone.
NativePlatform get platform =>
    read(platformRef, orElse: () => NativePlatform.current!);
