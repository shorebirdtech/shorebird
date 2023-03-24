// This file deals with the cache / state management for the updater.

use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::path::{Path, PathBuf};

use anyhow::Ok;
use serde::{Deserialize, Serialize};

use crate::updater::UpdateError;

#[derive(PartialEq, Debug)]
pub struct PatchInfo {
    pub path: String,
    pub number: usize,
}

#[derive(Deserialize, Serialize, Default, Clone, Debug)]
struct Slot {
    /// Path to the slot directory.
    path: String,
    /// Patch number for the patch in this slot.
    patch_number: usize,
}

impl Slot {
    fn to_patch_info(&self) -> PatchInfo {
        PatchInfo {
            path: self.path.clone(),
            number: self.patch_number,
        }
    }
}

// This struct is public, as callers can have a handle to it, but modifying
// anything inside should be done via the functions below.
#[derive(Deserialize, Serialize)]
pub struct UpdaterState {
    /// Where this writes to disk.
    cache_dir: String,
    /// The release version this cache corresponds to.
    /// If this does not match the release version we're booting from we will
    /// clear the cache.
    release_version: String,
    /// The patch number of the patch that was last downloaded.
    latest_downloaded_patch: Option<usize>,
    /// List of patches that failed to boot.  We will never attempt these again.
    failed_patches: Vec<usize>,
    /// List of patches that successfully booted. We will never rollback past
    /// one of these for this device.
    successful_patches: Vec<usize>,
    /// Currently selected slot.
    current_slot_index: Option<usize>,
    /// List of slots.
    slots: Vec<Slot>,
    // Add file path or FD so modifying functions can save it to disk?
}

impl UpdaterState {
    fn new(cache_dir: String, release_version: String) -> Self {
        Self {
            cache_dir,
            release_version,
            current_slot_index: None,
            latest_downloaded_patch: None,
            failed_patches: Vec::new(),
            successful_patches: Vec::new(),
            slots: Vec::new(),
        }
    }
}

// fn compute_hash(path: &Path) -> anyhow::Result<String> {
//     use sha2::{Digest, Sha256};
//     use std::{fs, io};

//     let mut file = fs::File::open(&path)?;
//     let mut hasher = Sha256::new();
//     let n = io::copy(&mut file, &mut hasher)?;
//     let hash = hasher.finalize();
//     Ok(format!("{:x}", hash))
// }

impl UpdaterState {
    pub fn is_known_good_patch(&self, patch: &PatchInfo) -> bool {
        self.successful_patches.iter().any(|v| v == &patch.number)
    }

    pub fn is_known_bad_patch(&self, patch: &PatchInfo) -> bool {
        self.failed_patches.iter().any(|v| v == &patch.number)
    }

    pub fn mark_patch_as_bad(&mut self, patch: &PatchInfo) {
        if self.is_known_good_patch(patch) {
            warn!("Tried to report failed launch for a known good patch.  Ignoring.");
            return;
        }

        if self.is_known_bad_patch(patch) {
            return;
        }
        info!("Marking patch {} as bad", patch.number);
        self.failed_patches.push(patch.number.clone());
    }

    pub fn mark_patch_as_good(&mut self, patch: &PatchInfo) {
        if self.is_known_bad_patch(patch) {
            warn!("Tried to report successful launch for a known bad patch.  Ignoring.");
            return;
        }

        if self.is_known_good_patch(patch) {
            return;
        }
        self.successful_patches.push(patch.number.clone());
    }

    fn load(cache_dir: &str) -> anyhow::Result<Self> {
        // Load UpdaterState from disk
        let path = Path::new(cache_dir).join("state.json");
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        // TODO: Now that we depend on serde_yaml for shorebird.yaml
        // we could use yaml here instead of json.
        let state = serde_json::from_reader(reader)?;
        Ok(state)
    }

    pub fn load_or_new_on_error(cache_dir: &str, release_version: &str) -> Self {
        let loaded = Self::load(cache_dir).unwrap_or_else(|e| {
            warn!("Failed to load updater state: {}", e);
            Self::new(cache_dir.to_owned(), release_version.to_owned())
        });
        if loaded.release_version != release_version {
            warn!("Release version changed, clearing updater state");
            Self::new(cache_dir.to_owned(), release_version.to_owned())
        } else {
            loaded
        }
    }

    pub fn save(&self) -> anyhow::Result<()> {
        // Save UpdaterState to disk
        std::fs::create_dir_all(&self.cache_dir)?;
        let path = Path::new(&self.cache_dir).join("state.json");
        let file = File::create(path)?;
        let writer = BufWriter::new(file);
        serde_json::to_writer_pretty(writer, self)?;
        Ok(())
    }

    /// This is NOT the current booted path (we don't keep that in memory yet).
    /// This is the patch that is selected in the state.json, which may or may
    /// not be the one that is booted, but will be the one used next boot.
    pub fn current_patch(&self) -> Option<PatchInfo> {
        if self.slots.is_empty() {
            return None;
        }
        if let Some(slot_index) = self.current_slot_index {
            if slot_index >= self.slots.len() {
                return None;
            }
            let slot = &self.slots[slot_index];
            // Otherwise return the version info from the current slot.
            return Some(slot.to_patch_info());
        }
        None
    }

    fn validate_slot(&self, slot: &Slot) -> bool {
        // Check if the patch is known bad.
        if self.is_known_bad_patch(&slot.to_patch_info()) {
            return false;
        }
        if PathBuf::from(&slot.path).exists() {
            return true;
        }
        // TODO: This should also check if the hash matches?
        // let hash = compute_hash(&PathBuf::from(&slot.path));
        // if let Ok(hash) = hash {
        //     if hash == slot.hash {
        //         return true;
        //     }
        //     error!("Hash mismatch for slot: {:?}", slot);
        // }
        false
    }

    fn latest_bootable_slot(&self) -> Option<usize> {
        // Find the latest slot that has a patch that is not bad.
        // Sort the slots by patch number, then return the highest
        // patch number that is not bad.
        let mut slots = self.slots.clone();
        slots.sort_by(|a, b| a.patch_number.cmp(&b.patch_number));
        slots.reverse();
        for slot in slots {
            if self.validate_slot(&slot) {
                return Some(slot.patch_number);
            }
        }
        None
    }

    pub fn activate_latest_bootable_patch(&mut self) -> Result<(), UpdateError> {
        self.set_current_slot(self.latest_bootable_slot());
        self.save().map_err(|_| UpdateError::FailedToSaveState)
    }

    fn available_slot(&self) -> usize {
        // Assume we only use two slots and pick the one that's not current.
        if self.slots.is_empty() {
            return 0;
        }
        if let Some(slot_index) = self.current_slot_index {
            if slot_index == 0 {
                return 1;
            }
        }
        return 0;
    }

    fn clear_slot(&mut self, index: usize) {
        if self.slots.len() < index + 1 {
            return;
        }
        self.slots[index] = Slot::default();
    }

    fn set_slot(&mut self, index: usize, slot: Slot) {
        info!("Setting slot {} to {:?}", index, slot);
        if self.slots.len() < index + 1 {
            // Make sure we're not filling with empty slots.
            assert!(self.slots.len() == index);
            self.slots.resize(index + 1, Slot::default());
        }
        // Set the given slot to the given version.
        self.slots[index] = slot
    }

    fn slot_dir(&self, index: usize) -> String {
        Path::new(&self.cache_dir)
            .join(format!("slot_{}", index))
            .to_str()
            .unwrap()
            .to_owned()
    }

    pub fn install_patch(&mut self, patch: PatchInfo) -> anyhow::Result<()> {
        let slot_index = self.available_slot();
        let slot_dir_string = self.slot_dir(slot_index);
        let slot_dir = PathBuf::from(&slot_dir_string);

        // Clear the slot.
        self.clear_slot(slot_index); // Invalidate the slot.
        self.save()?;
        if slot_dir.exists() {
            std::fs::remove_dir_all(&slot_dir)?;
        }
        std::fs::create_dir_all(&slot_dir)?;

        if self.is_known_bad_patch(&patch) {
            return Err(UpdateError::InvalidArgument(
                "patch".to_owned(),
                format!("Refusing to install known bad patch: {:?}", patch),
            )
            .into());
        }

        // Move the artifact into the slot.
        let artifact_path = slot_dir.join("dlc.vmcode");
        std::fs::rename(&patch.path, &artifact_path)?;

        // Update the state to include the new slot.
        self.set_slot(
            slot_index,
            Slot {
                path: artifact_path.to_str().unwrap().to_owned(),
                patch_number: patch.number,
            },
        );
        self.set_current_slot(Some(slot_index));

        if (self.latest_downloaded_patch.is_none())
            || (self.latest_downloaded_patch.unwrap() < patch.number)
        {
            self.latest_downloaded_patch = Some(patch.number);
        } else {
            warn!(
                "Installed patch {} but latest downloaded patch is {:?}",
                patch.number, self.latest_downloaded_patch
            );
        }
        self.save()?;
        Ok(())
    }

    pub fn set_current_slot(&mut self, maybe_index: Option<usize>) {
        self.current_slot_index = maybe_index;
    }
    pub fn latest_patch_number(&self) -> Option<usize> {
        self.latest_downloaded_patch
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use tempdir::TempDir;

    use crate::cache::{PatchInfo, UpdaterState};

    fn test_state(tmp_dir: &TempDir) -> UpdaterState {
        let cache_dir = tmp_dir.path().to_str().unwrap().to_string();
        UpdaterState::new(cache_dir, "1.0.0".to_string())
    }

    fn fake_patch(tmp_dir: &TempDir, number: usize) -> super::PatchInfo {
        let path = PathBuf::from(tmp_dir.path()).join(format!("patch_{}", number));
        std::fs::write(&path, "fake patch").unwrap();
        PatchInfo {
            number,
            path: path.to_str().unwrap().to_owned(),
        }
    }

    #[test]
    fn current_patch_does_not_crash() {
        let tmp_dir = TempDir::new("example").unwrap();
        let mut state = test_state(&tmp_dir);
        assert_eq!(state.current_patch(), None);
        state.current_slot_index = Some(3);
        assert_eq!(state.current_patch(), None);
        state.slots.push(super::Slot::default());
        // This used to crash, where index was bad, but slots were not empty.
        assert_eq!(state.current_patch(), None);
    }

    #[test]
    fn release_version_changed() {
        let tmp_dir = TempDir::new("example").unwrap();
        let mut state = test_state(&tmp_dir);
        state.latest_downloaded_patch = Some(1);
        state.save().unwrap();
        let loaded = UpdaterState::load_or_new_on_error(&state.cache_dir, &state.release_version);
        assert_eq!(loaded.latest_downloaded_patch, Some(1));

        let loaded_after_version_change =
            UpdaterState::load_or_new_on_error(&state.cache_dir, "1.0.1");
        assert_eq!(loaded_after_version_change.latest_downloaded_patch, None);
    }

    #[test]
    fn latest_downloaded_patch() {
        let tmp_dir = TempDir::new("example").unwrap();
        let mut state = test_state(&tmp_dir);
        assert_eq!(state.latest_downloaded_patch, None);
        state.install_patch(fake_patch(&tmp_dir, 1)).unwrap();
        assert_eq!(state.latest_downloaded_patch, Some(1));
        state.install_patch(fake_patch(&tmp_dir, 2)).unwrap();
        assert_eq!(state.latest_downloaded_patch, Some(2));
        state.install_patch(fake_patch(&tmp_dir, 1)).unwrap();
        assert_eq!(state.latest_downloaded_patch, Some(2));
    }

    #[test]
    fn do_not_install_known_bad_patch() {
        let tmp_dir = TempDir::new("example").unwrap();
        let mut state = test_state(&tmp_dir);
        let bad_patch = fake_patch(&tmp_dir, 1);
        state.mark_patch_as_bad(&bad_patch);
        assert!(state.install_patch(bad_patch).is_err());
    }
}
