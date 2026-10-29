import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Everything a recorded pass depends on.
///
/// The hashes of [inputs] cover the files the command reads: the whole
/// working tree by default, which includes the command's own script and
/// every lockfile. The rest is what the tree does not record.
class CacheKey {
  /// A key over the given inputs.
  const CacheKey({
    required this.inputs,
    required this.directory,
    required this.command,
    required this.tools,
    required this.platform,
  });

  /// Bumped whenever what a key means changes, so no entry written under an
  /// older meaning is ever read under a newer one.
  static const formatVersion = 2;

  /// The git hash of each input path as the working tree holds it, by path
  /// relative to the checkout root. `.` is the whole working tree.
  final Map<String, String> inputs;

  /// The directory the command runs in, relative to the checkout root.
  final String directory;

  /// The command and its arguments. Arguments are compared as written, so
  /// a path in them should be relative to [directory] for two checkouts to
  /// share a key.
  final List<String> command;

  /// The first line of each tool's `--version`, by tool name.
  final Map<String, String> tools;

  /// The OS and architecture, as [Abi.current] names them.
  final String platform;

  /// The inputs as JSON, in a fixed order so equal inputs encode equally.
  Map<String, Object> toJson() => {
    'format': formatVersion,
    'inputs': {
      for (final path in inputs.keys.toList()..sort()) path: inputs[path]!,
    },
    'directory': directory,
    'command': command,
    'tools': {
      for (final name in tools.keys.toList()..sort()) name: tools[name]!,
    },
    'platform': platform,
  };

  /// The SHA-256 of [toJson], which names this key's entry and lock.
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

/// The platform a key is computed on.
String currentPlatform() => Abi.current().toString();

/// The first line `tool --version` prints, or `absent` when there is no such
/// tool on the PATH.
///
/// Some tools print their version to stderr, so both streams are read.
Future<String> toolVersion(String tool) async {
  final ProcessResult result;
  try {
    result = await Process.run(tool, ['--version']);
  } on ProcessException {
    return 'absent';
  }
  final output = '${result.stdout}${result.stderr}'.trim();
  final firstLine = output.split('\n').first.trim();
  return 'exit ${result.exitCode}: $firstLine';
}
