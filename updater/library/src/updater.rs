// This file's job is to be the Rust API for the updater.

use std::fmt;
use std::fmt::{Display, Formatter};

use crate::cache::{download_into_unused_slot, PatchInfo, UpdaterState};
use crate::config::{set_config, with_config, ResolvedConfig};
use crate::logging::init_logging;
use crate::network::send_patch_check_request;
use crate::yaml::YamlConfig;

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

#[derive(Debug, PartialEq)]
pub enum UpdateError {
    InvalidArgument(String, String),
    InvalidState(String),
}

impl std::error::Error for UpdateError {}

impl Display for UpdateError {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            UpdateError::InvalidArgument(name, value) => {
                write!(f, "Invalid Argument: {} -> {}", name, value)
            }
            UpdateError::InvalidState(msg) => write!(f, "Invalid State: {}", msg),
        }
    }
}

// AppConfig is the rust API.  ResolvedConfig is the internal storage.
// However rusty api would probably used &str instead of String,
// but making &str from CStr* is a bit of a pain.
pub struct AppConfig {
    pub cache_dir: String,
    pub base_version: String,
    pub original_libapp_path: String,
    pub vm_path: String,
}

/// Initialize the updater library.
/// Takes a AppConfig struct and a yaml string.
/// The yaml string is the contents of the shorebird.yaml file.
/// The AppConfig struct is information about the running app and where
/// the updater should keep its cache.
pub fn init(app_config: AppConfig, yaml: &str) -> Result<(), UpdateError> {
    init_logging();
    let config = YamlConfig::from_yaml(&yaml)
        .map_err(|err| UpdateError::InvalidArgument("yaml".to_string(), err.to_string()))?;
    set_config(app_config, config);
    Ok(())
}

fn check_for_update_internal(config: &ResolvedConfig) -> bool {
    // Load UpdaterState from disk
    // If there is no state, make an empty state.
    let state = UpdaterState::load(&config.cache_dir).unwrap_or_default();
    // Send info from app + current slot to server.
    let response_result = send_patch_check_request(&config, &state);
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

/// Synchronously checks for an update and returns true if an update is available.
pub fn check_for_update() -> bool {
    return with_config(check_for_update_internal);
}

fn update_internal(config: &ResolvedConfig) -> anyhow::Result<UpdateStatus> {
    // Load the state from disk.
    let mut state = UpdaterState::load(&config.cache_dir).unwrap_or_default();
    // Check for update.
    let response = send_patch_check_request(&config, &state)?;
    if !response.patch_available {
        return Ok(UpdateStatus::NoUpdate);
    }
    // If needed, download the new version.
    let slot = download_into_unused_slot(&config.cache_dir, &response, &mut state)?;
    // Install the new version.
    state.set_current_slot(slot);
    state.save(&config.cache_dir)?;
    // Set the state to "restart required".
    return Ok(UpdateStatus::UpdateInstalled);
}

/// Reads the current patch from the cache and returns it.
pub fn active_patch() -> Option<PatchInfo> {
    return with_config(|config| {
        let state = UpdaterState::load(&config.cache_dir).unwrap_or_default();
        return state.current_patch();
    });
}

pub fn report_failed_launch() -> Result<(), UpdateError> {
    return with_config(|config| {
        let mut state = UpdaterState::load(&config.cache_dir).unwrap_or_default();

        let patch = state
            .current_patch()
            .ok_or(UpdateError::InvalidState("No current patch".to_string()))?;
        state.mark_patch_as_bad(&patch);
        state.save(&config.cache_dir).unwrap();
        Ok(())
    });
}

pub fn report_successful_launch() {
    with_config(|config| {
        let mut state = UpdaterState::load(&config.cache_dir).unwrap_or_default();

        let patch = state.current_patch().unwrap();
        state.mark_patch_as_good(&patch);
        state.save(&config.cache_dir).unwrap();
    });
}

/// Synchronously checks for an update and downloads and installs it if available.
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

#[cfg(test)]
mod tests {
    use tempdir::TempDir;

    fn init_for_testing() {
        let tmp_dir = TempDir::new("example").unwrap();
        let cache_dir = tmp_dir.path().to_str().unwrap().to_string();
        crate::init(
            crate::AppConfig {
                cache_dir: cache_dir.clone(),
                base_version: "1.0.0".to_string(),
                original_libapp_path: "original_libapp_path".to_string(),
                vm_path: "vm_path".to_string(),
            },
            "app_id: 1234",
        )
        .unwrap();
    }

    #[test]
    fn init_missing_yaml() {
        let tmp_dir = TempDir::new("example").unwrap();
        let cache_dir = tmp_dir.path().to_str().unwrap().to_string();
        assert_eq!(
            crate::init(
                crate::AppConfig {
                    cache_dir: cache_dir.clone(),
                    base_version: "1.0.0".to_string(),
                    original_libapp_path: "original_libapp_path".to_string(),
                    vm_path: "vm_path".to_string(),
                },
                "",
            ),
            Err(crate::UpdateError::InvalidArgument(
                "yaml".to_string(),
                "missing field `app_id`".to_string()
            ))
        );
    }

    #[test]
    fn report_failure_with_no_current() {
        init_for_testing();
        assert_eq!(
            crate::report_failed_launch(),
            Err(crate::UpdateError::InvalidState(
                "No current patch".to_string()
            ))
        );
    }
}
