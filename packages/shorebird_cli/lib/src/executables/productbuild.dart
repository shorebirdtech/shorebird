import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [ProductBuild] instance.
final productBuildRef = create(ProductBuild.new);

/// The [ProductBuild] instance available in the current zone.
ProductBuild get productBuild => read(productBuildRef);

/// {@template productbuild}
/// A wrapper around the `productbuild` command.
/// {@endtemplate}
class ProductBuild {
  /// {@macro productbuild}
  const ProductBuild();

  /// The path to the `productbuild` executable.
  static const executable = 'productbuild';

  /// Creates a signed macOS installer package from component packages.
  Future<ShorebirdProcessResult> build({
    required String packagePath,
    required String outputPath,
    String? sign,
  }) async {
    final args = <String>[
      '--package',
      packagePath,
    ];

    if (sign != null) {
      args.addAll(['--sign', sign]);
    }

    args.add(outputPath);

    return process.run(
      executable,
      args,
      runInShell: true,
    );
  }

  /// Creates a signed macOS installer package from a component.
  Future<ShorebirdProcessResult> buildFromComponent({
    required String componentPath,
    required String installLocation,
    required String outputPath,
    String? sign,
  }) async {
    final args = <String>[
      '--component',
      componentPath,
      installLocation,
    ];

    if (sign != null) {
      args.addAll(['--sign', sign]);
    }

    args.add(outputPath);

    return process.run(
      executable,
      args,
      runInShell: true,
    );
  }
}
