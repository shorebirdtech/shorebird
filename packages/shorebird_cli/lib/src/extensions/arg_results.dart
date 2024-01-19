import 'package:args/args.dart';
import 'package:collection/collection.dart';

extension OptionFinder on ArgResults {
  String? findOption(String name) {
    if (wasParsed(name)) {
      return this[name] as String?;
    }

    // We would ideally check for abbrevations here as well, but ArgResults
    // doesn't expose its parser (which we could use to get the list of
    // [Options] being parsed) or an abbrevations map.
    final flagStart = '--$name=';
    return rest
        .firstWhereOrNull((extra) => extra.startsWith(flagStart))
        ?.substring(flagStart.length);
  }
}
