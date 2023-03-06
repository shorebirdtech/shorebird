use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::updater;

fn app_config_from_c(c_client_id: *const c_char, c_cache_dir: *const c_char) -> updater::AppConfig {
    let client_id = unsafe { CStr::from_ptr(c_client_id) }.to_str().unwrap();
    let cache_dir = if c_cache_dir == std::ptr::null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(c_cache_dir).to_str().unwrap() }.to_string())
    };

    updater::AppConfig {
        client_id: client_id.to_string(),
        cache_dir: cache_dir,
    }
}

#[no_mangle]
pub extern "C" fn active_version(
    c_client_id: *const c_char,
    c_cache_dir: *const c_char,
) -> *mut c_char {
    let config = app_config_from_c(c_client_id, c_cache_dir);
    let version = updater::active_version(&config);
    match version {
        Some(v) => {
            let c_version = CString::new(v.version).unwrap();
            c_version.into_raw()
        }
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn active_path(
    c_client_id: *const c_char,
    c_cache_dir: *const c_char,
) -> *mut c_char {
    let config = app_config_from_c(c_client_id, c_cache_dir);
    let version = updater::active_version(&config);
    match version {
        Some(v) => {
            let c_version = CString::new(v.path).unwrap();
            c_version.into_raw()
        }
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn free_string(c_string: *mut c_char) {
    unsafe {
        if c_string.is_null() {
            return;
        }
        drop(CString::from_raw(c_string));
    }
}

#[no_mangle]
pub extern "C" fn check_for_update(c_client_id: *const c_char, c_cache_dir: *const c_char) -> bool {
    let config = app_config_from_c(c_client_id, c_cache_dir);
    return updater::check_for_update(&config);
}

#[no_mangle]
pub extern "C" fn update(c_client_id: *const c_char, c_cache_dir: *const c_char) {
    let config = app_config_from_c(c_client_id, c_cache_dir);
    updater::update(&config);
}
