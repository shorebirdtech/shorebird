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
        cache_dir: "updater_cache".to_owned(),
        release_version: "0.1.0".to_owned(),
        original_libapp_paths: vec!["libapp.so".to_owned()],
        vm_path: "libflutter.so".to_owned(),
    };
    let yaml_str = "
app_id: demo
channel: stable
base_url: http://localhost:8000
";
    updater::init(config, yaml_str).expect("init failed");

    // You can check for the existence of subcommands, and if found use their
    // matches just as you would the top level cmd
    match &cli.command {
        Some(Commands::Check {}) => {
            let needs_update = updater::check_for_update();
            println!("Checking for update...");
            if needs_update {
                println!("Update needed.");
            } else {
                println!("No update needed.");
            }
        }
        Some(Commands::Current {}) => {
            let version = updater::active_patch();
            println!("Current version info:");
            match version {
                Some(v) => {
                    println!("path: {:?}", v.path);
                    println!("number: {:?}", v.number);
                }
                None => {
                    println!("None");
                }
            }
        }
        Some(Commands::Update {}) => {
            let status = updater::update();
            println!("Update: {}", status);
        }
        None => {}
    }
}
