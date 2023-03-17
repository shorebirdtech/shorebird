// This file's job is to deal with the update_server and network side
// of the updater library.

use serde::{Deserialize, Serialize};
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
    pub number: usize,
    pub hash: String,
    pub download_url: String,
}

#[derive(Debug, Serialize)]
pub struct PatchCheckRequest {
    pub app_id: String,
    pub channel: String,
    pub release_version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patch_number: Option<usize>,
    pub platform: String,
    pub arch: String,
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
    let req = PatchCheckRequest {
        app_id: config.app_id.clone(),
        channel: config.channel.clone(),
        release_version: config.release_version.clone(),
        patch_number: patch.map(|p| p.number),
        platform: current_platform().to_string(),
        arch: current_arch().to_string(),
    };
    info!("Sending patch check request: {:?}", req);
    let response = client
        .post(&patches_check_url(&config.base_url))
        .json(&req)
        .send()?
        .json()?;

    info!("Patch check response: {:?}", response);
    return Ok(response);
}

pub fn download_to_path(url: &str, path: &PathBuf) -> anyhow::Result<()> {
    // Download the file at the given url to the given path.
    let client = reqwest::blocking::Client::new();
    let response = client.get(url).send()?;
    let mut bytes = response.bytes()?;

    // Ensure the download directory exists.
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let mut file = File::create(path)?;
    file.write_all(&mut bytes)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::network::PatchCheckResponse;

    #[test]
    fn check_patch_request_response_deserialization() {
        let data = r###"
    {
        "patch_available": true,
        "patch": {
            "number": 1,
            "download_url": "https://storage.googleapis.com/patch_artifacts/17a28ec1-00cf-452d-bdf9-dbb9acb78600/dlc.vmcode",
            "hash": "#"
        }
    }"###;

        let response: PatchCheckResponse = serde_json::from_str(data).unwrap();

        assert!(response.patch_available == true);
        assert!(response.patch.is_some());
        
        let patch = response.patch.unwrap();
        assert_eq!(patch.number, 1);
        assert_eq!(patch.download_url, "https://storage.googleapis.com/patch_artifacts/17a28ec1-00cf-452d-bdf9-dbb9acb78600/dlc.vmcode");
        assert_eq!(patch.hash, "#");
    }
}
