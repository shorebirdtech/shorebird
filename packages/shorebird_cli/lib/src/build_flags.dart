import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// The flags a release was built with that change its compiled Dart code and
/// aren't otherwise carried over to its patches, recorded in the release
/// supplement as [fileName] so `shorebird patch` can check that a patch is
/// built the same way (shorebirdtech/shorebird#3700).
///
/// Holds SHA-256 hashes, never dart-define values (often API keys) or the
/// entrypoint path, so the record shows which flag differs without holding
/// what it was.
class BuildFlags {
  /// Creates [BuildFlags] from hashes.
  const BuildFlags({required this.dartDefines, this.target});

  /// Hashes the dart-defines and target of [results], resolving
  /// `--dart-define-from-file` the way Flutter does. [target] is the
  /// entrypoint the build uses, null for the default; relative paths are
  /// taken from the current directory, the project root.
  ///
  /// Throws a [FormatException] if a define file can't be read.
  factory BuildFlags.fromArgs(ArgResults results, {required String? target}) {
    final defines = <String, String>{
      for (final path in _optionValues(
        results,
        CommonArguments.dartDefineFromFileArg.name,
      ))
        ...readDartDefinesFile(File(path)),
    };
    for (final define in _optionValues(
      results,
      CommonArguments.dartDefineArg.name,
    )) {
      if (define.isEmpty) continue;
      final separator = define.indexOf('=');
      if (separator == -1) {
        defines[define] = '';
      } else {
        defines[define.substring(0, separator)] = define.substring(
          separator + 1,
        );
      }
    }
    return BuildFlags(
      dartDefines: {
        for (final MapEntry(:key, :value) in defines.entries) key: _hash(value),
      },
      target: switch (_relativeTarget(target)) {
        final relative? => _hash(relative),
        null => null,
      },
    );
  }

  /// Reads [BuildFlags] from the JSON [toJson] wrote.
  factory BuildFlags.fromJson(Map<String, dynamic> json) => BuildFlags(
    dartDefines: (json['dart_defines'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    ),
    target: json['target'] as String?,
  );

  /// The name of the file in the release supplement.
  static const fileName = 'build_flags.json';

  /// Each dart-define key with the hex SHA-256 of its value.
  final Map<String, String> dartDefines;

  /// The hex SHA-256 of the entrypoint path relative to the project root,
  /// null for Flutter's default `lib/main.dart`.
  final String? target;

  /// This as JSON.
  Map<String, dynamic> toJson() => {
    'dart_defines': dartDefines,
    'target': ?target,
  };

  /// How a patch built with these flags differs from [release], one line
  /// each, naming keys but never values. Empty when they match.
  List<String> differencesFrom(BuildFlags release) {
    final keys = {...release.dartDefines.keys, ...dartDefines.keys}.toList()
      ..sort();
    String list(bool Function(String key) test) => keys.where(test).join(', ');
    final missing = list(
      (key) =>
          release.dartDefines.containsKey(key) && !dartDefines.containsKey(key),
    );
    final extra = list(
      (key) =>
          !release.dartDefines.containsKey(key) && dartDefines.containsKey(key),
    );
    final changed = list(
      (key) =>
          release.dartDefines.containsKey(key) &&
          dartDefines.containsKey(key) &&
          release.dartDefines[key] != dartDefines[key],
    );
    return [
      if (missing.isNotEmpty) '--dart-define missing: $missing',
      if (extra.isNotEmpty) '--dart-define not in the release: $extra',
      if (changed.isNotEmpty) '--dart-define with a different value: $changed',
      if (release.target != target) '--target differs from the release',
    ];
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// [target] relative to the current directory with `/` separators, or
  /// null for Flutter's default entrypoint.
  static String? _relativeTarget(String? target) {
    if (target == null) return null;
    final relative = p.posix.joinAll(
      p.split(p.normalize(p.relative(target))),
    );
    return relative == 'lib/main.dart' ? null : relative;
  }

  /// Every value of the multi-option [name], whether parsed or passed after
  /// `--` as `--name=value` or `--name value`.
  static List<String> _optionValues(ArgResults results, String name) {
    final values = <String>[
      if (results.wasParsed(name)) ...results[name] as List<String>,
    ];
    final rest = results.rest;
    for (var i = 0; i < rest.length; i++) {
      if (rest[i] == '--$name' && i + 1 < rest.length) {
        values.add(rest[++i]);
      } else if (rest[i].startsWith('--$name=')) {
        values.add(rest[i].substring('--$name='.length));
      }
    }
    return values;
  }
}
