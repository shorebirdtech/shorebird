import 'dart:io';

/// Builds `library_test_hooks` and returns the absolute path to the
/// resulting cdylib artifact.
///
/// Throws on any failure (cargo missing, build error, artifact not found).
/// The test entry point catches and translates these into a
/// `markTestSkipped`, so this layer can stay simple.
Future<String> buildTestHooksCdylib() async {
  final workspaceRoot = _resolveWorkspaceRoot();

  final result = await Process.run(
    'cargo',
    const ['build', '-p', 'library_test_hooks'],
    workingDirectory: workspaceRoot,
  );

  if (result.exitCode != 0) {
    throw Exception(
      'cargo build -p library_test_hooks failed (exit ${result.exitCode}):\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }

  final artifact = File(
    '$workspaceRoot/target/debug/${_artifactName('updater_test_hooks')}',
  );
  if (!artifact.existsSync()) {
    throw Exception(
      'cargo build succeeded but artifact not found at ${artifact.path}',
    );
  }
  return artifact.path;
}

/// Resolves the Cargo workspace root from the test process's cwd.
///
/// `dart test` runs with cwd = the package root (`shorebird_code_push/`),
/// so the workspace root is one level up.
String _resolveWorkspaceRoot() => Directory.current.parent.path;

String _artifactName(String libName) {
  if (Platform.isMacOS) return 'lib$libName.dylib';
  if (Platform.isLinux) return 'lib$libName.so';
  if (Platform.isWindows) return '$libName.dll';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
