// This file handles the global config for the updater library.

use std::sync::Mutex;

use crate::updater::AppConfig;
use crate::yaml::YamlConfig;
use once_cell::sync::OnceCell;

// cbindgen looks for const, ignore these so it doesn't warn about them.

/// cbindgen:ignore
const DEFAULT_BASE_URL: &'static str = "https://code-push-server-kmdbqkx7rq-uc.a.run.app";
/// cbindgen:ignore
const DEFAULT_CHANNEL: &'static str = "stable";

fn global_config() -> &'static Mutex<ResolvedConfig> {
    static INSTANCE: OnceCell<Mutex<ResolvedConfig>> = OnceCell::new();
    INSTANCE.get_or_init(|| Mutex::new(ResolvedConfig::empty()))
}

pub fn with_config<F, R>(f: F) -> R
where
    F: FnOnce(&ResolvedConfig) -> R,
{
    let lock = global_config()
        .lock()
        .expect("Failed to acquire updater lock.");

    if !lock.is_initialized {
        panic!("Must call shorebird_init() before using the updater.");
    }
    return f(&lock);
}

#[derive(Debug)]
pub struct ResolvedConfig {
    is_initialized: bool,
    pub cache_dir: String,
    pub channel: String,
    pub product_id: String,
    pub base_version: String,
    pub original_libapp_path: String,
    pub vm_path: String,
    pub base_url: String,
}

impl ResolvedConfig {
    pub fn empty() -> Self {
        Self {
            is_initialized: false,
            cache_dir: String::new(),
            channel: String::new(),
            product_id: String::new(),
            base_version: String::new(),
            original_libapp_path: String::new(),
            vm_path: String::new(),
            base_url: String::new(),
        }
    }
}

pub fn set_config(config: AppConfig, yaml: YamlConfig) {
    // If there is no base_url, use the default.
    // If there is no channel, use the default.
    let mut lock = global_config()
        .lock()
        .expect("Failed to acquire updater lock.");
    lock.base_url = yaml
        .base_url
        .as_deref()
        .unwrap_or(DEFAULT_BASE_URL)
        .to_owned();
    lock.channel = yaml
        .channel
        .as_deref()
        .unwrap_or(DEFAULT_CHANNEL)
        .to_owned();
    lock.cache_dir = config.cache_dir.to_string();
    lock.product_id = yaml.product_id.to_string();
    lock.base_version = config.base_version.to_string();
    lock.original_libapp_path = config.original_libapp_path.to_string();
    lock.vm_path = config.vm_path.to_string();
    lock.is_initialized = true;
    info!("Updater configured with: {:?}", lock);
}
