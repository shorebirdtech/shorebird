// This file's job is to deal with the update_server and network side
// of the updater library.

use std::collections::HashMap;
use std::string::ToString;

use serde::Deserialize;

use crate::cache::PatchInfo;
use crate::config::ResolvedConfig;

fn updates_url(base_url: &str) -> String {
    return format!("{}/api/v1/updates", base_url);
}

#[derive(Deserialize)]
pub struct Update {
    pub version: String,
    pub hash: String,
    pub download_url: String,
}

#[derive(Deserialize)]
pub struct UpdateResponse {
    pub update_available: bool,
    #[serde(default)]
    pub update: Option<Update>,
}

pub fn send_update_request(
    config: &ResolvedConfig,
    patch: Option<PatchInfo>,
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
    body.insert("product_id", config.product_id.clone());
    body.insert("channel", config.channel.clone());
    body.insert("base_version", config.base_version.clone());
    if let Some(patch) = patch {
        body.insert("patch_version", patch.version);
        body.insert("patch_hash", patch.hash);
    }
    body.insert("platform", PLATFORM.to_string());
    body.insert("arch", ARCH.to_string());
    let response = client
        .post(&updates_url(&config.base_url))
        .json(&body)
        .send()?
        .json()?;
    return Ok(response);
}
