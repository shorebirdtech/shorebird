import 'dart:ffi';

import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [Abi] instance.
ScopedRef<LocalAbi> abiRef = create(() => const LocalAbi());

/// The [Abi] instance available in the current zone.
LocalAbi get abi => read(abiRef, orElse: () => const LocalAbi());

/// {@template abi}
/// A mockable wrapper around [Abi] from dart:ffi.
/// {@endtemplate}
class LocalAbi {
  /// {@macro abi}
  const LocalAbi();

  /// The current ABI.
  Abi get current => Abi.current();
}
