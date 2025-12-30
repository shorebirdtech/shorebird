/// {@template export_method}
/// The method used to export the IPA. This is passed to the Flutter tool.
/// Acceptable values can be found by running `flutter build ipa -h`.
/// {@endtemplate}
enum ExportMethod {
  /// Upload to the App Store.
  appStore('app-store', 'Upload to the App Store'),

  /// Ad-hoc distribution.
  adHoc('ad-hoc', '''
Test on designated devices that do not need to be registered with the Apple developer account.
    Requires a distribution certificate.'''),

  /// Development distribution.
  development(
    'development',
    '''Test only on development devices registered with the Apple developer account.''',
  ),

  /// Enterprise distribution.
  enterprise(
    'enterprise',
    'Distribute an app registered with the Apple Developer Enterprise Program.',
  );

  /// {@macro export_method}
  const ExportMethod(this.argName, this.description);

  /// The command-line argument name for this export method.
  final String argName;

  /// A description of this method and how/when it should be used.
  final String description;
}
