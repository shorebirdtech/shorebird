import 'package:shorebird_cli/src/archive_analysis/dex_parser.dart';

/// The kind of difference found between two DEX files.
enum DexDifferenceKind {
  /// Source file attribute changed (safe — build path difference).
  sourceFileChanged,

  /// A class was added.
  classAdded,

  /// A class was removed.
  classRemoved,

  /// A method was added to a class.
  methodAdded,

  /// A method was removed from a class.
  methodRemoved,

  /// A field was added to a class.
  fieldAdded,

  /// A field was removed from a class.
  fieldRemoved,

  /// Access flags changed on a class, method, or field.
  accessFlagsChanged,

  /// The superclass of a class changed.
  superclassChanged,

  /// The interface list of a class changed.
  interfacesChanged;

  /// Whether this kind of difference is safe (does not affect runtime
  /// behavior).
  bool get isSafe => this == sourceFileChanged;
}

/// {@template dex_difference}
/// A single difference found between two DEX files.
/// {@endtemplate}
class DexDifference {
  /// {@macro dex_difference}
  const DexDifference({required this.kind, required this.description});

  /// The classification of this difference.
  final DexDifferenceKind kind;

  /// A human-readable description of the difference.
  final String description;
}

/// {@template dex_diff_result}
/// The result of comparing two DEX files.
/// {@endtemplate}
class DexDiffResult {
  /// {@macro dex_diff_result}
  const DexDiffResult({required this.differences});

  /// Creates an empty (identical) diff result.
  const DexDiffResult.identical() : differences = const [];

  /// All differences found between the two DEX files.
  final List<DexDifference> differences;

  /// Differences that are safe to ignore (e.g. source file paths).
  Iterable<DexDifference> get safeDifferences =>
      differences.where((d) => d.kind.isSafe);

  /// Differences that indicate real code changes.
  Iterable<DexDifference> get breakingDifferences =>
      differences.where((d) => !d.kind.isSafe);

  /// Whether all differences are safe to ignore.
  bool get isSafe => breakingDifferences.isEmpty;

  /// A human-readable summary of the differences.
  String describe() {
    final buffer = StringBuffer();
    final safe = safeDifferences.toList();
    final breaking = breakingDifferences.toList();

    if (safe.isNotEmpty) {
      buffer.writeln(
        'Safe differences (${safe.length}):',
      );
      for (final diff in safe) {
        buffer.writeln('  - ${diff.description}');
      }
    }

    if (breaking.isNotEmpty) {
      buffer.writeln(
        'Breaking differences (${breaking.length}):',
      );
      for (final diff in breaking) {
        buffer.writeln('  - ${diff.description}');
      }
    }

    return buffer.toString().trimRight();
  }
}

/// {@template dex_differ}
/// Compares two parsed [DexFile]s and produces a [DexDiffResult] describing
/// the semantic differences between them.
/// {@endtemplate}
class DexDiffer {
  /// {@macro dex_differ}
  const DexDiffer();

  /// Compares two DEX files and returns the differences.
  DexDiffResult diff(DexFile oldFile, DexFile newFile) {
    final differences = <DexDifference>[];

    // Build class maps keyed by type descriptor.
    final oldClasses = {
      for (final c in oldFile.classDefs) c.className: c,
    };
    final newClasses = {
      for (final c in newFile.classDefs) c.className: c,
    };

    final oldClassNames = oldClasses.keys.toSet();
    final newClassNames = newClasses.keys.toSet();

    // Detect added/removed classes.
    for (final added in newClassNames.difference(oldClassNames)) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.classAdded,
          description: 'Class added: $added',
        ),
      );
    }

    for (final removed in oldClassNames.difference(newClassNames)) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.classRemoved,
          description: 'Class removed: $removed',
        ),
      );
    }

    // Compare matched classes.
    for (final name in oldClassNames.intersection(newClassNames)) {
      _compareClasses(oldClasses[name]!, newClasses[name]!, differences);
    }

    return DexDiffResult(differences: differences);
  }

  void _compareClasses(
    DexClassDef oldClass,
    DexClassDef newClass,
    List<DexDifference> differences,
  ) {
    final name = oldClass.className;

    if (oldClass.sourceFile != newClass.sourceFile) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.sourceFileChanged,
          description:
              '$name: source file changed from '
              '"${oldClass.sourceFile}" to "${newClass.sourceFile}"',
        ),
      );
    }

    if (oldClass.accessFlags != newClass.accessFlags) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.accessFlagsChanged,
          description:
              '$name: class access flags changed from '
              '0x${oldClass.accessFlags.toRadixString(16)} to '
              '0x${newClass.accessFlags.toRadixString(16)}',
        ),
      );
    }

    if (oldClass.superclass != newClass.superclass) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.superclassChanged,
          description:
              '$name: superclass changed from '
              '${oldClass.superclass} to ${newClass.superclass}',
        ),
      );
    }

    if (!_listEquals(oldClass.interfaces, newClass.interfaces)) {
      differences.add(
        DexDifference(
          kind: DexDifferenceKind.interfacesChanged,
          description: '$name: interfaces changed',
        ),
      );
    }

    _compareMembers(
      className: name,
      oldData: oldClass.classData,
      newData: newClass.classData,
      extract: (data) => {
        for (final f in [...data.staticFields, ...data.instanceFields])
          '${f.field.className}.${f.field.fieldName}:${f.field.typeName}':
              f.accessFlags,
      },
      memberLabel: 'field',
      addedKind: DexDifferenceKind.fieldAdded,
      removedKind: DexDifferenceKind.fieldRemoved,
      differences: differences,
    );

    _compareMembers(
      className: name,
      oldData: oldClass.classData,
      newData: newClass.classData,
      extract: (data) => {
        for (final m in [...data.directMethods, ...data.virtualMethods])
          _methodKey(m): m.accessFlags,
      },
      memberLabel: 'method',
      addedKind: DexDifferenceKind.methodAdded,
      removedKind: DexDifferenceKind.methodRemoved,
      differences: differences,
    );
  }

  /// Compares members (fields or methods) between two class data items.
  ///
  /// [extract] converts a [DexClassData] into a map of member key to access
  /// flags. The key is a human-readable descriptor used in diff descriptions.
  void _compareMembers({
    required String className,
    required DexClassData? oldData,
    required DexClassData? newData,
    required Map<String, int> Function(DexClassData) extract,
    required String memberLabel,
    required DexDifferenceKind addedKind,
    required DexDifferenceKind removedKind,
    required List<DexDifference> differences,
  }) {
    final oldMembers = oldData != null ? extract(oldData) : <String, int>{};
    final newMembers = newData != null ? extract(newData) : <String, int>{};

    final oldKeys = oldMembers.keys.toSet();
    final newKeys = newMembers.keys.toSet();

    for (final added in newKeys.difference(oldKeys)) {
      differences.add(
        DexDifference(
          kind: addedKind,
          description: '$className: $memberLabel added: $added',
        ),
      );
    }

    for (final removed in oldKeys.difference(newKeys)) {
      differences.add(
        DexDifference(
          kind: removedKind,
          description: '$className: $memberLabel removed: $removed',
        ),
      );
    }

    for (final common in oldKeys.intersection(newKeys)) {
      if (oldMembers[common] != newMembers[common]) {
        differences.add(
          DexDifference(
            kind: DexDifferenceKind.accessFlagsChanged,
            description:
                '$className: $memberLabel $common access flags changed '
                'from 0x${oldMembers[common]!.toRadixString(16)} '
                'to 0x${newMembers[common]!.toRadixString(16)}',
          ),
        );
      }
    }
  }

  static String _methodKey(DexEncodedMethod m) {
    final params = m.method.proto.parameterTypes.join(', ');
    return '${m.method.className}.${m.method.methodName}'
        '($params)${m.method.proto.returnType}';
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
