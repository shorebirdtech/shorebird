/// String-level API contract between the trace *producers* (flutter_tools,
/// aot_tools, CocoaPods wrapper, the Gradle init script) and the trace
/// *consumer* (shorebird_cli's `build_trace_summary.dart`).
///
/// Once a name lands in a shipped flutter or aot_tools, shorebird_cli
/// has to understand it across every version pin that ships with that
/// release — shorebird_cli runs against many flutter versions at once.
/// So:
///
/// * **Never rename** a constant here. Add a new one and have shorebird
///   recognize both.
/// * **Don't reuse** a removed constant's value for a different meaning
///   for the same reason.
/// * The Groovy init script (`shorebird_trace_init.gradle` in the flutter
///   fork) can't import Dart — its literals must be hand-kept in sync
///   with this file. The init script carries a comment pointing here.
class TraceSchema {
  TraceSchema._();

  // --- Chrome Trace Event "cat" values ---------------------------------

  /// Flutter-tool setup / teardown and outer `flutter build <target>`
  /// spans.
  static const String catFlutter = 'flutter';

  /// Native build system (Gradle, Xcode) outer spans.
  static const String catGradle = 'gradle';

  /// See [catGradle].
  static const String catXcode = 'xcode';

  /// Per-task events emitted by `shorebird_trace_init.gradle`.
  static const String catGradleTask = 'gradle_task';

  /// Per-subsection events parsed from xcresulttool's structured log.
  static const String catXcodeSubsection = 'xcode_subsection';

  /// `flutter assemble` target spans.
  static const String catAssemble = 'assemble';

  /// Child processes traced via [BuildTracer.startAndTraceSubprocess] or
  /// [BuildTracer.timeSubprocess] — also the category the CocoaPods
  /// wrapper emits phase spans under.
  static const String catSubprocess = 'subprocess';

  /// HTTP request spans (artifact fetches + auth/upload).
  static const String catNetwork = 'network';

  // --- Span name prefixes / literals -----------------------------------

  /// Prefix for the outer flutter build span. Span name is
  /// `"flutter build <target>"` where `<target>` is apk / appbundle /
  /// ios / ipa. shorebird matches with `startsWith`.
  static const String flutterBuildSpanPrefix = 'flutter build ';

  /// Prefix for the outer gradle span. Span name is
  /// `"gradle <assembleTask>"` where `<assembleTask>` is the variant-
  /// specific task (e.g. `assembleRelease`, `bundleFooRelease`).
  /// shorebird bucketizes by the `gradle` category rather than parsing
  /// this prefix, but it's kept here for documentation.
  static const String gradleSpanPrefix = 'gradle ';

  /// Prefix for the outer xcode span. Span name is
  /// `"xcode <action>"` (build / archive / install).
  static const String xcodeSpanPrefix = 'xcode ';

  /// `pod install` namePrefix used by the CocoaPods phase tracker.
  /// Spans emitted are `"pod install: <phase>"` using [PhaseTracker].
  static const String podInstallNamePrefix = 'pod install';

  /// Name of the outer `pod install` span itself (emitted separately
  /// from phase sub-spans).
  static const String podInstallSpanName = 'pod install';

  /// Phase name used by [PhaseTracker] when the `Analyzing
  /// dependencies` line is seen in `pod install --verbose` stdout.
  /// The full span name shorebird matches is
  /// `"pod install: analyzing"` etc.
  static const String podPhaseAnalyzing = 'analyzing';

  /// See [podPhaseAnalyzing].
  static const String podPhaseDownloading = 'downloading';

  /// See [podPhaseAnalyzing].
  static const String podPhaseGenerating = 'generating';

  /// See [podPhaseAnalyzing].
  static const String podPhaseIntegrating = 'integrating';

  // --- Gradle task kinds -----------------------------------------------

  /// Value of `args["kind"]` on per-Gradle-task events. Produced by
  /// `shorebird_trace_init.gradle`'s classifier and consumed by
  /// shorebird_cli's summary. If the init script adds a new kind, it
  /// must also land here AND shorebird_cli must recognize it or it'll
  /// silently fall into the `other` bucket.
  static const String gradleKindKotlinCompile = 'kotlin_compile';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindJavaCompile = 'java_compile';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindDex = 'dex';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindResources = 'resources';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindTransform = 'transform';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindR8Minify = 'r8_minify';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindLint = 'lint';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindFlutterGradlePlugin = 'flutter_gradle_plugin';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindBundle = 'bundle';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindPackaging = 'packaging';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindAidl = 'aidl';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindNativeLink = 'native_link';

  /// See [gradleKindKotlinCompile].
  static const String gradleKindGradleScaffold = 'gradle_scaffold';

  /// Catch-all for unmatched Gradle tasks. Not emitted by the init
  /// script (which writes one of the named kinds above), but used by
  /// consumers for a safety bucket when [args['kind']] is unknown.
  static const String gradleKindOther = 'other';
}
