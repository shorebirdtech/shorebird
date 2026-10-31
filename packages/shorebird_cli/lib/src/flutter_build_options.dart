import 'package:args/args.dart';

/// How a [FlutterBuildOption] is written on the command line.
enum FlutterBuildOptionKind {
  /// A boolean flag that also has a `--no-` form, like `--tree-shake-icons`.
  negatableFlag,

  /// A boolean flag with no `--no-` form, like `--ignore-deprecation`.
  flag,

  /// An option that takes a value, like `--code-size-directory=<path>`.
  /// It may be repeated; each occurrence is forwarded.
  option,
}

/// A `flutter build` option that `shorebird release` and `shorebird patch`
/// accept directly (without `--`) and forward to Flutter unchanged.
class FlutterBuildOption {
  /// Creates a [FlutterBuildOption].
  const FlutterBuildOption(this.name, this.kind, {this.abbr});

  /// The option's name, without the leading `--`.
  final String name;

  /// How the option is written.
  final FlutterBuildOptionKind kind;

  /// The single-letter abbreviation Flutter accepts, if any.
  final String? abbr;
}

/// The `flutter build` options Shorebird forwards without `--`.
///
/// The table is needed because `--foo bar` is ambiguous without one: `bar`
/// could be the value of `--foo` or a positional argument. An option not
/// listed here still works after `--`, so a missing entry is an annoyance,
/// not a break.
///
/// Left out: options Shorebird registers itself (`--target`, `--flavor`,
/// `--build-name`, `--dart-define`, `--obfuscate`, `--codesign`,
/// `--target-platform`, `--split-per-abi` and the like), the build mode
/// (`--debug`, `--release`), and options that change where or whether
/// artifacts are written (`--output`, `--config-only`), since Shorebird reads
/// the artifacts from where Flutter writes them by default.
///
/// Taken from the visible options of `flutter build apk`, `appbundle`,
/// `aar`, `ipa`, `ios-framework`, `macos`, `linux` and `windows`.
const flutterBuildOptions = <FlutterBuildOption>[
  FlutterBuildOption('analyze-size', FlutterBuildOptionKind.negatableFlag),
  FlutterBuildOption(
    'android-project-arg',
    FlutterBuildOptionKind.option,
    abbr: 'P',
  ),
  FlutterBuildOption(
    'android-project-cache-dir',
    FlutterBuildOptionKind.option,
  ),
  FlutterBuildOption(
    'android-skip-build-dependency-validation',
    FlutterBuildOptionKind.negatableFlag,
  ),
  FlutterBuildOption('cocoapods', FlutterBuildOptionKind.negatableFlag),
  FlutterBuildOption('code-size-directory', FlutterBuildOptionKind.option),
  FlutterBuildOption('codesign-identity', FlutterBuildOptionKind.option),
  FlutterBuildOption(
    'deferred-components',
    FlutterBuildOptionKind.negatableFlag,
  ),
  FlutterBuildOption('enable-experiment', FlutterBuildOptionKind.option),
  FlutterBuildOption('ignore-deprecation', FlutterBuildOptionKind.flag),
  FlutterBuildOption('plugins', FlutterBuildOptionKind.negatableFlag),
  FlutterBuildOption('pub', FlutterBuildOptionKind.negatableFlag),
  FlutterBuildOption('static', FlutterBuildOptionKind.negatableFlag),
  FlutterBuildOption('target-sysroot', FlutterBuildOptionKind.option),
  FlutterBuildOption(
    'track-widget-creation',
    FlutterBuildOptionKind.negatableFlag,
  ),
  FlutterBuildOption('tree-shake-icons', FlutterBuildOptionKind.negatableFlag),
  FlutterBuildOption(
    'validate-deferred-components',
    FlutterBuildOptionKind.negatableFlag,
  ),
];

/// The `--help` footer of `shorebird [command]` explaining that
/// `flutter build` options are accepted.
String flutterBuildOptionsUsage(String command) => '''

Common flutter build options, such as --no-tree-shake-icons, --no-pub or
-P key=value, are passed to Flutter as given. Put any other flutter build
option after --, for example: shorebird $command android -- --<option>''';

/// Adds [flutterBuildOptions] to an [ArgParser] as hidden options, so a
/// command accepts them directly and forwards them with `forwardedArgs`.
extension FlutterBuildOptionsArgParser on ArgParser {
  /// Registers every option in [flutterBuildOptions], hidden from `--help`
  /// (the command's description says they are accepted).
  void addFlutterBuildOptions() {
    for (final option in flutterBuildOptions) {
      switch (option.kind) {
        case FlutterBuildOptionKind.negatableFlag:
        case FlutterBuildOptionKind.flag:
          addFlag(
            option.name,
            abbr: option.abbr,
            negatable: option.kind == FlutterBuildOptionKind.negatableFlag,
            hide: true,
          );
        case FlutterBuildOptionKind.option:
          addMultiOption(
            option.name,
            abbr: option.abbr,
            splitCommas: false,
            hide: true,
          );
      }
    }
  }
}
