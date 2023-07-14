/// Get info about your Shorebird code push app
library shorebird_code_push;

export 'shorebird_code_push_io.dart'
    if (dart.library.html) 'shorebird_code_push_web.dart';
