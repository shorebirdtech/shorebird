// This file handles the global config for the updater library.

use std::cell::RefCell;

use crate::updater::AppConfig;

const DEFAULT_BASE_URL: &'static str = "https://shorebird-code-push-api-cypqazu4da-uc.a.run.app";
const DEFAULT_CHANNEL: &'static str = "stable";

thread_local!(static CONFIG: RefCell<Option<ResolvedConfig>> = RefCell::new(None));

pub fn with_config<F, R>(f: F) -> R
where
    F: FnOnce(&ResolvedConfig) -> R,
{
    CONFIG
        .try_with(|config| {
            let config = config.borrow();
            let config = config
                .as_ref()
                .expect("Must call updater_init before using the updater library.");
            return f(config);
        })
        .expect("Must call updater_init before using the updater library.")
}

pub fn set_config(config: AppConfig) {
    let config = resolve_config(config);
    CONFIG.with(|c| {
        let mut c = c.borrow_mut();
        *c = Some(config);
    });
}

pub struct ResolvedConfig {
    pub cache_dir: String,
    pub channel: String,
    pub client_id: String,
    pub product_id: String,
    pub base_version: String,
    pub original_libapp_path: String,
    pub vm_path: String,
    pub base_url: String,
}

fn resolve_config(config: AppConfig) -> ResolvedConfig {
    // Resolve the config
    // If there is no base_url, use the default.
    // If there is no channel, use the default.
    return ResolvedConfig {
        client_id: config.client_id.to_string(),
        base_url: config
            .base_url
            .as_deref()
            .unwrap_or(DEFAULT_BASE_URL)
            .to_owned(),
        cache_dir: config.cache_dir.to_string(),
        channel: config
            .channel
            .as_deref()
            .unwrap_or(DEFAULT_CHANNEL)
            .to_owned(),
        product_id: config.product_id.to_string(),
        base_version: config.base_version.to_string(),
        original_libapp_path: config.original_libapp_path.to_string(),
        vm_path: config.vm_path.to_string(),
    };
}
