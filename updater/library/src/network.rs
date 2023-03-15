// This file's job is to deal with the update_server and network side
// of the updater library.

use serde::Deserialize;
use std::collections::HashMap;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use std::string::ToString;

use crate::cache::UpdaterState;
use crate::config::{current_arch, current_platform, ResolvedConfig};

fn patches_check_url(base_url: &str) -> String {
    return format!("{}/api/v1/patches/check", base_url);
}

#[derive(Debug, Deserialize)]
pub struct Patch {
    pub version: String,
    pub hash: String,
    pub download_url: String,
}

#[derive(Debug, Deserialize)]
pub struct PatchCheckResponse {
    pub patch_available: bool,
    #[serde(default)]
    pub patch: Option<Patch>,
}

pub fn send_patch_check_request(
    config: &ResolvedConfig,
    state: &UpdaterState,
) -> anyhow::Result<PatchCheckResponse> {
    let patch = state.current_patch();

    // Send the request to the server.
    let client = reqwest::blocking::Client::new();
    let mut body = HashMap::new();
    body.insert("app_id", config.app_id.clone());
    body.insert("channel", config.channel.clone());
    body.insert("base_version", config.base_version.clone());
    if let Some(patch) = patch {
        body.insert("patch_version", patch.version);
    }
    body.insert("platform", current_platform().to_string());
    body.insert("arch", current_arch().to_string());
    info!("Sending patch check request: {:?}", body);
    let response = client
        .post(&patches_check_url(&config.base_url))
        .json(&body)
        .send()?
        .json()?;
    info!("Patch check response: {:?}", response);
    return Ok(response);
}

pub fn download_file_to_path(url: &str, path: &PathBuf) -> anyhow::Result<()> {
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
