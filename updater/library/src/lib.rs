// Declare that the c_api.rs file exists and is a public sub-namespace.
// C doesn't care about the namespaces, but Rust does.
pub mod c_api;

// Declare that the updater.rs file/module exists, but don't make it public.
mod updater;

// Take all public items from the updater namespace and make them public.
pub use self::updater::*;

#[macro_use]
extern crate log;
