#[cfg(target_os = "android")]
pub fn init_logging() {
    use android_logger::Config;
    use log::LevelFilter;

    android_logger::init_once(
        Config::default()
            // `flutter` tool ignores non-flutter tagged logs.
            .with_tag("flutter")
            .with_max_level(LevelFilter::Debug),
    );
    debug!("Logging initialized");
}

#[cfg(not(target_os = "android"))]
pub fn init_logging() {
    // Nothing to do on non-Android platforms.
    // Eventually iOS/MacOS may need something here.
}
