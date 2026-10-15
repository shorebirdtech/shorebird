import 'package:json_annotation/json_annotation.dart';

part 'shorebird_yaml.g.dart';

/// The patch verification mode for the app.
@JsonEnum(fieldRename: FieldRename.snake)
enum PatchVerification {
  /// Verify the patch signature and hash before installing and loading.
  strict,

  /// Verify the patch signature and hash before installing, but not when
  /// loading from cache.
  installOnly,
}

/// {@template shorebird_yaml}
/// A Shorebird configuration file which contains metadata about the app.
/// {@endtemplate}
@JsonSerializable(anyMap: true, disallowUnrecognizedKeys: true)
class ShorebirdYaml {
  /// {@macro shorebird_yaml}
  const ShorebirdYaml({
    required this.appId,
    this.flavors,
    this.baseUrl,
    this.autoUpdate,
    this.patchVerification,
  });

  /// Creates a [ShorebirdYaml] from a JSON map.
  factory ShorebirdYaml.fromJson(Map<dynamic, dynamic> json) =>
      _$ShorebirdYamlFromJson(json);

  /// Converts this [ShorebirdYaml] to a JSON map.
  Map<String, dynamic> toJson() => _$ShorebirdYamlToJson(this);

  /// The base app id.
  ///
  /// Example:
  /// `"8d3155a8-a048-4820-acca-824d26c29b71"`
  final String appId;

  /// A map of flavor names to app ids.
  ///
  /// Will be `null` for apps with no flavors.
  ///
  /// Example:
  /// ```json
  /// {
  ///   "development": "8d3155a8-a048-4820-acca-824d26c29b71",
  ///   "production": "d458e87a-7362-4386-9eeb-629db2af413a"
  /// }
  /// ```
  final Map<String, String>? flavors;

  /// The base url used to check for updates.
  final String? baseUrl;

  /// Whether or not to automatically update the app.
  final bool? autoUpdate;

  /// The patch verification mode for the app.
  final PatchVerification? patchVerification;
}

/// Extension on [ShorebirdYaml] to get the app id for a specific flavor.
extension AppIdExtension on ShorebirdYaml {
  /// Returns the app id for the given flavor.
  String getAppId({String? flavor}) {
    if (flavor == null || flavors == null) return appId;
    return flavors![flavor] ?? appId;
  }

  /// Why [flavor] can't be used with this project, or null if it can.
  ///
  /// [getAppId] falls back to the default app id for a flavor it doesn't
  /// know, so a mistyped `--flavor` must be rejected with this before the
  /// app id is used.
  String? unknownFlavorError(String? flavor) {
    if (flavor == null) return null;
    final projectFlavors = flavors;
    if (projectFlavors == null) {
      return '''The project does not have any flavors defined (no "flavors" in shorebird.yaml), but --flavor was provided. Re-run without --flavor, or run "shorebird init" to detect flavors.''';
    }
    if (!projectFlavors.containsKey(flavor)) {
      return '''This project does not have a flavor named "$flavor". Pass one of: ${projectFlavors.keys.join(', ')} (from "flavors" in shorebird.yaml).''';
    }
    return null;
  }
}
