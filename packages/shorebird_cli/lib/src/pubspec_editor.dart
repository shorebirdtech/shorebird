import 'dart:math';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// A reference to a [PubspecEditor] instance.
final pubspecEditorRef = create(PubspecEditor.new);

/// The [PubspecEditor] instance available in the current zone.
PubspecEditor get pubspecEditor => read(pubspecEditorRef);

/// {@template pubspec_editor}
/// A class that exposes APIs to edit the current project's `pubspec.yaml`.
/// {@endtemplate}
class PubspecEditor {
  /// Adds shorebird.yaml to the assets section of the pubspec.yaml file.
  /// Does nothing if the pubspec.yaml file already contains shorebird.yaml.
  /// Does nothing if a flutter project root cannot be found.
  void addShorebirdYamlToPubspecAssets() {
    if (shorebirdEnv.pubspecContainsShorebirdYaml) return;

    final root = shorebirdEnv.getFlutterProjectRoot();
    // TODO(felangel): this should throw an exception instead of returning
    // to make it explicit that the edit operation failed.
    if (root == null) return;

    final pubspecFile = shorebirdEnv.getPubspecYamlFile(cwd: root);
    final pubspecContents = pubspecFile.readAsStringSync();
    final editor = YamlEditor(pubspecContents);
    final yaml = loadYaml(pubspecContents, sourceUrl: pubspecFile.uri) as Map;

    if (!yaml.containsKey('flutter') || yaml['flutter'] == null) {
      editor.update(
        ['flutter'],
        {
          'assets': ['shorebird.yaml'],
        },
      );
    } else {
      if (!(yaml['flutter'] as Map).containsKey('assets')) {
        final flutter = (yaml as YamlMap).nodes['flutter'];
        // Not `editor.update`, which chooses where a new key goes and chooses
        // wrong when the map has exactly one key: it inserts *before* that
        // key rather than after it, which separates the key from the comment
        // block above it. That is the shape `flutter create` emits --
        // `flutter:` holding only `uses-material-design: true`, with three
        // lines of comment above describing it -- so almost every first
        // `shorebird init` rewrote a comment onto the wrong line. With two or
        // more keys the same call appends correctly, which is why this went
        // unnoticed: it only misfires on the default project.
        //
        // Only for a block map with something in it. An empty one has no last
        // entry to append after, and a flow one (`flutter: {a: b}`) has no
        // block layout to match, so appending a block key to it would produce
        // something that no longer parses. `yaml_edit` handles both of those
        // correctly, and neither can hit the misplacement above, so they keep
        // going through it.
        if (flutter is YamlMap &&
            flutter.style == CollectionStyle.BLOCK &&
            flutter.isNotEmpty) {
          pubspecFile.writeAsStringSync(
            _appendAssetsToFlutterSection(pubspecContents, flutter),
          );
          return;
        }
        editor.update(['flutter', 'assets'], ['shorebird.yaml']);
      } else {
        final assets = (yaml['flutter'] as Map)['assets'] as List;
        if (!assets.contains('shorebird.yaml')) {
          editor.update(['flutter', 'assets'], [...assets, 'shorebird.yaml']);
        }
      }
    }

    if (editor.edits.isEmpty) return;

    pubspecFile.writeAsStringSync(editor.toString());
  }

  /// The offset just past the deepest scalar under [node].
  ///
  /// Recurses rather than reading [node]'s own span because only a scalar's
  /// span is tight; a collection's extends to whatever comes after it. Keys
  /// count as well as values, so a mapping whose last entry has an empty
  /// collection for a value still lands on that key.
  ///
  /// A block scalar is a scalar, so text inside one that merely looks like a
  /// comment stays part of the document rather than being walked over.
  int _lastLeafEnd(YamlNode node) {
    if (node is YamlMap && node.nodes.isNotEmpty) {
      return node.nodes.entries
          .map(
            (e) => max(_lastLeafEnd(e.key as YamlNode), _lastLeafEnd(e.value)),
          )
          .reduce(max);
    }
    if (node is YamlList && node.nodes.isNotEmpty) {
      return node.nodes.map(_lastLeafEnd).reduce(max);
    }
    return node.span.end.offset;
  }

  /// Splices an `assets` block in directly after the last entry of an existing
  /// `flutter` section, which is where `yaml_edit` puts it whenever it has
  /// more than one entry to reason about.
  ///
  /// Placing it by hand rather than by key is what keeps every comment
  /// attached to the line it documents: a comment is not part of the YAML
  /// tree, so anything choosing a position from the tree alone is free to land
  /// between a comment and its key.
  String _appendAssetsToFlutterSection(String contents, YamlMap flutter) {
    // The last leaf's end, not the last entry's. A scalar's span stops at its
    // own text, but a block collection's runs on through whatever follows it,
    // and for the last entry of a mapping that is the rest of the document --
    // blank lines and any trailing comment included. Appending at the entry's
    // own end would put `assets:` underneath a comment that has nothing to do
    // with it, which is the thing this method exists to avoid.
    var end = _lastLeafEnd(flutter.nodes[flutter.keys.last]!);
    if (end > 0 && contents[end - 1] == '\n') {
      end -= 1;
    } else {
      while (end < contents.length && contents[end] != '\n') {
        end++;
      }
    }

    // Taken from the document rather than assumed, the way `yaml_edit` takes
    // it, so a pubspec written with a different indent keeps that indent
    // here instead of gaining a section in some other one. The keys of
    // `flutter` sit exactly one step in, which makes that column the step.
    final step = (flutter.nodes.keys.first as YamlScalar).span.start.column;
    final key = ' ' * step;
    final item = ' ' * (step * 2);

    final block = '\n${key}assets:\n$item- shorebird.yaml';
    return contents.substring(0, end) + block + contents.substring(end);
  }
}
