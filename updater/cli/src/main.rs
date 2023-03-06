extern crate updater;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(author, version, about, long_about = None, arg_required_else_help=true)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    Check {},
    Current {},
    Update {},
}

fn main() {
    let cli = Cli::parse();

    let config = updater::AppConfig {
        client_id: "demo".to_string(),
        cache_dir: None,
        // base_url: "http://localhost:8080",
        // channel: "stable",
    };

    // You can check for the existence of subcommands, and if found use their
    // matches just as you would the top level cmd
    match &cli.command {
        Some(Commands::Check {}) => {
            let needs_update = updater::check_for_update(&config);
            println!("Checking for update...");
            if needs_update {
                println!("Update needed.");
            } else {
                println!("No update needed.");
            }
        }
        Some(Commands::Current {}) => {
            let version = updater::active_version(&config);
            println!("Current version info:");
            match version {
                Some(v) => {
                    println!("path: {:?}", v.path);
                    println!("hash: {:?}", v.hash);
                    println!("version: {:?}", v.version);
                }
                None => {
                    println!("None");
                }
            }
        }
        Some(Commands::Update {}) => {
            let status = updater::update(&config);
            println!("Update: {}", status);
        }
        None => {}
    }
}
