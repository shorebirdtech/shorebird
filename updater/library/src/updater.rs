// This file's job is to be the Rust API for the updater.

use std::fmt::{Display, Formatter};

use crate::cache::{PatchInfo, UpdaterState};
use crate::config::{set_config, with_config, ResolvedConfig};
use crate::logging::init_logging;
use crate::network::{download_to_path, send_patch_check_request};
use crate::yaml::YamlConfig;
use std::path::{Path, PathBuf};

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
    BadServerResponse,
    FailedToSaveState,
}

impl std::error::Error for UpdateError {}

impl Display for UpdateError {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        match self {
            UpdateError::InvalidArgument(name, value) => {
                write!(f, "Invalid Argument: {} -> {}", name, value)
            }
            UpdateError::InvalidState(msg) => write!(f, "Invalid State: {}", msg),
            UpdateError::FailedToSaveState => write!(f, "Failed to save state"),
            UpdateError::BadServerResponse => write!(f, "Bad server response"),
        }
    }
}

// AppConfig is the rust API.  ResolvedConfig is the internal storage.
// However rusty api would probably used &str instead of String,
// but making &str from CStr* is a bit of a pain.
pub struct AppConfig {
    pub cache_dir: String,
    pub release_version: String,
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
    let state = UpdaterState::load_or_new_on_error(&config.cache_dir, &config.release_version);
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
    let mut state = UpdaterState::load_or_new_on_error(&config.cache_dir, &config.release_version);
    // Check for update.
    let response = send_patch_check_request(&config, &state)?;
    if !response.patch_available {
        return Ok(UpdateStatus::NoUpdate);
    }

    let patch = response.patch.ok_or(UpdateError::BadServerResponse)?;

    let download_dir = PathBuf::from(&config.cache_dir);
    let mut download_path = download_dir.join(patch.number.to_string());
    download_to_path(&patch.download_url, &download_path)?;

    // Inflate the patch from a diff if needed.
    if patch.is_diff {
        let base_path = PathBuf::from(&config.original_libapp_path);
        let output_path = download_dir.join(format!("{}.full", patch.number.to_string()));
        inflate(&download_path, &base_path, &output_path)?;
        download_path = output_path;
    }

    // Check the hash before moving into place.
    // Move/state update should be "atomic".
    // Consider supporting allowing the system to download for us (e.g. iOS).

    let patch_info = PatchInfo {
        path: download_path.to_str().unwrap().to_string(),
        number: patch.number,
    };
    state.install_patch(patch_info)?;

    // Set the state to "restart required".
    return Ok(UpdateStatus::UpdateInstalled);
}

fn inflate(patch_path: &Path, base_path: &Path, output_path: &Path) -> anyhow::Result<()> {
    info!("Patch is compressed, inflating...");
    use comde::de::Decompressor;
    use comde::zstd::ZstdDecompressor;
    use std::fs::File;
    use std::io::{BufReader, BufWriter};

    // Open all our files first for error clarity.  Otherwise we might see
    // PipeReader/Writer errors instead of file open errors.
    info!("Reading base file: {:?}", base_path);
    let base_r = File::open(base_path)?;
    let compressed_patch_r = BufReader::new(File::open(patch_path)?);
    let output_file_w = File::create(&output_path)?;

    // Set up a pipe to connect the writing from the decompression thread
    // to the reading of the decompressed patch data on this thread.
    let (patch_r, patch_w) = pipe::pipe();

    let decompress = ZstdDecompressor::new();
    // Spawn a thread to run the decompression in parallel to the patching.
    // decompress.copy will block on the pipe being full (I think) and then
    // when it returns the thread will exit.
    std::thread::spawn(move || {
        let result = decompress.copy(compressed_patch_r, patch_w);
        // If this thread fails, undoubtedly the main thread will fail too.
        // Most important is to not crash.
        if let Err(err) = result {
            error!("Decompression thread failed: {err}");
        }
    });

    // Do the patch, using the uncompressed patch data from the pipe.
    let mut fresh_r = bipatch::Reader::new(patch_r, base_r)?;

    // Write out the resulting patched file to the new location.
    let mut output_w = BufWriter::new(output_file_w);
    std::io::copy(&mut fresh_r, &mut output_w)?;
    Ok(())
}

/// Reads the current patch from the cache and returns it.
pub fn active_patch() -> Option<PatchInfo> {
    return with_config(|config| {
        let state = UpdaterState::load_or_new_on_error(&config.cache_dir, &config.release_version);
        return state.current_patch();
    });
}

pub fn report_failed_launch() -> Result<(), UpdateError> {
    info!("Reporting failed launch.");
    with_config(|config| {
        let mut state =
            UpdaterState::load_or_new_on_error(&config.cache_dir, &config.release_version);

        let patch = state
            .current_patch()
            .ok_or(UpdateError::InvalidState("No current patch".to_string()))?;
        state.mark_patch_as_bad(&patch);
        state.activate_latest_bootable_patch()
    })
}

pub fn report_successful_launch() -> Result<(), UpdateError> {
    with_config(|config| {
        let mut state =
            UpdaterState::load_or_new_on_error(&config.cache_dir, &config.release_version);

        let patch = state
            .current_patch()
            .ok_or(UpdateError::InvalidState("No current patch".to_string()))?;
        state.mark_patch_as_good(&patch);
        state.save().map_err(|_| UpdateError::FailedToSaveState)
    })
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

    fn init_for_testing(tmp_dir: &TempDir) {
        let cache_dir = tmp_dir.path().to_str().unwrap().to_string();
        crate::init(
            crate::AppConfig {
                cache_dir: cache_dir.clone(),
                release_version: "1.0.0".to_string(),
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
                    release_version: "1.0.0".to_string(),
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
    fn report_launch_result_with_no_current_patch() {
        let tmp_dir = TempDir::new("example").unwrap();
        init_for_testing(&tmp_dir);
        assert_eq!(
            crate::report_failed_launch(),
            Err(crate::UpdateError::InvalidState(
                "No current patch".to_string()
            ))
        );
        assert_eq!(
            crate::report_successful_launch(),
            Err(crate::UpdateError::InvalidState(
                "No current patch".to_string()
            ))
        );
    }

    #[test]
    fn ignore_version_after_marked_bad() {
        let tmp_dir = TempDir::new("example").unwrap();
        init_for_testing(&tmp_dir);

        use crate::cache::{PatchInfo, UpdaterState};
        use crate::config::with_config;

        // Install a fake patch.
        with_config(|config| {
            let download_dir = std::path::PathBuf::from(&config.download_dir);
            let artifact_path = download_dir.join("1");
            println!("artifact_path: {:?}", artifact_path);
            std::fs::create_dir_all(&download_dir).unwrap();
            std::fs::write(&artifact_path, "hello").unwrap();

            let mut state =
                UpdaterState::load_or_new_on_error(&config.cache_dir, &config.release_version);
            state
                .install_patch(PatchInfo {
                    path: artifact_path.to_str().unwrap().to_string(),
                    number: 1,
                })
                .expect("move failed");
            state.save().expect("save failed");
        });
        assert!(crate::active_patch().is_some());
        // pretend we booted from it
        crate::report_successful_launch().unwrap();
        assert!(crate::active_patch().is_some());
        // mark it bad.
        crate::report_failed_launch().unwrap();
        // Technically might need to "reload"
        // ask for current patch (should get none).
        assert!(crate::active_patch().is_none());
    }
}
