// This is a required file for rust libraries which declares what files are
// part of the library and what interfaces are public from the library.

// Declare that the c_api.rs file exists and is a public sub-namespace.
// C doesn't care about the namespaces, but Rust does.
pub mod c_api;

// Declare other .rs file/module exists, but make them public.
mod cache;
mod config;
mod logging;
mod network;
mod updater;

// Take all public items from the updater namespace and make them public.
pub use self::updater::*;

// Exposes error!(), info!(), etc macros.
#[macro_use]
extern crate log;
