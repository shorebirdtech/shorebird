// This file's job is to deal with the update_server and network side
// of the updater library.

use std::collections::HashMap;
use std::string::ToString;

use serde::Deserialize;

use crate::cache::{client_id, current_patch, UpdaterState};
use crate::config::ResolvedConfig;

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

    let patch = current_patch(state);

    // Send the request to the server.
    let client = reqwest::blocking::Client::new();
    let mut body = HashMap::new();
    body.insert("client_id", client_id(state));
    body.insert("product_id", config.product_id.clone());
    body.insert("channel", config.channel.clone());
    body.insert("base_version", config.base_version.clone());
    if let Some(patch) = patch {
        body.insert("patch_version", patch.version);
        body.insert("patch_hash", patch.hash);
    }
    body.insert("platform", PLATFORM.to_string());
    body.insert("arch", ARCH.to_string());
    info!("Sending patch check request: {:?}", body);
    let response = client
        .post(&patches_check_url(&config.base_url))
        .json(&body)
        .send()?
        .json()?;
    info!("Patch check response: {:?}", response);
    return Ok(response);
}
