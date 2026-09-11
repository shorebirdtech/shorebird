// Regeneration entrypoint for the shorebird_code_push_protocol package.
//
// Plugs a Shorebird-specific [FileRenderer] into space_gen's standard
// [runCli] shell. The renderer matches this package's layout convention:
// everything lives under `lib/src/` (standard Dart internal-files layout),
// request/response DTOs owned by a single operation nest under a
// per-operation directory, domain models land in `lib/src/models/`,
// shared messages stay flat in `lib/src/messages/`.
//
// Usage (from the repo root):
//   dart run packages/shorebird_code_push_protocol/tool/gen.dart \
//     -i https://api.shorebird.dev/openapi.json \
//     -o packages/shorebird_code_push_protocol
//
// The generator does not touch `lib/extensions/` or
// `lib/shorebird_code_push_protocol.dart`; those are hand-written and
// re-export the generated types.

import 'package:space_gen/space_gen.dart';

class ShorebirdFileRenderer extends FileRenderer {
  ShorebirdFileRenderer(super.config);

  @override
  String modelPath(LayoutContext context) {
    final snakeName = context.schema.snakeName;
    final className = context.schema.typeName;
    final isMessage =
        className.endsWith('Request') || className.endsWith('Response');
    if (!isMessage) return 'src/models/$snakeName.dart';
    final base = _messageBaseName(snakeName);
    if (context.operationSnakeNames.contains(base)) {
      return 'src/messages/$base/$snakeName.dart';
    }
    return 'src/messages/$snakeName.dart';
  }

  /// Route generated round-trip tests to `test/generated/` so they sit
  /// alongside the hand-written tests at `test/src/` without colliding.
  /// Mirrors [modelPath], just under a dedicated directory.
  @override
  String? testPath(LayoutContext context) {
    final modelRelative = modelPath(context);
    // Strip a leading `src/` — we already namespace under `generated/`.
    final trimmed = modelRelative.startsWith('src/')
        ? modelRelative.substring('src/'.length)
        : modelRelative;
    final withSuffix = trimmed.replaceFirst(
      RegExp(r'\.dart$'),
      '_test.dart',
    );
    return 'test/generated/$withSuffix';
  }

  /// Tests import the hand-maintained top-level barrel, not the
  /// generator's `api.dart` (which we don't emit — see below).
  @override
  String testBarrelImport() => 'shorebird_code_push_protocol.dart';

  // Everything below is a no-op override: this package hand-maintains
  // its pubspec, analysis config, HTTP client, auth, and top-level
  // barrel. space_gen is only on the hook for models/messages/tests
  // and the `model_helpers.dart` runtime library.

  @override
  void renderPubspec() {}

  @override
  void renderAnalysisOptions() {}

  @override
  void renderGitignore() {}

  @override
  void renderApiException() {}

  @override
  void renderAuth() {}

  @override
  void renderApiClient(RenderSpec spec) {}

  @override
  List<Api> renderApis(List<Api> apis) => const [];

  @override
  void renderClient(List<Api> apis, {required String specName}) {}

  @override
  void renderPublicApi(Iterable<Api> apis, Iterable<RenderSchema> schemas) {}

  @override
  void renderCspellConfig(List<String> misspellings) {}

  /// Strip a trailing `_request`/`_response` (and any HTTP status code
  /// inline-schema suffix like `200_response`) from [snake], returning
  /// the operation-name portion. Non-matching input is returned as-is.
  static String _messageBaseName(String snake) {
    for (final suffix in const ['_request', '_response']) {
      if (snake.endsWith(suffix)) {
        var base = snake.substring(0, snake.length - suffix.length);
        final match = RegExp(r'\d+$').firstMatch(base);
        if (match != null) {
          base = base.substring(0, match.start);
        }
        return base;
      }
    }
    return snake;
  }
}

Future<int> main(List<String> arguments) =>
    runCli(arguments, fileRendererBuilder: ShorebirdFileRenderer.new);
