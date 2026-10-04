mod inject;
mod output;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{ArgAction, Parser};
use regex::Regex;
use walkdir::WalkDir;

use inject::Injector;
use output::{error, trace, warning};

/// Installs the git flow (AVH edition) hooks in git repositories
#[derive(Parser)]
#[command(version)]
struct Cli {
    /// The repositories to inject the hooks into
    #[arg(required = true, value_name = "REPOSITORY")]
    repositories: Vec<PathBuf>,

    /// Path to the source folder used to detect the language, relative to the repository. Can be repeated [default: . src backend src/backend]
    #[arg(long = "src", value_name = "PATH")]
    sources: Vec<String>,

    /// Do not use pull requests before finishing releases/hotfixes/features
    #[arg(long = "no-pull-request", visible_alias = "no-pr")]
    no_pull_request: bool,

    /// Exclude the folders matching this regular expression when used with --recursive. Can be repeated
    #[arg(long, value_name = "PATTERN", value_parser = Regex::new)]
    exclude: Vec<Regex>,

    /// Inject hooks in all the git repositories found in the given folders
    #[arg(short, long)]
    recursive: bool,

    /// Copy the hooks from this folder instead of the ones embedded in hook-it
    #[arg(long, value_name = "PATH")]
    hooks_dir: Option<PathBuf>,

    /// Do not execute any command, just display what would be done
    #[arg(long, visible_alias = "dry-run", alias = "dry_run")]
    noop: bool,

    /// Do not display any message
    #[arg(long)]
    quiet: bool,

    /// Increase verbosity, can be repeated
    #[arg(short, long, action = ArgAction::Count)]
    verbose: u8,

    /// Assume yes to all questions (there are no questions, kept for compatibility)
    #[arg(short = 'y', long = "yes", aliases = ["assumeyes", "assume-yes", "assume_yes"], hide = true)]
    _yes: bool,

    /// Force operations (does nothing, kept for compatibility)
    #[arg(long, hide = true)]
    force: bool,
}

/// Tells if the path matches any of the exclude patterns
fn is_excluded(path: &Path, excludes: &[Regex]) -> bool {
    let path = path.to_string_lossy();
    excludes.iter().any(|pattern| {
        trace!("    checking {path} against pattern {pattern}");
        pattern.is_match(&path)
    })
}

/// Finds all the git repositories in the given folders
fn find_repositories(folders: &[PathBuf], excludes: &[Regex]) -> Vec<PathBuf> {
    let mut repositories = Vec::new();

    trace!("Building folders from arguments");
    trace!("  Excluding {excludes:?}");
    for folder in folders {
        trace!(">>> Processing {}", folder.display());
        if is_excluded(folder, excludes) {
            trace!("{} should be excluded", folder.display());
            continue;
        }
        let mut entries = WalkDir::new(folder).sort_by_file_name().into_iter();
        while let Some(entry) = entries.next() {
            let entry = match entry {
                Ok(entry) => entry,
                Err(err) => {
                    warning!("{err}");
                    continue;
                }
            };
            if !entry.file_type().is_dir() || entry.file_name() != ".git" {
                continue;
            }
            // Nothing to look for inside a .git folder
            entries.skip_current_dir();
            if is_excluded(entry.path(), excludes) {
                trace!("{} should be excluded", entry.path().display());
                continue;
            }
            if let Some(repository) = entry.path().parent() {
                repositories.push(repository.to_path_buf());
            }
        }
    }
    repositories.sort();
    repositories.dedup();
    repositories
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    output::set_verbosity(if cli.quiet { 0 } else { cli.verbose });
    if cli.no_pull_request {
        warning!("The hooks will NOT use pull requests before finishing releases/hotfixes/features");
    }
    if cli.force {
        warning!("This program will force operations to be executed");
    }
    if cli.noop {
        warning!("This program will execute in dry mode, your system will not be modified");
    }

    let injector = Injector {
        git: std::env::var("GIT").unwrap_or_else(|_| "git".into()),
        hooks_dir: std::env::var("DEFAULT_HOOKS_DIR").unwrap_or_else(|_| ".git/hooks".into()).into(),
        sources: cli.sources,
        hooks_source: cli.hooks_dir,
        use_pull_requests: !cli.no_pull_request,
        noop: cli.noop,
    };

    let repositories = match cli.recursive {
        true => find_repositories(&cli.repositories, &cli.exclude),
        false => cli.repositories,
    };
    for repository in &repositories {
        output::title(&format!("Processing Folder: {}", repository.display()));
        if let Err(err) = injector.inject(repository) {
            error!("{err}");
            return ExitCode::FAILURE;
        }
    }
    ExitCode::SUCCESS
}
