// This file's job is to be the Rust API for the updater.

use std::fmt::{Display, Formatter};

use crate::cache::{
    current_patch_internal, download_into_unused_slot, load_state, save_state, set_current_slot,
    PatchInfo,
};
use crate::config::{set_config, with_config, ResolvedConfig};
use crate::logging::init_logging;
use crate::network::send_patch_check_request;

pub enum UpdateStatus {
    NoUpdate,
    UpdateAvailable,
    UpdateDownloaded,
    UpdateInstalled,
    UpdateHadError,
}

impl Display for UpdateStatus {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            UpdateStatus::NoUpdate => write!(f, "No update"),
            UpdateStatus::UpdateAvailable => write!(f, "Update available"),
            UpdateStatus::UpdateDownloaded => write!(f, "Update downloaded"),
            UpdateStatus::UpdateInstalled => write!(f, "Update installed"),
            UpdateStatus::UpdateHadError => write!(f, "Update had error"),
        }
    }
}

// AppConfig is the rust API.  ResolvedConfig is the internal storage.
// However rusty api would probably used &str instead of String,
// but making &str from CStr* is a bit of a pain.
pub struct AppConfig {
    pub cache_dir: String,
    pub channel: Option<String>, // If None, use the 'stable'.
    pub client_id: String,
    pub product_id: String,
    pub base_version: String,
    pub original_libapp_path: String,
    pub vm_path: String,
    pub base_url: Option<String>, // If None, use the default.
}

pub fn init(app_config: AppConfig) {
    init_logging();
    set_config(app_config);
}

pub fn check_for_update_internal(config: &ResolvedConfig) -> bool {
    // Load UpdaterState from disk
    // If there is no state, make an empty state.
    let state = load_state(&config.cache_dir).unwrap_or_default();
    // Check the current slot.
    let patch = current_patch_internal(&state);
    // Send info from app + current slot to server.
    let response_result = send_patch_check_request(&config, patch);
    match response_result {
        Err(err) => {
            error!("Failed update check: {err}");
            return false;
        }
        Ok(response) => {
            return response.patch_available;
        }
    }
}

pub fn check_for_update() -> bool {
    return with_config(check_for_update_internal);
}

fn update_internal(config: &ResolvedConfig) -> anyhow::Result<UpdateStatus> {
    // Load the state from disk.
    let mut state = load_state(&config.cache_dir).unwrap_or_default();
    let version = current_patch_internal(&state);
    // Check for update.
    let response = send_patch_check_request(&config, version)?;
    if !response.patch_available {
        return Ok(UpdateStatus::NoUpdate);
    }
    // If needed, download the new version.
    let slot = download_into_unused_slot(&config.cache_dir, &response, &mut state)?;
    // Install the new version.
    set_current_slot(&mut state, slot);
    save_state(&state, &config.cache_dir)?;
    // Set the state to "restart required".
    return Ok(UpdateStatus::UpdateInstalled);
}

pub fn active_patch() -> Option<PatchInfo> {
    return with_config(|config| {
        let state = load_state(&config.cache_dir).unwrap_or_default();
        return current_patch_internal(&state);
    });
}

pub fn update() -> UpdateStatus {
    return with_config(|config| {
        let result = update_internal(&config);
        match result {
            Err(err) => {
                error!("Problem updating: {err}");
                error!("{}", err.backtrace());
                return UpdateStatus::UpdateHadError;
            }
            Ok(status) => status,
        }
    });
}
