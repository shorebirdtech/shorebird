import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';

// A reference to a [Platform] instance.
ScopedRef<Platform> platformRef = create(() => const LocalPlatform());

// The [Platform] instance available in the current zone.
Platform get platform => read(platformRef);
