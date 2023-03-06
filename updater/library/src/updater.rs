use std::collections::HashMap;
use std::fmt::{Display, Formatter};
use std::fs::File;
use std::io::{BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::string::ToString;

use android_logger::Config;
use log::LevelFilter;

use serde::{Deserialize, Serialize};
// use thiserror::Error;

// #[derive(Error, Debug)]
// pub enum UpdateError {
//     #[error("update server disconnected")]
//     NetworkFailure(#[from] std::io::Error),
//     #[error("unknown error")]
//     Unknown,
// }

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

pub struct AppConfig {
    // provided from the application
    pub client_id: String,
    pub cache_dir: Option<String>,
    // typically default=shorebird, but provided by the app as override?
    // pub base_url: Option<&'a str>,
    // typically default=stable, but provided by the app as override.
    // pub channel: Option<&'a str>,
    // Other needs:
    // Architecture? Or engine can get that itself?
    // fallback path?  Or engine just returns null and caller figures that out?
}

pub struct VersionInfo {
    pub path: String,
    pub version: String,
    pub hash: String,
}

#[derive(Deserialize, Serialize, Default, Clone)]
struct Slot {
    path: String,
    version: String,
    hash: String,
}

#[derive(Deserialize, Serialize)]
struct UpdaterState {
    current_slot_index: usize,
    slots: Vec<Slot>,
}

impl Default for UpdaterState {
    fn default() -> Self {
        Self {
            current_slot_index: 0,
            slots: Vec::new(),
        }
    }
}

struct ResolvedConfig {
    client_id: String,
    base_url: String,
    channel: String,
    cache_dir: String,
}

fn load_state(cache_dir: &str) -> anyhow::Result<UpdaterState> {
    // Load UpdaterState from disk
    let path = Path::new(cache_dir).join("state.json");
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    let state = serde_json::from_reader(reader)?;
    Ok(state)
}

fn save_state(state: &UpdaterState, cache_dir: &str) -> anyhow::Result<()> {
    // Save UpdaterState to disk
    std::fs::create_dir_all(cache_dir)?;
    let path = Path::new(cache_dir).join("state.json");
    let file = File::create(path)?;
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, &state)?;
    Ok(())
}

fn resolve_config(config: &AppConfig) -> ResolvedConfig {
    // Resolve the config
    // If there is no base_url, use the default.
    // If there is no channel, use the default.
    return ResolvedConfig {
        client_id: config.client_id.to_string(),
        base_url: "https://shorebird-code-push-api-cypqazu4da-uc.a.run.app".to_string(),
        cache_dir: config
            .cache_dir
            .as_deref()
            .unwrap_or("updater_cache")
            .to_owned(),
        channel: "stable".to_string(),
    };
}

fn updates_url(config: &ResolvedConfig) -> String {
    return format!("{}/api/v1/updates", config.base_url);
}

#[derive(Deserialize)]
struct Update {
    version: String,
    hash: String,
    download_url: String,
}

#[derive(Deserialize)]
struct UpdateResponse {
    update_available: bool,
    #[serde(default)]
    update: Option<Update>,
}

pub fn check_for_update(app_config: &AppConfig) -> bool {
    let config = resolve_config(app_config);
    // Load UpdaterState from disk
    // If there is no state, make an empty state.
    let state = load_state(&config.cache_dir).unwrap_or_default();
    // Check the current slot.
    let version = current_version_internal(&state);
    // Send info from app + current slot to server.
    let response_result = send_update_request(&config, version);
    match response_result {
        Err(err) => {
            error!("Failed update check: {err}");
            return false;
        }
        Ok(response) => {
            return response.update_available;
        }
    }
}

fn send_update_request(
    config: &ResolvedConfig,
    version: Option<VersionInfo>,
) -> anyhow::Result<UpdateResponse> {
    #[cfg(target_os = "macos")]
    static PLATFORM: &str = "macos";
    #[cfg(target_os = "linux")]
    static PLATFORM: &str = "linux";
    #[cfg(target_os = "windows")]
    static PLATFORM: &str = "windows";
    #[cfg(target_os = "android")]
    static PLATFORM: &str = "android";

    #[cfg(target_arch = "x86")]
    static ARCH: &str = "x86";
    #[cfg(target_arch = "x86_64")]
    static ARCH: &str = "x86_64";
    #[cfg(target_arch = "aarch64")]
    static ARCH: &str = "aarch64";

    // Send the request to the server.
    let client = reqwest::blocking::Client::new();
    let mut body = HashMap::new();
    body.insert("client_id", config.client_id.clone());
    body.insert("channel", config.channel.clone());
    if let Some(version) = version {
        body.insert("version", version.version);
        body.insert("hash", version.hash);
    }
    body.insert("platform", PLATFORM.to_string());
    body.insert("arch", ARCH.to_string());
    let response = client
        .post(&updates_url(config))
        .json(&body)
        .send()?
        .json()?;
    return Ok(response);
}

fn current_version_internal(state: &UpdaterState) -> Option<VersionInfo> {
    // If there is no state, return None.
    if state.slots.is_empty() {
        return None;
    }
    let slot = &state.slots[state.current_slot_index];
    // Otherwise return the version info from the current slot.
    return Some(VersionInfo {
        path: slot.path.clone(),
        version: slot.version.clone(),
        hash: slot.hash.clone(),
    });
}

pub fn active_version(config: &AppConfig) -> Option<VersionInfo> {
    let config = resolve_config(config);
    let state = load_state(&config.cache_dir).unwrap_or_default();
    return current_version_internal(&state);
}

fn unused_slot(state: &UpdaterState) -> usize {
    // Assume we only use two slots and pick the one that's not current.
    if state.slots.is_empty() {
        return 0;
    }
    if state.current_slot_index == 0 {
        return 1;
    }
    return 0;
}

fn set_slot(state: &mut UpdaterState, index: usize, slot: Slot) {
    if state.slots.len() < index + 1 {
        // Make sure we're not filling with empty slots.
        assert!(state.slots.len() == index);
        state.slots.resize(index + 1, Slot::default());
    }
    // Set the given slot to the given version.
    state.slots[index] = slot
}

fn download_file_to_path(url: &str, path: &PathBuf) -> anyhow::Result<()> {
    // Download the file at the given url to the given path.
    let client = reqwest::blocking::Client::new();
    let response = client.get(url).send()?;
    let mut bytes = response.bytes()?;

    // Ensure the download directory exists.
    std::fs::create_dir_all(path.parent().unwrap())?;

    let mut file = File::create(path)?;
    file.write_all(&mut bytes)?;
    Ok(())
}

fn download_into_slot(
    config: &ResolvedConfig,
    update_response: &UpdateResponse,
    state: &mut UpdaterState,
    slot_index: usize,
) -> anyhow::Result<()> {
    // Download the new version into the given slot.
    let path = Path::new(&config.cache_dir)
        .join(format!("slot_{}", slot_index))
        .join("libapp.txt");

    // TODO: Shouldn't crash on malformed response.
    let update = update_response.update.as_ref().unwrap();

    // We should download into a separate place and move into place.
    // That would allow us to check the hash before moving into place.
    // Would also allow the move/state update to be "atomic" or at least allow
    // us to carefully guard against state corruption.
    // Would also let us support when we need to allow the system to download for us (e.g. iOS).
    download_file_to_path(&update.download_url, &path)?;
    // Check the hash against the download?

    // Update the state to include the new version.
    set_slot(
        state,
        slot_index,
        Slot {
            path: path.to_str().unwrap().to_string(),
            version: update.version.clone(),
            hash: update.hash.clone(),
        },
    );
    save_state(&state, &config.cache_dir)?;

    return Ok(());
}

fn update_internal(config: &ResolvedConfig) -> anyhow::Result<UpdateStatus> {
    // Load the state from disk.
    let mut state = load_state(&config.cache_dir).unwrap_or_default();
    let version = current_version_internal(&state);
    // Check for update.
    let response = send_update_request(&config, version)?;
    if !response.update_available {
        return Ok(UpdateStatus::NoUpdate);
    }
    // If needed, download the new version.
    let slot = unused_slot(&mut state);
    download_into_slot(&config, &response, &mut state, slot)?;
    // Install the new version.
    state.current_slot_index = slot;
    save_state(&state, &config.cache_dir)?;
    // Set the state to "restart required".
    return Ok(UpdateStatus::UpdateInstalled);
}

fn init_logging() {
    android_logger::init_once(
        Config::default()
            // `flutter` tool ignores non-flutter tagged logs.
            .with_tag("flutter")
            .with_max_level(LevelFilter::Debug),
    );
    debug!("Logging initialized");
}

pub fn update(app_config: &AppConfig) -> UpdateStatus {
    init_logging();

    let config = resolve_config(&app_config);
    let result = update_internal(&config);
    match result {
        Err(err) => {
            error!("Problem updating: {err}");
            error!("{}", err.backtrace());
            return UpdateStatus::UpdateHadError;
        }
        Ok(status) => status,
    }
}
