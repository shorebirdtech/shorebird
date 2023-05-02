import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/command.dart';

mixin ShorebirdFlavorMixin on ShorebirdCommand {
  Future<Set<String>> extractProductFlavors(
    String path, {
    Platform platform = const LocalPlatform(),
  }) async {
    final executable = platform.isWindows ? 'gradlew.bat' : 'gradlew';
    final result = await process.run(
      p.join(path, 'android', executable),
      ['app:tasks', '--all', '--console=auto'],
      runInShell: true,
      workingDirectory: p.join(path, 'android'),
    );

    if (result.exitCode != 0) throw Exception('${result.stderr}');

    final variants = <String>{};
    final assembleTaskPattern = RegExp(r'assemble(\S+)');
    for (final task in '${result.stdout}'.split('\n')) {
      final match = assembleTaskPattern.matchAsPrefix(task);
      if (match != null) {
        final variant = match.group(1)!.toLowerCase();
        if (!variant.endsWith('test')) {
          variants.add(variant);
        }
      }
    }

    final productFlavors = <String>{};
    for (final variant1 in variants) {
      for (final variant2 in variants) {
        if (variant2.startsWith(variant1) && variant2 != variant1) {
          final buildType = variant2.substring(variant1.length);
          if (variants.contains(buildType)) {
            productFlavors.add(variant1);
          }
        }
      }
    }
    return productFlavors;
  }
}
