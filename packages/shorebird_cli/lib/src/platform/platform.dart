export 'android.dart';
export 'ios.dart';

/// {@template arch}
/// Build architectures supported by Shorebird.
///
/// Note: in addition to these values, the Flutter tooling also supports x86.
/// {@endtemplate}
enum Arch {
  arm32(arch: 'arm'),
  arm64(arch: 'aarch64'),
  x86_64(arch: 'x86_64');

  /// {@macro arch}
  const Arch({required this.arch});

  /// The name used by Shorebird to identify this architecture.
  final String arch;
}
