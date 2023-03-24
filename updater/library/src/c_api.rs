// This file handles translating the updater library's types into C types.

// Currently manually prefixing all functions with "shorebird_" to avoid
// name collisions with other libraries.
// cbindgen:prefix-with-name could do this for us.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::updater;

/// Struct containing configuration parameters for the updater.
/// Passed to all updater functions.
/// NOTE: If this struct is changed all language bindings must be updated.
#[repr(C)]
pub struct AppParameters {
    /// release_version, required.  Named version of the app, off of which updates
    /// are based.  Can be either a version number or a hash.
    pub release_version: *const libc::c_char,

    /// Path to the original aot library, required.  For Flutter apps this
    /// is the path to the bundled libapp.so.  May be used for compression
    /// downloaded artifacts.
    pub original_libapp_path: *const libc::c_char,

    /// Path to the app's libflutter.so, required.  May be used for ensuring
    /// downloaded artifacts are compatible with the Flutter/Dart versions
    /// used by the app.  For Flutter apps this should be the path to the
    /// bundled libflutter.so.  For Dart apps this should be the path to the
    /// dart executable.
    pub vm_path: *const libc::c_char,

    /// Path to cache_dir where the updater will store downloaded artifacts.
    pub cache_dir: *const libc::c_char,
}

fn to_rust(c_string: *const libc::c_char) -> String {
    unsafe { CStr::from_ptr(c_string).to_str().unwrap() }.to_string()
}

fn app_config_from_c(c_params: *const AppParameters) -> updater::AppConfig {
    let c_params_ref = unsafe { &*c_params };

    updater::AppConfig {
        cache_dir: to_rust(c_params_ref.cache_dir),
        release_version: to_rust(c_params_ref.release_version),
        original_libapp_path: to_rust(c_params_ref.original_libapp_path),
        vm_path: to_rust(c_params_ref.vm_path),
    }
}

/// Configures updater.  First parameter is a struct containing configuration
/// from the running app.  Second parameter is a YAML string containing
/// configuration compiled into the app.
#[no_mangle]
pub extern "C" fn shorebird_init(c_params: *const AppParameters, c_yaml: *const libc::c_char) {
    let config = app_config_from_c(c_params);

    let yaml_string = to_rust(c_yaml);
    let result = updater::init(config, &yaml_string);
    match result {
        Ok(_) => {}
        Err(e) => {
            error!("Error initializing updater: {:?}", e);
        }
    }
}

/// Return the active version of the app, or NULL if there is no active version.
#[no_mangle]
pub extern "C" fn shorebird_active_patch_number() -> *mut c_char {
    let patch = updater::active_patch();
    match patch {
        Some(v) => {
            let c_patch = CString::new(v.number.to_string()).unwrap();
            c_patch.into_raw()
        }
        None => std::ptr::null_mut(),
    }
}

/// Return the path to the active version of the app, or NULL if there is no
/// active version.
#[no_mangle]
// rename to shorebird_patch_path
pub extern "C" fn shorebird_active_path() -> *mut c_char {
    let version = updater::active_patch();
    match version {
        Some(v) => {
            let c_version = CString::new(v.path).unwrap();
            c_version.into_raw()
        }
        None => std::ptr::null_mut(),
    }
}

/// Free a string returned by the updater library.
#[no_mangle]
pub extern "C" fn shorebird_free_string(c_string: *mut c_char) {
    unsafe {
        if c_string.is_null() {
            return;
        }
        drop(CString::from_raw(c_string));
    }
}

/// Check for an update.  Returns true if an update is available.
#[no_mangle]
pub extern "C" fn shorebird_check_for_update() -> bool {
    return updater::check_for_update();
}

/// Synchronously download an update if one is available.
#[no_mangle]
pub extern "C" fn shorebird_update() {
    updater::update();
}

/// Report that the app failed to launch.  This will cause the updater to
/// attempt to roll back to the previous version if this version has not
/// been launched successfully before.
#[no_mangle]
pub extern "C" fn shorebird_report_failed_launch() {
    let result = updater::report_failed_launch();
    match result {
        Ok(_) => {}
        Err(e) => {
            error!("Error recording launch failure: {:?}", e);
        }
    }
}
